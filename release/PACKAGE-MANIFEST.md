# Package manifest

Every tracked file in this GitHub repository, with its Git mode and purpose. Hashes: `release/SHA256SUMS` holds the SHA-256 of every
tracked file except itself (this manifest included); check it from the repository root with
`sha256sum -c release/SHA256SUMS`. Checkpoint files are listed in `release/checkpoint.sha256`.

## Files

| file | mode | purpose |
|---|---|---|
| `.gitattributes` | 100644 | line-ending rule: every text file LF, PNG images binary |
| `.dockerignore` | 100644 | allow-list for the container build context: the install and serve files and the sidecar only |
| `.gitignore` | 100644 | keeps the installed engine (`engine/`), a checkpoint downloaded to `ckpt/`, Python bytecode and compile caches out of the repository |
| `CHANGELOG.md` | 100644 | changes by version |
| `LICENSE` | 100644 | Apache License 2.0, for this repository's scripts and documentation |
| `LICENSE-QWEN` | 100644 | Qwen Community License 1.0 text (the checkpoint and the sidecar) |
| `LICENSE-SWIFT` | 100644 | Swift Open License v1.0 text (the checkpoint and the sidecar) |
| `Dockerfile` | 100644 | the container image: python:3.13-slim-bookworm (digest-pinned) + `release/install-env.sh` + `serve/serve.sh` via `serve/docker-entrypoint.sh`; the checkpoint is mounted at `/model` |
| `NOTICE` | 100644 | attribution: this repository, the engine (not included), UkisAI's notice, the checkpoint's sources and the changes made |
| `README.md` | 100644 | what this release is, why use it, what you need, how to install, serve and talk to it, what is new, limitations, credits and licence terms |
| `benchmarks/2026-09-27/BENCH-CARD.md` | 100644 | the v2.2.0-swift1.5 bench card: Merlin checkpoint and Swift 1.5 build, measured interleaved on 2026-09-27 |
| `benchmarks/2026-09-27/swift1.5-v2.2.0-ctx-itl-tpe.png` | 100644 | the v2.2.0-swift1.5 bench card's chart |
| `benchmarks/2026-10-06/BENCH-CARD.md` | 100644 | the v2.5.1-swift1.5 bench card: this checkpoint on the v2.5.1 engine, release gate of 2026-10-06 |
| `docker-compose.yml` | 100644 | `MODEL_DIR=... docker compose up -d`: four GPUs, `/model` read-only, the `/cache` volume, port 8000 |
| `docs/images/swift15-v2.5.1-summary.png` | 100644 | the summary image at the top of the README and the Hugging Face card |
| `docs/loop-check.md` | 100644 | the repetition-loop check at `xhigh`: protocol, detector, pass rule, results |
| `docs/reference.md` | 100644 | reference: install and serve scripts and their variables, requirements, container, checks, troubleshooting, known behaviours, how the checkpoint is built, credit, licence detail |
| `quant/kv_scales-swift-e4m3.json` | 100644 | static FP8 E4M3 K/V scales calibrated on this checkpoint (sha256 `d211be1f3b0484d2e7d6592bf1dbd67fcfea89cdc22a389dab86b82df4f5fee5`, the same bytes as the checkpoint's `qsa_kv_scales_swift.json`); model-derived data under the Swift Open License v1.0 and the Qwen Community License 1.0 |
| `release/PACKAGE-MANIFEST.md` | 100644 | this file |
| `release/SHA256SUMS` | 100644 | SHA-256 of every tracked file except itself |
| `release/checkpoint.sha256` | 100644 | SHA-256 of the 41 checkpoint files, in `sha256sum -c` format (run inside the checkpoint directory) |
| `release/install-env.sh` | 100755 | installs the pinned engine into `engine/` (clone, commit and launcher assertions, release assets verified against the engine's pin file, the engine's own build) |
| `serve/docker-entrypoint.sh` | 100755 | container entrypoint: checks the mounted checkpoint, GPUs, the nvcc-versus-driver rule and `/dev/shm`, then execs `serve/serve.sh` |
| `serve/serve.sh` | 100755 | the serve entry: the v2.5.1 launcher, sha256-checked, with this checkpoint's sidecar and the `xhigh` default |

## Engine pin

| | |
|---|---|
| repository | https://github.com/halt95/qwen38-flash-next-3090s |
| tag | `v2.5.1` |
| commit | `352e0065bd28686d60d8b13c1d2b16783ade6b2d` |
| launcher | `scripts/serve-v2.5.sh`, sha256 `22eb5201ec7f2c7f5c549cc6a63777ca4157c0e373bdea1e53c9e26e7314e912` |
| build | `scripts/build-v2.5.sh`, with the release assets `v2.5.1-from-upstream-v0.30.0.bundle.gz` (from the `v2.5.1` GitHub release; uncompressed sha256 `d904e4685877e56b57c9a23a621b537239ba6316ad238c3848c5f03437d03d7c`) and `build-artifacts-sm86-py313-cu130-v2.2.0.tar.gz` (from the `v2.2.0` GitHub release, reused unchanged by v2.5.1; sha256 `cdca5ffcb3003d15e00896f0969134e16d7bfbe0a3c6dfe10698bec32573f592`), verified against `upstream/PIN-v2.5` at that commit |

The engine is not copied into this repository; `release/install-env.sh` installs it and `serve/serve.sh` refuses any
other launcher.

## Checkpoint

| | |
|---|---|
| repository | https://huggingface.co/halt95/Swift1.5-Qwen3.8-Flash-Next-W4A16-Merlin |
| revision | `3c9a1159eac1282463b06313de7dd9262edf8b58` |
| files | 41, listed with their SHA-256 in `release/checkpoint.sha256` |

The checkpoint's own `SHA256SUMS` on Hugging Face covers the same 41 files.
