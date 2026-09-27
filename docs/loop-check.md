# Repetition-loop check at `xhigh` (2026-09-27)

**Question:** at `xhigh` reasoning effort, does the Swift 1.5 build collapse into repetition more often than the
Merlin checkpoint on the same engine?

**Arms** (four RTX 3090, the Flash-Next v2.2.0 `scripts/serve-v2.2.sh` from the published v2.2.0 install, no knobs
set, `xhigh` as the server default; only the checkpoint and its KV-scale sidecar differ):
- **Swift 1.5 build:** this release's checkpoint with its own sidecar (`quant/kv_scales-swift-e4m3.json`);
- **Merlin checkpoint:** `halt95/Qwen3.8-Flash-Next-W4A16-Merlin` with the v2.2.0 release sidecar, as the reference arm.

**Protocol:**
- 12 long-form prompts × 6 seeds per arm: 72 generations per arm, one fresh boot per arm.
- Thinking on at `xhigh`, with the served sampling settings (temperature 1.0, top-p 0.95, top-k 20, as the launcher pins them), one seed per generation.
- Output caps of 16,384 tokens, and 8,192 for the shorter prompts.
- 6 concurrent requests.
- A generation counts as **collapsed** when the distinct-word-pair ratio of its last 30 % of words is below 0.15, or
  one 12-word window occurs 20 or more times.
- Pass rule, fixed before the run: Swift 1.5 collapses minus Merlin checkpoint collapses ≤ 1, a one-sided Fisher exact test of
  Swift 1.5 worse than the Merlin checkpoint at p ≥ 0.05, and no engine errors.

| arm | generations | collapsed | engine errors |
|---|---:|---:|---:|
| Swift 1.5 build | 72 | **0** | 0 |
| Merlin checkpoint | 72 | **0** | 0 |

For 0 of 72 against 0 of 72 the one-sided Fisher exact p-value is 1, so the rule holds. One Merlin checkpoint generation (the prompt
asking for an algorithm that detects repeating cycles) was flagged by the detector's looser screen; its tail
distinct-word-pair ratio was 0.87, far above the 0.15 threshold, and it is not a collapse. No Swift 1.5 generation was
flagged.

**Limit:** no collapses were observed in 72 generations per arm. That passes the rule above; it does not show equal
collapse rates, and a sample this size can't rule out a rare loop.
