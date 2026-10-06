#!/usr/bin/env bash
# Install the serving engine for this release: the unchanged Flash-Next v2.5.1 engine
# (https://github.com/halt95/qwen38-flash-next-3090s, tag v2.5.1 = commit 352e0065bd28686d60d8b13c1d2b16783ade6b2d),
# built by that repository's own scripts/build-v2.5.sh.
#
#   release/install-env.sh                 (ENGINE=/path/to/engine to put it elsewhere; default <repo>/engine)
#
# Steps, each with its exit code checked:
#   1. clone the engine repository into $ENGINE and check out the pinned commit; assert `git rev-parse HEAD`, a clean
#      tracked tree and the sha256 of scripts/serve-v2.5.sh (22eb5201...), the launcher serve/serve.sh accepts;
#   2. download the two release assets build-v2.5.sh needs next to it (it does not download them itself) and verify
#      both against the engine's upstream/PIN-v2.5 (its bundle hash is of the uncompressed bundle): the v2.5.1 delta
#      bundle (a v2.5.1 release asset, shipped gzipped; decompressed here) and the compiled-ops tarball (a v2.2.0
#      release asset that v2.5.1 reuses unchanged: v2.5.1 changes no compiled code);
#   3. run `scripts/build-v2.5.sh ./vllm-v2.5 ./venv-v2.5` inside $ENGINE: it fetches vLLM v0.30.0 from GitHub, applies
#      the bundle, asserts commit and tree hash, builds a fresh Python 3.13 venv from the engine's pinned requirements
#      (PyPI) and installs and re-verifies the compiled ops.
# A re-run reuses a checkout at the pinned commit and assets that verify; build-v2.5.sh resumes and re-verifies.
#
# Needs: Linux x86-64 with glibc >= 2.34, git, curl, gzip, tar, sha256sum, Python 3.13 with venv as `python3.13` on
# PATH, network access to GitHub and PyPI. Serving also needs a C/C++ compiler, ninja, the Python 3.13 headers and an
# NVIDIA driver with CUDA >= 13.0 (docs/reference.md, Build and serve).
set -euo pipefail

