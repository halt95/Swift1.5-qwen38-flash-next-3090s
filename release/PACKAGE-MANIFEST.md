# Package manifest

Every tracked file in this GitHub repository, with its Git mode and purpose. Hashes: `release/SHA256SUMS` holds the SHA-256 of every
tracked file except itself (this manifest included); check it from the repository root with
`sha256sum -c release/SHA256SUMS`. Checkpoint files are listed in `release/checkpoint.sha256`.

## Files

| file | mode | purpose |
|---|---|---|
| `.gitattributes` | 100644 | line-ending rule: every text file LF, PNG images binary |
| `.gitignore` | 100644 | keeps the installed engine (`engine/`), a checkpoint downloaded to `ckpt/`, Python bytecode and compile caches out of the repository |
| `CHANGELOG.md` | 100644 | changes by version |
| `LICENSE` | 100644 | Apache License 2.0, for this repository's scripts and documentation |
| `LICENSE-QWEN` | 100644 | Qwen Community License 1.0 text (the checkpoint and the sidecar) |
| `LICENSE-SWIFT` | 100644 | Swift Open License v1.0 text (the checkpoint and the sidecar) |
| `NOTICE` | 100644 | attribution: this repository, the engine (not included), UkisAI's notice, the checkpoint's sources and the changes made |
| `README.md` | 100644 | what this release is, how to install, serve and check it, results, licences |
| `benchmarks/2026-09-27/BENCH-CARD.md` | 100644 | the bench card: Merlin checkpoint and Swift 1.5 build, measured interleaved on 2026-09-27 |
| `benchmarks/2026-09-27/swift1.5-v2.2.0-ctx-itl-tpe.png` | 100644 | the bench card's chart (also shown in `README.md`) |
| `docs/loop-check.md` | 100644 | the repetition-loop check at `xhigh`: protocol, detector, pass rule, results |
| `quant/kv_scales-swift-e4m3.json` | 100644 | static FP8 E4M3 K/V scales calibrated on this checkpoint (sha256 `d211be1f3b0484d2e7d6592bf1dbd67fcfea89cdc22a389dab86b82df4f5fee5`, the same bytes as the checkpoint's `qsa_kv_scales_swift.json`); model-derived data under the Swift Open License v1.0 and the Qwen Community License 1.0 |
| `release/PACKAGE-MANIFEST.md` | 100644 | this file |
| `release/SHA256SUMS` | 100644 | SHA-256 of every tracked file except itself |
| `release/checkpoint.sha256` | 100644 | SHA-256 of the 41 checkpoint files, in `sha256sum -c` format (run inside the checkpoint directory) |
| `release/install-env.sh` | 100755 | installs the pinned engine into `engine/` (clone, commit and launcher assertions, release assets verified against the engine's pin file, the engine's own build) |
| `serve/serve.sh` | 100755 | the serve entry: the v2.2.0 launcher, sha256-checked, with this checkpoint's sidecar and the `xhigh` default |

## Engine pin

| | |
|---|---|
| repository | https://github.com/halt95/qwen38-flash-next-3090s |
| tag | `v2.2.0` |
| commit | `cda592711239fa5061d59ef4858db4e68b217445` |
| launcher | `scripts/serve-v2.2.sh`, sha256 `f599dac7a9861ad3358d56c14636a66c7e4bb3ce221d9804612ce41bf2d7009f` |
| build | `scripts/build-v2.2.sh`, with the release assets `v2.2.0-from-upstream-v0.30.0.bundle.gz` and `build-artifacts-sm86-py313-cu130-v2.2.0.tar.gz` from the `v2.2.0` GitHub release, verified against `upstream/PIN-v2.2` at that commit |

The engine is not copied into this repository; `release/install-env.sh` installs it and `serve/serve.sh` refuses any
other launcher.

## Checkpoint

| | |
|---|---|
| repository | https://huggingface.co/halt95/Swift1.5-Qwen3.8-Flash-Next-W4A16-Merlin |
| revision | `7ee538a4cf45d91c7bd71124c66038ac52b3a0f7` |
| files | 41, listed with their SHA-256 in `release/checkpoint.sha256` |

The checkpoint's own `SHA256SUMS` on Hugging Face covers the same 41 files.
