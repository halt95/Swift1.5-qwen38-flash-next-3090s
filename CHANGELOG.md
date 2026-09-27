# Changelog

## v2.2.0-swift1.5 (2026-09-27)

First public release of this repository. There is no earlier public version and no upgrade path.

- Serves `halt95/Swift1.5-Qwen3.8-Flash-Next-W4A16-Merlin` (41 files, checksums in
  `release/checkpoint.sha256`): the Merlin checkpoint with the 300 dense tensors Swift 1.5 changed.
- Engine: Flash-Next v2.2.0, unchanged and not copied here
  (`halt95/qwen38-flash-next-3090s` tag `v2.2.0` = commit `cda592711239fa5061d59ef4858db4e68b217445`).
- Install route: `release/install-env.sh` clones the engine at that commit, asserts it and the launcher's sha256,
  downloads and verifies the two v2.2.0 release assets against the engine's `upstream/PIN-v2.2`, and runs the
  engine's own `scripts/build-v2.2.sh`.
- Serve entry: `serve/serve.sh`, the v2.2.0 launcher (`scripts/serve-v2.2.sh`, sha256 checked before start) with
  `SCALES` set to this checkpoint's sidecar and `xhigh` as the server default reasoning effort.
- KV-scale sidecar: `quant/kv_scales-swift-e4m3.json`, static FP8 K/V scales calibrated on this checkpoint.
- Evidence: bench card `benchmarks/2026-09-27/`, loop check `docs/loop-check.md`.
- Licences: `LICENSE` (Apache-2.0), `LICENSE-SWIFT` (Swift Open License v1.0), `LICENSE-QWEN` (Qwen Community
  License 1.0), `NOTICE`.
