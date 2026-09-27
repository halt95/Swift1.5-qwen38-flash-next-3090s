# v2.2.0-swift1.5 card — 2026-09-27 (parity check against the Merlin checkpoint, quality, install check)

> **Provenance.** Measurements on the reference host (4× RTX 3090, 220 W power cap, PCIe Gen4 x16 with
> peer-to-peer, no NVLink; driver 610.43.02). Both checkpoints were served by the published Flash-Next
> v2.2.0 install (tree `9c27ca9a`, no local changes) through its published launcher (`scripts/serve-v2.2.sh`),
> on python 3.13.5, torch 2.13.0 (CUDA 13.0), triton 3.7.1, flashinfer 0.6.18.post1. Every boot's identity was
> asserted before traffic: launcher and tree hashes, vLLM 0.30.0, the checkpoint's own KV-scale sidecar, an
> 806,792-token FP8 KV pool, `kv_cache_dtype=fp8_e4m3`, MTP with 3 speculative tokens. Sections 1, 2 and the
> thinking-off half of section 3 ran with the launcher's logging-only counters on, matching how the published
> v2.2.0 numbers were measured (the FP8 KV clip check in section 4 needs them); the `xhigh` rows in section 3
> ran knob-absent, at the served default, confirmed by reading the served process's own environment. Two runs
> per checkpoint, measured in one session in interleaved order (Merlin, Swift, Merlin, Swift; a fresh boot for
> each run). Streams are client-timed. Raw streams and the boot logs are not published (as for the earlier
> cards). Every number below was recomputed from the raw per-request rows for this card.

## 1. Single-stream decode ladder, Swift 1.5 vs Merlin (thinking off)

Four depths, 3 sends per run at up to 256 tokens, 2 runs per checkpoint in the same session (Merlin run 1,
Swift run 1, Merlin run 2, Swift run 2). Thinking is off (`think: false`) on every row of this ladder, confirmed
in the raw rows. With MTP, read median ITL (the decode step time) together with tokens per event; single-stream
decode tokens/s is descriptive only, since with MTP it tracks how much of the drafted text a run's own generated
content accepts, not the engine's speed — step time is the fair comparison.

![Decode step time and tokens per event over context depth, Merlin checkpoint and Swift 1.5 build](swift1.5-v2.2.0-ctx-itl-tpe.png)

- The chart shows this section's step time and tokens per event.
- In the chart every axis starts at zero; each faint dot is one run, and the line is both runs pooled, with its
  value printed.

| prompt tokens, target / actual | Merlin ITL ms, pooled [run 1 / run 2] | Swift ITL ms, pooled [run 1 / run 2] | ITL ratio Swift/Merlin | tokens/event, pooled (Merlin / Swift) | decode t/s, pooled (Merlin / Swift) |
|---|---|---|---|---|---|
| 4,096 / 3,956 | 19.16 [19.08 / 19.27] | 19.09 [19.16 / 19.02] | 0.996 | 2.95 / 2.90 | 154.8 / 152.6 |
| 32,768 / 32,621 | 19.20 [19.21 / 19.20] | 19.29 [19.30 / 19.28] | 1.005 | 3.05 / 3.12 | 159.7 / 164.5 |
| 131,072 / 130,922 | 19.64 [19.52 / 19.76] | 19.58 [19.73 / 19.45] | 0.997 | 3.06 / 3.14 | 161.6 / 167.8 |
| 263,800 / 260,555 | 19.66 [19.55 / 19.81] | 19.71 [19.97 / 19.61] | 1.003 | 3.36 / 3.36 | 177.1 / 175.3 |

Across the four depths, step time differs from −0.36 % to +0.48 % (Swift vs Merlin, largest magnitude 0.48 %);
tokens per event differ from −1.7 % to +2.7 % — the largest of any pooled delta in this ladder — but that figure
depends on the generated text, which differs between the two checkpoints by construction. Decode t/s pooled here
is the token-weighted rate over each pooled pair of runs; it is shown for interest, not as a gate.

