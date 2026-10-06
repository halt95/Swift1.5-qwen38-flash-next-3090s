# Reference

The detail behind the [README](../README.md): what the install and serve scripts do, the container route, health
checks and troubleshooting, how the model is laid out on the four cards, capacity, known behaviours and how the
release is measured. Release notes are in [CHANGELOG.md](../CHANGELOG.md). The engine's own reference is
[halt95/qwen38-flash-next-3090s, docs/reference.md](https://github.com/halt95/qwen38-flash-next-3090s/blob/v2.5.1/docs/reference.md).

- [Overview](#overview)
- [Build and serve](#build-and-serve) (files, the bare-metal route, requirements, running without peer-to-peer)
- [Container](#container)
- [Check it's working](#check-its-working), [Troubleshooting](#troubleshooting)
- [Multi-GPU hosts and topology (opt-in)](#multi-gpu-hosts-and-topology-opt-in), [Running notes](#running-notes)
- [How it works](#how-it-works): [Hardware](#hardware), [The KV budget](#the-kv-budget), [Stack](#stack),
  [Checkpoint](#checkpoint), [Serving an agent](#serving-an-agent)
- [Benchmarks](#benchmarks) (what each card measures, the evidence boundary)
- [Known behaviours](#known-behaviours-of-the-qwen38-flash-next-architecture-in-vllm)
- [What ships next](#what-ships-next), [Credit](#credit), [Licence detail](#licence-detail)

## Overview

UkisAI's Swift 1.5 post-train of Qwen3.8-Flash-Next (125B MoE, ~6B activated per token, plus a 51B n-gram embedding
table and a one-layer MTP head; Gated DeltaNet linear attention, 512 experts, vision tower), as a 4-bit build on the
Merlin recipe, served with vLLM at its **full 262,144-token context** on four consumer Ampere cards: a **924,993-token**
FP8 KV pool, TP2 × PP2 + expert parallel, MTP K=3, `xhigh` reasoning by default. The current release,
**v2.5.1-swift1.5**, runs the unchanged Flash-Next v2.5.1 engine (the public vLLM `v0.30.0` tag plus 97 commits): agent
follow-up turns resume from cache on a 64-token grid, the KV pool is larger and prefill is faster than on v2.2.0.

## Build and serve

**If you already have a vLLM checkout, do not start the server next to it.** vLLM inspects the model registry in a
child process started with `python -m`, which puts the current directory ahead of `PYTHONPATH` on `sys.path`. A
`vllm/` directory beside you therefore wins over the tree you built. The engine's `scripts/serve-v2.5.sh` refuses to
start in that situation and tells you what to do; the container form cannot hit it at all.

| path | what |
|---|---|
| `release/install-env.sh` | clones the Flash-Next engine repository into `engine/` (or `ENGINE=`), checks out tag `v2.5.1` = commit `352e0065bd28686d60d8b13c1d2b16783ade6b2d` and asserts it, a clean tracked tree and the launcher's sha256; downloads the v2.5.1 delta bundle (a v2.5.1 release asset) and the compiled-ops tarball (a v2.2.0 release asset that v2.5.1 reuses unchanged) and verifies both against the engine's `upstream/PIN-v2.5`; then runs the engine's `scripts/build-v2.5.sh ./vllm-v2.5 ./venv-v2.5`. Every step checks its exit code; it refuses an existing `engine/` at another commit |
| `serve/serve.sh` | starts the engine's `scripts/serve-v2.5.sh` (sha256 `22eb5201ec7f2c7f5c549cc6a63777ca4157c0e373bdea1e53c9e26e7314e912`, checked before start) with this checkpoint's sidecar and the `xhigh` default; it adds nothing else to the launcher's environment or command line |
| `Dockerfile`, `docker-compose.yml`, `.dockerignore`, `serve/docker-entrypoint.sh` | the container: `release/install-env.sh` at image build, `serve/serve.sh` through the entrypoint, the checkpoint mounted at `/model`, the cache as a volume |
| `quant/kv_scales-swift-e4m3.json` | the static FP8 K/V scales recalibrated on this checkpoint (the same bytes as `qsa_kv_scales_swift.json` in the checkpoint) |
| `release/checkpoint.sha256` | checksums of the 41 checkpoint files (the same list as the checkpoint's own `SHA256SUMS`) |
| `release/SHA256SUMS`, `release/PACKAGE-MANIFEST.md` | checksums of every other file in this repository, and what each file is |
| `engine/` (not tracked) | created by `install-env.sh`: the v2.5.1 checkout, its built tree `vllm-v2.5/`, venv `venv-v2.5/` and, by default, the compile cache `.vllm-cache-v2.5/` |

```bash
# v2.5.1-swift1.5. install-env.sh fetches the engine's release assets itself.
git clone --branch v2.5.1-swift1.5 https://github.com/halt95/Swift1.5-qwen38-flash-next-3090s.git
cd Swift1.5-qwen38-flash-next-3090s && sha256sum -c release/SHA256SUMS
release/install-env.sh
engine/venv-v2.5/bin/hf download halt95/Swift1.5-Qwen3.8-Flash-Next-W4A16-Merlin \
  --revision 3c9a1159eac1282463b06313de7dd9262edf8b58 --local-dir ./ckpt   # 115 GiB
(cd ckpt && sha256sum -c ../release/checkpoint.sha256)
HOST=0.0.0.0 serve/serve.sh "$PWD/ckpt"
```

Then [Check it's working](#check-its-working).

`HOST=0.0.0.0` exposes an endpoint without an API key on every interface: if the host is reachable from other machines,
set `VLLM_API_KEY` (or pass `--api-key` after the checkpoint; extra arguments go to `vllm serve`), or keep the default
`127.0.0.1` behind a proxy.

**Serve-script variables.** The checkpoint directory is the one required argument; the rest are optional: `ENGINE`
(`<repo>/engine`), `SCALES` (`<repo>/quant/kv_scales-swift-e4m3.json`; a relative path is resolved from the current
directory), `TREE` / `VENV` (`$ENGINE/vllm-v2.5`, `$ENGINE/venv-v2.5`); the wrapper fills in only these, and only when
they are unset. Every other knob of the v2.5.1 launcher passes through unchanged: `PORT` (8000), `HOST` (127.0.0.1),
`MODEL_NAME` (default `flash-next-v2 flash-next flash-mtp flash-next-mtp`), `CACHE_ROOT` (default
`$ENGINE/.vllm-cache-v2.5`; use a new one for v2.5, v2.2 artefacts do not carry over), `COUNTERS` (off; `1` adds the
two logging-only counters), `GUARD`, `PLE_HOME`, `CUDA_HOME`, `AUTO_TOPO` and the rest its header lists.

**The `xhigh` default.** `serve/serve.sh` passes
`--default-chat-template-kwargs '{"enable_thinking": true, "reasoning_effort": "xhigh"}'` after the checkpoint path.
The launcher passes every argument after the checkpoint path straight through to `vllm serve` after its own flags, so
this replaces the launcher's own default (`reasoning_effort: low`) rather than adding to it; arguments you give
`serve/serve.sh` after the checkpoint path come last and win in turn. A request that names an effort still gets that
effort.

**Requirements.** Linux x86-64 with glibc 2.34 or newer for the v2.5.1 build products (Ubuntu 22.04, Debian 12, RHEL 9 or
later); an NVIDIA driver with CUDA 13.0 or newer (the 580 series or later; tested on 595.84 / CUDA 13.2 and 610.43.02);
git, curl, gzip, tar, `sha256sum`; Python 3.13 with venv and headers, as `python3.13` on `PATH`. Debian 13 packages it
(`apt install python3.13-venv python3.13-dev`); Ubuntu 22.04 / 24.04 get it from the deadsnakes PPA (same package
names); on Debian 12 or RHEL 9 use a standalone build such as `uv python install 3.13` (it ships venv and headers;
check that `python3.13` is on `PATH`), pyenv, or the container. A C/C++ compiler and ninja (the first serve compiles
kernels), four visible 24 GB NVIDIA GPUs (qualified with peer-to-peer on the driver; it also runs without, see below),
headless and with no other CUDA process on them (the KV pool is pinned in bytes and leaves about 1 GB per card), host
RAM (96 GB qualified; ~69 GiB measured floor on v2.0.1/v2.2.0, not re-measured for v2.5.1), `/dev/shm` ≥ 1 GB. The
first boot compiles the graphs; later boots reuse `CACHE_ROOT`.

**Running next to an engine install.** This repository installs its own engine copy under `engine/`; it does not
upgrade or replace a `qwen38-flash-next-3090s` install. Both serve on port 8000 by default, so stop one before
starting the other. An `engine/` left by a v2.2.0-swift1.5 install is at another commit, so `install-env.sh` refuses
it: move it away or pass a new `ENGINE=`.

**Without peer-to-peer** the engine runs unchanged, with lower prefill; see the
[engine reference](https://github.com/halt95/qwen38-flash-next-3090s/blob/v2.5.1/docs/reference.md#build-and-serve)
(measured on v2.2.0 with the Merlin checkpoint).

Read [Known behaviours](#known-behaviours-of-the-qwen38-flash-next-architecture-in-vllm) before putting it in front of clients.

## Container

The container recipe is one image that installs the pinned v2.5.1 engine with `release/install-env.sh` and serves
through `serve/serve.sh`. **Unverified for v2.5.1:** the image has not been rebuilt or GPU-served on this release (its
recipe changed only in names and paths; for v2.2.0 the image was built and its entrypoint checks run on a host without
GPUs). Use the bare-metal route ([Build and serve](#build-and-serve)) for a verified install. Host requirements:

- four 24 GB Ampere cards (qualified with peer-to-peer working on the driver; it also runs without, with lower
  prefill), headless, with no other CUDA process on them: the KV pool is pinned in bytes and leaves about 1 GB per
  card, so a display server or another process on one card can stop the boot;
- `nvidia-container-toolkit` registered with Docker
  (`sudo nvidia-ctk runtime configure --runtime=docker && sudo systemctl restart docker`);
- Docker Compose v2 (`docker compose`, not the 1.x `docker-compose`);
- host RAM (96 GB is the qualified allocation; the measured resident floor is about 69 GiB on v2.0.1 and v2.2.0, not
  re-measured for v2.5.1, see [Hardware](#hardware));
- the checkpoint [halt95/Swift1.5-Qwen3.8-Flash-Next-W4A16-Merlin](https://huggingface.co/halt95/Swift1.5-Qwen3.8-Flash-Next-W4A16-Merlin)
  on disk (115 GiB).

```bash
git clone --branch v2.5.1-swift1.5 https://github.com/halt95/Swift1.5-qwen38-flash-next-3090s.git
cd Swift1.5-qwen38-flash-next-3090s
docker build -t swift1.5-qwen38-flash-next-3090s:v2.5.1-swift1.5 .   # runs release/install-env.sh inside the image
hf download halt95/Swift1.5-Qwen3.8-Flash-Next-W4A16-Merlin --revision 3c9a1159eac1282463b06313de7dd9262edf8b58 \
  --local-dir /path/to/Swift1.5-Qwen3.8-Flash-Next-W4A16-Merlin   # 115 GiB; outside the clone (see below)
MODEL_DIR=/path/to/Swift1.5-Qwen3.8-Flash-Next-W4A16-Merlin docker compose up -d
docker compose logs -f flash-next      # wait for "Application startup complete" (about 5–6 min the first time, about 2–3 min after)
curl -s localhost:8000/v1/chat/completions -H 'Content-Type: application/json'   -d '{"model":"flash-next","messages":[{"role":"user","content":"hello"}],"max_tokens":512}'
```

`hf` is the Hugging Face CLI: `pipx install huggingface_hub` or `uv tool install huggingface_hub` installs it
(a system-wide `pip install` is refused on current Debian and Ubuntu); after a bare-metal install,
`engine/venv-v2.5/bin/hf` also works. Download the checkpoint outside the clone; `.dockerignore` keeps the build context
to the install and serve files and the sidecar in any case. How to tell the server is healthy:
[Check it's working](#check-its-working).

The first start compiles the cudagraphs (about 5–6 minutes) into the `swift15-flash-next-cache-v2.5` volume, and the
first request compiles FlashInfer's kernels into the same volume (the image sets `FLASHINFER_WORKSPACE_BASE` and
`TRITON_CACHE_DIR` under `/cache`); later starts take about 2–3 minutes. Thinking is on by default at `xhigh`, so a
short `max_tokens` can end inside the reasoning with empty `content`; send
`"chat_template_kwargs":{"enable_thinking":false}` to turn it off per request. The endpoint has no API key and the
compose file publishes port 8000 on every interface: if the host is reachable from other machines, set `VLLM_API_KEY`
in its `environment` (clients then send `Authorization: Bearer <key>`), or publish `127.0.0.1:8000:8000` behind a
proxy. The host driver must support CUDA 13.0 or newer. Without compose:

```bash
docker run -d --name flash-next --gpus all --ipc=host --ulimit memlock=-1 --stop-timeout 70 -p 8000:8000 \
  -v /path/to/Swift1.5-Qwen3.8-Flash-Next-W4A16-Merlin:/model:ro -v swift15-flash-next-cache-v2.5:/cache \
  swift1.5-qwen38-flash-next-3090s:v2.5.1-swift1.5
```

Everything the container does is in `Dockerfile`, `docker-compose.yml` and `serve/docker-entrypoint.sh`; the install
and serve scripts run without Docker ([Build and serve](#build-and-serve)).

## Check it's working

The same check applies to both routes (container, bare metal):

```bash
# 1. the log shows "Application startup complete" (about 5–6 min the first time on a fresh compile cache, about 2–3 min after)
# 2. the log's KV line reads "GPU KV cache size: 924,993 tokens" with the default serve command (the pool is pinned in bytes, so any other
#    number means the serve command or the build is not the shipped one)
# 3. a real generation answers (add -H "Authorization: Bearer <key>" if you set VLLM_API_KEY):
curl -s localhost:8000/v1/chat/completions -H 'Content-Type: application/json' \
  -d '{"model":"flash-next","messages":[{"role":"user","content":"ok"}],"max_tokens":16,"chat_template_kwargs":{"enable_thinking":false}}'
```

The first request also compiles FlashInfer's kernels, so it takes noticeably longer than later ones (not measured).
Do not use `/v1/models` as a health check: it answers 200 even when the engine is dead. The container's
`HEALTHCHECK` runs a one-token generation for that reason.

The log also names the sidecar it applied (`applied static K/V scales from .../quant/kv_scales-swift-e4m3.json`) and
lists `'reasoning_effort': 'xhigh'` among the non-default arguments. The v2.5.1 cache fixes each log one line at
startup; all four should be there:
`Mamba align: each request holds its partial-tail CoW checkpoint until it is freed (...)`,
`Mamba align: a prompt tail key that lands on a block end is hashed too (...)`,
`Prefix cache: waiting requests' cached prefixes are pinned until admission (...)` and
`Prefix cache: a finished turn's cached prefix stays referenced until its next turn is admitted (...)`.

## Troubleshooting

- `serve/serve.sh` refuses to start because the launcher is missing or is not the published v2.5.1 launcher: run
  `release/install-env.sh`, or point `ENGINE=` at an install it made.
- `release/install-env.sh` refuses because `engine/` exists at another commit (for example a v2.2.0-swift1.5 install):
  move it away or pass a new `ENGINE=`.
- `KV-scale sidecar missing`: `SCALES` names a file that does not exist from the current directory; give an absolute
  path or leave it unset.
- `config.json lacks text_config.ple_embedding_dtype`: this checkpoint carries that key, so the directory is not the
  full checkpoint; re-run the checksum step of the [Quick start](../README.md#quick-start).
- Empty `content` with `finish_reason: "length"`: thinking is on and `max_tokens` ended inside the reasoning, which at
  `xhigh` can be long; raise `max_tokens`, or send a lower `reasoning_effort` or `"enable_thinking": false` in
  `chat_template_kwargs`.
- `Bus error`, CUDA out-of-memory, the kernel's OOM killer, `AttributeError: '_ModelInfo' ...`, `Unsupported .version`,
  `e2-guard`, an empty completion with zero tokens: the engine is the v2.5.1 engine, unchanged; see its
  [Troubleshooting](https://github.com/halt95/qwen38-flash-next-3090s/blob/v2.5.1/docs/reference.md#troubleshooting).

## Multi-GPU hosts and topology (opt-in)

`AUTO_TOPO=1` (NVLink pairs, hosts with more than four GPUs) passes through `serve/serve.sh` to the engine's launcher
unchanged; see the engine's
[Multi-GPU hosts and topology](https://github.com/halt95/qwen38-flash-next-3090s/blob/v2.5.1/docs/reference.md#multi-gpu-hosts-and-topology-opt-in).

## Running notes

The lines every boot logs that are not failures, and the allocator warnings you may see, are the engine's:
[Running notes](https://github.com/halt95/qwen38-flash-next-3090s/blob/v2.5.1/docs/reference.md#running-notes).

## How it works

![Flash-Next v2.5.1 layout on four RTX 3090s: pipeline stage 0 on GPUs 0 and 1 (25 of 48 layers, vision tower, target embedding, PLE home GPU 0) hands off over PCIe P2P to stage 1 on GPUs 2 and 3 (23 of 48 layers, MTP drafter, drafter embedding, LM head); each pair all-reduces over PCIe P2P; the FP8 n-gram table (~48 GiB) and the pinned embedding tables (~4.2 GiB) sit in host RAM and are pulled over PCIe; the whole-box FP8 KV pool is 924,993 tokens](https://raw.githubusercontent.com/halt95/qwen38-flash-next-3090s/v2.5.1/docs/images/flashnext-v2.5-layout.png)

### Hardware

| resource | reference host |
|---|---|
| GPU | 4× NVIDIA GeForce RTX 3090 (Ampere sm_86, 24 GB each), **220 W** power cap, no NVLink |
| PCIe | Gen4 x16 to every card; P2P over the aikitoria open-kernel-module patch |
| RAM | the serving container is allocated **96 GB**, the qualified figure; measured resident floor about **69 GiB** (v2.0.1), treat it as a hard floor |
| disk, `/dev/shm` | ≥ 250 GB free (the checkpoint is 115 GiB); `/dev/shm` ≥ 1 GB |

### The KV budget

**924,993 tokens** at `--kv-cache-memory 4100000000` per rank, measured on this checkpoint's v2.5.1 gate boot, the
same as the Merlin checkpoint's. The attention block size is 4,096 tokens. The per-request limit stays 262,144; the pool is the
aggregate over concurrent requests. Where the room comes from (pipeline parallelism, the host-mapped n-gram table,
host-resident embeddings, the side-cache layout) is in the engine's
[The KV budget](https://github.com/halt95/qwen38-flash-next-3090s/blob/v2.5.1/docs/reference.md#the-kv-budget).
Session residency (three 262K or six 131K at once) was measured on the Merlin checkpoint, not re-run on this one.
Under full-pool pressure on this checkpoint, 8 deep conversations drove the pool to 98.0 % with 0 preemptions, and all
90 requests completed.

### Stack

| piece | v2.5.1-swift1.5 |
|---|---|
| engine | Flash-Next v2.5.1, unchanged: public tag **`v0.30.0`** + 97 commits, release commit **`96a0d13b6e`**, installed from [halt95/qwen38-flash-next-3090s](https://github.com/halt95/qwen38-flash-next-3090s) tag `v2.5.1` (`352e006`) by `release/install-env.sh` |
| compiled ops | the v2.2.0 compiled-ops tarball, reused unchanged by v2.5.1, hash-pinned in the engine's `upstream/PIN-v2.5` |
| environment | Python 3.13, torch 2.13.0 (CUDA 13.0), triton 3.7.1, flashinfer 0.6.18.post1, transformers 5.18.0 (the engine's 196 pins) |
| shape | the engine's `serve-v2.5.sh`: TP2 × PP2 + EP, MTP K=3, KV pin 4.1e9, fp8_e4m3 KV with this checkpoint's sidecar, prefix caching, `--use-replayssm`, `--block-size 4096`, `--prefix-match-unit 64`, image limit 42 with 4 MP per image; plus `reasoning_effort: xhigh` as the server default |
| instrumentation | bounds guards on in `warn`; exact-restart and FP8 KV clip counters off by default (`COUNTERS=1`) |

### Checkpoint

[halt95/Swift1.5-Qwen3.8-Flash-Next-W4A16-Merlin](https://huggingface.co/halt95/Swift1.5-Qwen3.8-Flash-Next-W4A16-Merlin)
is the Merlin checkpoint with the 300 tensors Swift 1.5 changed swapped in. We compared Swift 1.5 (revision
`0bd4fe22431372cdad1979267d3ab45aa7e6150a`) with Qwen/Qwen3.8-Flash-Next (revision
`de4b8e4d43b917e7706784d8bb445c9af86a3540`) tensor by tensor: changes were found in the attention `q/k/v/o_proj`
(12 layers), the GDN `in_proj_qkv` / `in_proj_z` / `out_proj` (36 layers) and the shared experts (48 layers), 5.42 GiB in
BF16. The routed experts, routers, MTP head, PLE table, embeddings, `lm_head` and vision tower were reported unchanged
(the MTP head with a full SHA-256 of every tensor; the other groups with whole-shard or sampled hashes, three 512 KiB
chunks per large tensor; a sampled match is strong evidence but not proof). Attention and shared experts stay in BF16;
the GDN projections are re-packed to INT8 per-channel symmetric in the Merlin checkpoint's format. The routed experts
(Intel AutoRound INT4 g128), MTP head and FP8 PLE table are the Merlin checkpoint's, unmodified, and the checkpoint
carries the `ple_embedding_dtype` config key the engine needs.

The KV scale sidecar was recalibrated on this checkpoint (`quant/kv_scales-swift-e4m3.json`, sha256 `d211be1f…`, the
same bytes as `qsa_kv_scales_swift.json` in the checkpoint). Swift 1.5 changed `k_proj` / `v_proj`, so the Merlin
sidecar does not carry over: serving the Merlin checkpoint through `serve/serve.sh` needs
`SCALES=$PWD/engine/scales/qsa_kv_scales_262k.json`.

The checkpoint's own `tokenizer.json` on Hugging Face, the file Swift 1.5 and the Intel AutoRound release ship, is
replaced with the upstream Qwen3.8-Flash-Next file (vocabulary, merges and special tokens identical), so tools that
read it directly (the `tokenizers` library, GGUF converters) match upstream too; vLLM serving on 5.18.0 tokenizes
identically with either file.

### Serving an agent

| agent need | as served |
|---|---|
| several long sessions at once | 8 sequences admitted; 8 deep conversations served from a nearly full pool (98.0 %) with 0 preemptions on this checkpoint |
| the same context re-sent every turn | prefix caching on; a follow-up turn resumes from its conversation's cached prefix on a 64-token grid, and v2.5.1 holds that prefix until the next turn is admitted |
| tool calls, thinking, images | Qwen3 coder tool parser, Qwen3 reasoning parser with thinking on at `xhigh` effort, up to 42 images per request capped at 4 MP each, one OpenAI-compatible front door |
| a client that expects an answer every time | retry once on `finish_reason == "stop"` with 0 completion tokens ([empty warm completion](#known-behaviours-of-the-qwen38-flash-next-architecture-in-vllm)) |

## Benchmarks

The v2.5.1-swift1.5 card: [`benchmarks/2026-10-06/BENCH-CARD.md`](../benchmarks/2026-10-06/BENCH-CARD.md): this
checkpoint's release gate on the v2.5.1 engine (pool, needles, structured output, GSM8K, cold prefill, follow-up
turns, cache validity), against the Merlin checkpoint's v2.5.1 numbers. The decode ladder, depth chart and session
residency were not re-run on this checkpoint; they are in the
[engine's v2.5.1 card](https://github.com/halt95/qwen38-flash-next-3090s/blob/v2.5.1/benchmarks/2026-10-06/BENCH-CARD.md).

The v2.2.0-swift1.5 card: [`benchmarks/2026-09-27/BENCH-CARD.md`](../benchmarks/2026-09-27/BENCH-CARD.md): this
checkpoint against the Merlin checkpoint on the v2.2.0 engine, measured interleaved (step time, aggregate decode, MTP
acceptance, GSM8K thinking off and at `xhigh`, completion tokens by reasoning effort, retrieval to 256K), and the
`xhigh` loop check ([loop-check.md](loop-check.md)).

> **Evidence boundary.** Both cards are maintainer measurements on the reference host; the drivers, raw streams and
> boot logs are not published. What you can reproduce independently: the engine source (commit **and** tree hash), the
> environment, the checkpoint files (`release/checkpoint.sha256`), the sidecar and the serve command. Everything else
> is maintainer-reported.

## Known behaviours of the Qwen3.8-Flash-Next architecture in vLLM

The engine's known behaviours apply unchanged; none is introduced by this checkpoint. The full list, with causes and
mitigations, is in the
[engine reference](https://github.com/halt95/qwen38-flash-next-3090s/blob/v2.5.1/docs/reference.md#known-behaviours-of-the-qwen38-flash-next-architecture-in-vllm).
The ones a client meets:

- **Custom pool sizes: keep the KV pool larger than `--max-model-len` plus a few blocks** (not reached with the
  shipped settings: a 924,993-token pool, requests up to 262,144 tokens).
- **Empty warm completion**: an occasional empty completion (`finish_reason: "stop"`, zero tokens) on a warm repeat
  of a long cached prefix (upstream class: vllm-project/vllm #53912). Mitigation: **retry once**.
- **Full re-prefills under a full pool**: with 8 long conversations and the pool near full, a few follow-ups find no
  cached prefix and re-read the whole conversation (3 of 82 in 5 minutes on this checkpoint); the protection yields
  rather than preempting a running request.
- **Greedy T=0 repeats within one compile cache**, not across fresh compiles.

Specific to this checkpoint:

- **Reasoning effort.** The launcher's server default is `low`; `serve/serve.sh` sets `xhigh`, which we recommend for
  Swift 1.5 ([UkisAI's model card](https://huggingface.co/ukisai/Swift1.5-Qwen3.8-Flash-Next) reports its evaluations
  at `xhigh`). On GSM8K-200 on v2.2.0, `xhigh` cost this checkpoint 304 completion tokens per answer against 259 at
  `low`, at the same accuracy; the Merlin checkpoint's `xhigh` cost 416.
- **Quality evidence**, beyond the release checks, is GSM8K-200 and the `xhigh` loop check; we ran no broader
  evaluation. UkisAI's published evaluations are of the BF16 model, not of this quantised build.
- **MTP decode speed.** With MTP, single-request tokens/s depends on how much of the drafted text is accepted; judge
  speed by step time, not by one request's tokens/s.

## What ships next

This repository follows the engine's releases; the engine's next release focuses on single-stream decode and capacity.

## Credit

- Model: [Qwen/Qwen3.8-Flash-Next](https://huggingface.co/Qwen/Qwen3.8-Flash-Next)
- Swift 1.5 post-train: [ukisai/Swift1.5-Qwen3.8-Flash-Next](https://huggingface.co/ukisai/Swift1.5-Qwen3.8-Flash-Next)
- Quantised experts: [Intel/Qwen3.8-Flash-Next-W4A16-AutoRound](https://huggingface.co/Intel/Qwen3.8-Flash-Next-W4A16-AutoRound);
  FP8 PLE table: [RadixArk/Qwen3.8-Flash-Next-NVFP4](https://huggingface.co/RadixArk/Qwen3.8-Flash-Next-NVFP4);
  MTP INT4 packing recipe adapted from [DominikBucko/qwen38-flash-next-2x3090](https://github.com/DominikBucko/qwen38-flash-next-2x3090);
  Merlin checkpoint and recipe: [halt95/Qwen3.8-Flash-Next-W4A16-Merlin](https://huggingface.co/halt95/Qwen3.8-Flash-Next-W4A16-Merlin)
- Serving engine: [vLLM](https://github.com/vllm-project/vllm) (Apache-2.0) through the Flash-Next v2.5.1 release
  ([halt95/qwen38-flash-next-3090s](https://github.com/halt95/qwen38-flash-next-3090s)); upstream fixes are credited
  by PR number in its commit messages and by author in its `NOTICE` and
  [credit list](https://github.com/halt95/qwen38-flash-next-3090s/blob/v2.5.1/docs/reference.md#credit); P2P on
  consumer Ampere: aikitoria's open-kernel-module patch

Third-party notices for this repository are in [NOTICE](../NOTICE).

## Licence detail

- **Code** in this repository — the scripts (`serve/`, `release/`) and the documentation — is under Apache-2.0
  (`LICENSE`). The engine is not part of this repository: `release/install-env.sh` installs it from
  [halt95/qwen38-flash-next-3090s](https://github.com/halt95/qwen38-flash-next-3090s), a vLLM fork under Apache-2.0
  whose own `NOTICE` lists the modified files.
- **The Swift 1.5 KV-scale sidecar** (`quant/kv_scales-swift-e4m3.json`) is model-derived data, not under Apache-2.0.
  It is subject to the Swift Open License v1.0 (`LICENSE-SWIFT`) and the Qwen Community License 1.0 (`LICENSE-QWEN`).
- **The checkpoint you serve**
  ([halt95/Swift1.5-Qwen3.8-Flash-Next-W4A16-Merlin](https://huggingface.co/halt95/Swift1.5-Qwen3.8-Flash-Next-W4A16-Merlin))
  is subject to the same two licences; it is not part of this repository.
  - Commercial Use by a Legal Entity whose gross revenue meets or exceeds US$1,000,000 is not licensed under the
    Swift Open License. Revenue is measured over the most recently completed fiscal year across that entity and all
    entities controlling, controlled by, or under common control with it. A Qualified Non-Profit Organization's
    Non-Commercial or Research Purposes are exempt from the threshold. An entity above the threshold may obtain a
    separate written Swift Enterprise License from UkisAI. See Swift Open License §§1 and 5.
  - If the Software or a derivative is used for a licensee's commercial product or service with more than
    100,000,000 monthly active users or more than US$20,000,000 monthly revenue, the respective model name must be
    prominently displayed in that product's or service's user interface. If the licensee or an affiliate conducts a
    Model as a Service or AI Work Assistant business, it must obtain a separate Qwen licence before any commercial
    use, except for qualifying internal use that makes neither the software, its outputs, nor its model capabilities
    available to a third party. See Qwen Community License §§1–2.
- "UkisAI" and "Swift" are UkisAI's names. They are used here only to describe where the weights come from.
- This section summarises the licences. It is not legal advice, and the licence texts govern.

This is an independent derivative made by halt95. It is not made, reviewed or endorsed by UkisAI or by Qwen.