REPO_URL=https://github.com/halt95/qwen38-flash-next-3090s.git
COMMIT=352e0065bd28686d60d8b13c1d2b16783ade6b2d
LAUNCHER_SHA256=22eb5201ec7f2c7f5c549cc6a63777ca4157c0e373bdea1e53c9e26e7314e912
# the bundle is a v2.5.1 release asset; the compiled-ops tarball is v2.2.0's, reused unchanged by v2.5.1
BUNDLE_ASSETS=https://github.com/halt95/qwen38-flash-next-3090s/releases/download/v2.5.1
ARTIFACTS_ASSETS=https://github.com/halt95/qwen38-flash-next-3090s/releases/download/v2.2.0

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENGINE="${ENGINE:-$HERE/engine}"
case "$ENGINE" in /*) ;; *) ENGINE="$PWD/$ENGINE" ;; esac

fail(){ echo "install-env: $*" >&2; exit 1; }
sha_ok(){ [ "$(sha256sum "$2" | cut -d' ' -f1)" = "$1" ]; }
for t in git curl gzip tar sha256sum; do command -v "$t" >/dev/null || fail "missing tool: $t"; done

# 1. the engine checkout
if [ -e "$ENGINE" ]; then
  # must be its own repository (not a directory inside another checkout) at the pinned commit
  # (an empty --show-prefix means $ENGINE is the top of its own work tree)
  prefix="$(git -C "$ENGINE" rev-parse --show-prefix 2>/dev/null || echo none)"
  [ -z "$prefix" ] \
    || fail "refusing: $ENGINE exists and is not a git checkout; move it away or set ENGINE= to a new path"
  got="$(git -C "$ENGINE" rev-parse -q --verify HEAD 2>/dev/null || true)"
  [ "$got" = "$COMMIT" ] \
    || fail "refusing: $ENGINE is at ${got:-no commit}, not the pinned $COMMIT; move it away or set ENGINE= to a new path"
  echo "engine: reusing $ENGINE"
else
  git clone -q "$REPO_URL" "$ENGINE" || fail "git clone $REPO_URL failed"
  git -C "$ENGINE" -c advice.detachedHead=false checkout -q --detach "$COMMIT" || fail "checkout of $COMMIT failed"
fi
got="$(git -C "$ENGINE" rev-parse HEAD)" || fail "git rev-parse HEAD failed in $ENGINE"
[ "$got" = "$COMMIT" ] || fail "$ENGINE HEAD is $got, expected $COMMIT"
st="$(git -C "$ENGINE" status --porcelain --untracked-files=no)" || fail "git status failed in $ENGINE"
[ -z "$st" ] || fail "$ENGINE has modified tracked files; use a fresh ENGINE path"
sha_ok "$LAUNCHER_SHA256" "$ENGINE/scripts/serve-v2.5.sh" \
  || fail "$ENGINE/scripts/serve-v2.5.sh sha256 is not $LAUNCHER_SHA256"
echo "engine: $ENGINE at $COMMIT (v2.5.1), serve-v2.5.sh sha256 verified"

# 2. the release assets, verified against the engine's own pin file
PIN="$ENGINE/upstream/PIN-v2.5"
[ -f "$PIN" ] || fail "$PIN missing"
# shellcheck disable=SC1090
. "$PIN" || fail "could not read $PIN"
for v in bundle bundle_sha256 artifacts_tar artifacts_sha256; do
  [ -n "${!v:-}" ] || fail "$PIN does not define $v"
done
fetch(){  # $1 url, $2 destination; to .part first, so an interrupted download never takes the final name
  rm -f "$2.part"
  if curl -fsSL --retry 3 -o "$2.part" "$1"; then mv "$2.part" "$2"; else rm -f "$2.part"; fail "download failed: $1"; fi
}

BUNDLE="$ENGINE/$bundle"
if [ -f "$BUNDLE" ]; then
  sha_ok "$bundle_sha256" "$BUNDLE" || fail "$BUNDLE exists but its sha256 is not the pinned one; delete it and re-run"
else
  fetch "$BUNDLE_ASSETS/$bundle.gz" "$BUNDLE.gz"
  gzip -dc "$BUNDLE.gz" > "$BUNDLE.part" || { rm -f "$BUNDLE.part"; fail "could not decompress $BUNDLE.gz"; }
  sha_ok "$bundle_sha256" "$BUNDLE.part" || { rm -f "$BUNDLE.part" "$BUNDLE.gz"; fail "bundle sha256 mismatch"; }
  mv "$BUNDLE.part" "$BUNDLE"; rm -f "$BUNDLE.gz"
fi
echo "asset: $bundle sha256 verified"

ARTIFACTS="$ENGINE/$artifacts_tar"
if [ -f "$ARTIFACTS" ]; then
  sha_ok "$artifacts_sha256" "$ARTIFACTS" || fail "$ARTIFACTS exists but its sha256 is not the pinned one; delete it and re-run"
else
  fetch "$ARTIFACTS_ASSETS/$artifacts_tar" "$ARTIFACTS"
  sha_ok "$artifacts_sha256" "$ARTIFACTS" || { rm -f "$ARTIFACTS"; fail "$artifacts_tar sha256 mismatch"; }
fi
echo "asset: $artifacts_tar sha256 verified"

# 3. the engine's own build
(cd "$ENGINE" && BUNDLE="$BUNDLE" ARTIFACTS="$ARTIFACTS" scripts/build-v2.5.sh ./vllm-v2.5 ./venv-v2.5) \
  || fail "scripts/build-v2.5.sh failed (its message is above)"
[ -f "$ENGINE/vllm-v2.5/.v2.5-build-products" ] && [ -x "$ENGINE/venv-v2.5/bin/vllm" ] \
  || fail "build finished but $ENGINE/vllm-v2.5 or $ENGINE/venv-v2.5 is incomplete"
echo "INSTALL OK: ENGINE=$ENGINE (TREE=$ENGINE/vllm-v2.5 VENV=$ENGINE/venv-v2.5)"
echo "next: serve/serve.sh /path/to/Swift1.5-Qwen3.8-Flash-Next-W4A16-Merlin"