## 2. Aggregate throughput ladder (1,024-token prompt, 512-token output)

3 repeats per run at each concurrency, same 2 runs per checkpoint as above, thinking off at temperature 0 with fixed
512-token outputs. Shown relative to the Merlin checkpoint measured in the same session:

| | Swift ÷ Merlin (mean of 2 runs each) | run-to-run spread, Merlin | run-to-run spread, Swift |
|---|---:|---:|---:|
| N=1 | 1.009 (+0.88 %) | 6.18 % | 2.83 % |
| N=8 | 1.011 (+1.09 %) | 1.47 % | 0.15 % |

Run-to-run spread is the difference between a checkpoint's two runs, as a share of the lower one. The Swift-Merlin
difference is within the Merlin checkpoint's own spread at both concurrencies.

## 3. Quality: GSM8K-200 and the loop check

**GSM8K-200, thinking off, 4 runs (same runs as sections 1–2), 5-shot, exact-match on the final number:**

| run | correct / 200 | answers truncated at the 256-token cap |
|---|---:|---:|
| Merlin run 1 | 199 | 2 |
| Swift run 1 | 198 | 1 |
| Merlin run 2 | 199 | 2 |
| Swift run 2 | 199 | 2 |

Pooled: Merlin 398/400, Swift 397/400. Pairing each Merlin run with the Swift run that followed it in the same
session (run 1 with run 1, run 2 with run 2) and comparing the two runs item by item on the same 200 questions:
**1 discordant item of 400 paired comparisons** — in the run 1 pair, Merlin answered correctly where Swift did
not; in the run 2 pair, Merlin and Swift missed the identical item (0 discordant there). No item was ever wrong
for Swift alone.

**GSM8K-200, thinking on at `xhigh` (Swift only, knob-absent, served sampling, up to 16,384 tokens):** 198/200
correct, 0 errors, 0 truncated, mean completion length 285.8 tokens. Merlin was not run through this gate at
`xhigh`. It was measured later the same day in a separate session (see section 5, install-and-serve check):
**197/200** correct, 0 errors, 0 truncated, mean completion length 465.5 tokens. That is a single run from a
different session, not a paired comparison.

**Loop check at `xhigh`, knob-absent, thinking on, 72 generations per arm (12 prompts × 6 seeds, up to 16,384
tokens, 8,192 for the shorter prompts):**

| arm | genuine collapses | flagged (non-genuine) | errors |
|---|---:|---:|---:|
| Swift, xhigh | 0 | 0 | 0 |
| Merlin, xhigh (reference arm) | 0 | 1 | 0 |

Definitions: **flagged** = an 8-word repeat ratio above 0.15, OR a 12-word window repeating 4 or more times, OR
a tail (last 30 % of words) distinct-word-pair ratio below 0.45. **Genuine collapse** = tail distinct-word-pair
ratio below 0.15, OR a 12-word window repeating 20 or more times. The one flagged Merlin generation ("Design an
algorithm to detect repeating cycles in …", 8-word repeat ratio 0.0112, worst window repeat 4, tail ratio
0.8699) sits far from the genuine threshold on every measure and was hand-read as not a genuine collapse.

## 4. MTP acceptance and the FP8 KV clip check

**MTP acceptance**, computed as 1 + 3 × (accepted draft tokens / drafted draft tokens), token-weighted over every
decode-metrics line from the start of a run's traffic to 10 s after its last request (the same runs as sections
1–2):

| | Merlin run 1 | Merlin run 2 | Merlin, pooled | Swift run 1 | Swift run 2 | Swift, pooled |
|---|---:|---:|---:|---:|---:|---:|
| accepted / drafted tokens | 28,549 / 45,102 | 28,483 / 44,889 | 57,032 / 89,991 | 28,960 / 45,030 | 28,798 / 45,279 | 57,758 / 90,309 |
| mean acceptance length | 2.899 | 2.904 | 2.901 | 2.929 | 2.908 | 2.919 |

