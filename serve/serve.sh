#!/usr/bin/env bash
# Serve halt95/Swift1.5-Qwen3.8-Flash-Next-W4A16-Merlin on 4x RTX 3090 with the unchanged Flash-Next v2.5.1 engine.
#
#   serve/serve.sh /path/to/Swift1.5-Qwen3.8-Flash-Next-W4A16-Merlin [extra vllm args]
#
# This is the published v2.5.1 launcher ($ENGINE/scripts/serve-v2.5.sh, sha256 22eb5201...) with this checkpoint's
# KV-scale sidecar passed through SCALES and `xhigh` as the server's default reasoning effort. The wrapper adds nothing
# else to the launcher's environment or command line. It refuses to start unless the launcher is that exact file
# (release/install-env.sh installs it) and the sidecar exists.
#
# Knobs:
#   ENGINE      the engine checkout (default: <repo>/engine, where release/install-env.sh puts it)
#   SCALES      the KV-scale sidecar (default: <repo>/quant/kv_scales-swift-e4m3.json; a relative path is resolved from
#               the current directory, by this script and by the launcher alike)
#   TREE, VENV  the built vLLM tree and venv (default: $ENGINE/vllm-v2.5 and $ENGINE/venv-v2.5, as install-env.sh
#               builds them); set only when unset
#   Every serve-v2.5.sh knob passes through unchanged: PORT (8000), HOST (127.0.0.1), MODEL_NAME (the names requests
#   use in "model"), CACHE_ROOT (compile cache; default $ENGINE/.vllm-cache-v2.5), COUNTERS (1 = the two logging-only
#   counters), and the others its header lists (PLE_HOME, GUARD, CUDA_HOME, AUTO_TOPO, ...).
#
# Extra arguments go to `vllm serve` after the launcher's own flags and after the xhigh default below. For a repeated
# flag the last value wins, so a later --default-chat-template-kwargs replaces the xhigh default.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LAUNCHER_SHA256=22eb5201ec7f2c7f5c549cc6a63777ca4157c0e373bdea1e53c9e26e7314e912

if [ "$#" -lt 1 ] || [ -z "$1" ]; then
  echo "usage: serve/serve.sh <checkpoint-dir> [extra vllm args]" >&2
  echo "  checkpoint: hf download halt95/Swift1.5-Qwen3.8-Flash-Next-W4A16-Merlin (README, Quick start)" >&2
  exit 2
fi
CKPT="$1"; shift
[ -f "$CKPT/config.json" ] || { echo "no config.json in $CKPT: pass the checkpoint directory" >&2; exit 1; }

ENGINE="${ENGINE:-$HERE/engine}"
case "$ENGINE" in /*) ;; *) ENGINE="$PWD/$ENGINE" ;; esac
LAUNCHER="$ENGINE/scripts/serve-v2.5.sh"
if [ ! -f "$LAUNCHER" ]; then
  echo "refusing to start: $LAUNCHER not found." >&2
  echo "  Install the engine first: release/install-env.sh (or set ENGINE= to an existing install)." >&2
  exit 1
fi
got="$(sha256sum "$LAUNCHER" | cut -d' ' -f1)"
if [ "$got" != "$LAUNCHER_SHA256" ]; then
  echo "refusing to start: $LAUNCHER is not the published v2.5.1 launcher" >&2
  echo "  (sha256 $got, expected $LAUNCHER_SHA256)." >&2
  echo "  Install the pinned engine with release/install-env.sh into a fresh ENGINE directory." >&2
  exit 1
fi

export SCALES="${SCALES:-$HERE/quant/kv_scales-swift-e4m3.json}"
[ -f "$SCALES" ] || { echo "refusing to start: KV-scale sidecar missing: $SCALES" >&2; exit 1; }
export TREE="${TREE:-$ENGINE/vllm-v2.5}" VENV="${VENV:-$ENGINE/venv-v2.5}"

exec "$LAUNCHER" "$CKPT" \
  --default-chat-template-kwargs '{"enable_thinking": true, "reasoning_effort": "xhigh"}' \
  "$@"