Pooled: Merlin 2.90, Swift 2.92 (both checkpoints, at most 4 tokens per step with MTP K=3).

**FP8 KV clip check**, counted over the same runs' request window (limits scale with the number of
≥131,072-token rows in that window; 3 here, so k ≤ 44×3 = 132 and v ≤ 81×3 = 243):

| run | k increments | v increments | limit | verdict |
|---|---:|---:|---|---|
| Merlin run 1 | 0 | 0 | k≤132, v≤243 | PASS |
| Swift run 1 | 0 | 1 | k≤132, v≤243 | PASS |
| Merlin run 2 | 0 | 17 | k≤132, v≤243 | PASS |
| Swift run 2 | 1 | 2 | k≤132, v≤243 | PASS |

All four runs passed with room to spare; the largest single-run count (17, Merlin run 2) is 7 % of its limit.

## 5. Checkpoint and launcher checks

**KV pool.** Every boot behind sections 1–4 — all 4 gated runs above, plus the knob-absent `xhigh` runs behind
section 3's `xhigh` rows — logged an 806,792-token FP8 KV pool, unchanged from the Merlin checkpoint.

**Install-and-serve check.** A fresh clone of this repository ran `release/install-env.sh` (the pinned
v2.2.0 engine and its build, verified against the pins) and then served both checkpoints through
`serve/serve.sh`, one after the other:

- **Swift 1.5 build, `SCALES` unset** (the README's install and serve commands, on the staged Hugging Face
  upload set; the download step itself was not part of the check): the engine logged "applied static K/V scales from …/quant/kv_scales-swift-e4m3.json", the
  806,792-token pool and `xhigh` as the server default. GSM8K-200 thinking on at `xhigh`: **197/200**
  (bar ≥196), 0 errors, 0 truncated, no engine errors.
- **Merlin checkpoint, `SCALES` set to the Merlin sidecar**: the Merlin sidecar applied, the same pool,
  `xhigh` default. GSM8K-200 thinking on at `xhigh`: **197/200**, 0 errors, 0 truncated (section 3).

**Rebuild check.** A second build of the checkpoint, from the changed tensors fetched again from UkisAI's published
Swift 1.5 checkpoint and the Merlin checkpoint, using our own build tools (not published), reproduced **27 of 27
safetensors shards byte-identical** to the gated checkpoint, plus 6 smaller files and the shard index equal; the
shard index is also byte-identical to the published Hugging Face index. The comparison allowed only the disclosed
differences (the README, a provenance file, and files present on one side only: the licence and NOTICE files and
the sidecar).
A control run with one byte deliberately flipped in a shard was correctly caught and the exact tensor named by
the same check, confirming the check discriminates a real mismatch rather than always passing.

## 6. What this card does not show

- **No container.** This release ships no container image; every number above comes from the bare-metal launcher.
- **One hardware profile.** Four RTX 3090s on PCIe Gen4 x16 with peer-to-peer, 220 W, and this launcher's fixed
  layout (TP2 × PP2 + EP, MTP K=3, 806,792-token pool). Other GPUs, layouts, power caps and host configurations
  are untested.
- **Two runs per checkpoint, one session.** No confidence interval is claimed anywhere above beyond the paired
  GSM8K-200 discordant count in section 3.
- **Run-to-run spread versus the Swift-Merlin difference.** Between the two runs of the *same* checkpoint,
  step time varied by up to 1.86 % and aggregate N=8 decode by up to 1.47 % — both larger than every
  Swift-vs-Merlin difference in those same two metrics (step time −0.36 % to +0.48 %; aggregate N=8 +1.09 %).
  Tokens per event varied more between runs of the same checkpoint too, but that metric tracks the generated
  text by construction, so it is not compared against a noise floor the same way.
