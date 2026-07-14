---
sessionId: session-260714-113006-1ljl
---

# Requirements

### Overview & Goals
Replace the chart's fixed model backend from **Qwen3-Coder-Next 80B (AWQ INT4, CPU-offloaded)** with **Qwen3.6-27B (AWQ 4-bit)** served by vLLM, tuned so the model fits **entirely in the 2x RTX 2000 Ada GPUs (32GB combined VRAM) with no CPU offload**, at 128K context, with **MTP (Multi-Token Prediction)** speculative decoding enabled for faster decode.

The key win: the 27B checkpoint (~21GiB) fits across both GPUs via tensor parallelism, eliminating the dense PCIe-bound CPU offload and the upstream Marlin MoE-repack OOM bug that blocked the 80B on this device.

### Scope
**In scope**
- Point the chart at `QuantTrio/Qwen3.6-27B-AWQ` (AWQ 4-bit, ~21GiB).
- Remove CPU offload (`--cpu-offload-gb`) entirely.
- Keep 128K context (`--max-model-len 131072`).
- Enable MTP via `--speculative-config` (`qwen3_next_mtp`).
- Add reasoning parser (`qwen3`) and keep the `qwen3_coder` tool-call parser.
- Add FlashInfer/allocator env tweaks and `--trust-remote-code`.
- Keep TP=2 + the existing NCCL no-P2P/no-IB workarounds (still required for two-GPU init on this NVLink-less board).
- Update all docs of record: `CLAUDE.md`, `HARDWARE.md` (decision trail), `.aiassistant/rules/*`, `README.md`, `NOTES.txt`, `Chart.yaml` description, and version bumps in `Chart.yaml` + `gitops/rtx2000-ada-128gb-se.yaml`.

**Out of scope**
- Open WebUI deployment/service (unchanged).
- Persistence layout, service type, GPU-resource conventions (unchanged).
- Multimodal/vision input wiring (text/coding use only).

### User Stories
- As the device operator, I want the model to load fully into both GPUs with no CPU offload, so startup is reliable and free of the Marlin-repack OOM bug.
- As an API user, I want 128K context and MTP-accelerated decoding, so long agentic/coding sessions are fast.
- As a maintainer, I want the docs/decision-trail updated so the 27B choice and its no-offload rationale are canonical.

### Functional Requirements
- vLLM serves an OpenAI-compatible API on port 8080 (ClusterIP), served name updated (e.g. `qwen3.6-27b`).
- Model loads with `--tensor-parallel-size 2` and **no** `--cpu-offload-gb`.
- `--max-model-len 131072` (128K).
- MTP enabled via `--speculative-config '{"method":"qwen3_next_mtp","num_speculative_tokens":1}'`.
- Tool calling (`--enable-auto-tool-choice --tool-call-parser qwen3_coder`) and `--reasoning-parser qwen3` active.
- `/health` becomes ready; startupProbe still absorbs the (smaller, ~21GB) first-run download.

### Non-Functional Requirements
- Zero-config: all values hardcoded/tuned for `rtx2000-ada-128gb-se`; `valuesContent` stays empty.
- Fits within 16380 MiB/GPU at `--gpu-memory-utilization 0.90` with headroom for MTP draft head + 128K KV.
- `helm lint` + `helm template` smoke test (`./scripts/lint.sh`) pass.

# Technical Design

### Current Implementation
- `charts/local-llm/values.yaml` — `model.huggingfaceRepo: bullpoint/Qwen3-Coder-Next-AWQ-4bit`, `vllm.cpuOffloadGb: 32`, `maxModelLen: 131072`, `tensorParallelSize: 2`, `gpuMemoryUtilization: 0.90`, sampling defaults, `toolCallParser: qwen3_coder`.
- `charts/local-llm/templates/deployment.yaml` — vLLM `args` include `--cpu-offload-gb`, `--tensor-parallel-size`, `--disable-custom-all-reduce`, tool parser, generation-config override; `env` sets `HF_HOME`, `NCCL_P2P_DISABLE`, `NCCL_IB_DISABLE`, `NCCL_DEBUG`, `PYTORCH_ALLOC_CONF`.
- Docs of record: `CLAUDE.md`, `HARDWARE.md` ("Model decision trail"), `.aiassistant/rules/hardware.md` + `helm-chart.md`, `README.md`, `templates/NOTES.txt`.
- Version pins: `Chart.yaml` (`0.3.5`) and `gitops/rtx2000-ada-128gb-se.yaml` (`spec.version: 0.3.5`).

### VRAM Budget (answering: fits without CPU offload?)
- Weights: ~21GiB AWQ 4-bit / TP=2 ≈ **~10.5GB/GPU**.
- Usable/GPU at 0.90 util of 15.57GB ≈ **~14GB**.
- Remaining ~3.5GB/GPU covers CUDA graphs + activations + MTP draft head + KV.
- KV: Qwen3.6-27B uses gated-delta hybrid attention (constant-size state on most layers, like the 80B) → 128K ≈ **~1.5GB/GPU**.
- Conclusion: **fits with no `--cpu-offload-gb`.** This also removes the class of Marlin MoE-repack OOM bug documented for the 80B.

### Key Decisions
- **Model:** `QuantTrio/Qwen3.6-27B-AWQ` (confirmed) — replaces the 80B as the single fixed model.
- **No CPU offload:** drop `--cpu-offload-gb` and the `vllm.cpuOffloadGb` value; rely purely on TP=2 fitting in VRAM.
- **MTP:** enable via `--speculative-config '{"method":"qwen3_next_mtp","num_speculative_tokens":1}'` — lossless speedup; num_speculative_tokens kept at 1 initially (conservative on VRAM), documented as tunable.
- **Parsers:** add `--reasoning-parser qwen3`; keep `--enable-auto-tool-choice --tool-call-parser qwen3_coder`.
- **Env tweaks:** add `--trust-remote-code`, keep `PYTORCH_ALLOC_CONF=expandable_segments:True`, add FlashInfer sampler/allocator env (`VLLM_USE_FLASHINFER_SAMPLER=0`, `VLLM_SLEEP_WHEN_IDLE=1`) per the checkpoint's documented launch; MoE-specific FlashInfer flags are omitted since 27B is dense (noted as verify-on-device).
- **Keep NCCL workarounds + `--disable-custom-all-reduce`:** still needed for TP=2 on this no-NVLink/no-P2P board.
- **Model is still "fixed":** the zero-config contract is preserved, just re-pointed.

### Proposed Changes
**`charts/local-llm/values.yaml`**
- `model.huggingfaceRepo` → `QuantTrio/Qwen3.6-27B-AWQ`; `model.servedName` → `qwen3.6-27b`.
- Keep `maxModelLen: 131072`; keep sampling defaults (verify against Qwen3.6 recommendations).
- Remove `vllm.cpuOffloadGb`; keep `tensorParallelSize: 2`, `gpuMemoryUtilization: 0.90`.
- Add `model.reasoningParser: qwen3` and `vllm.speculative` block (method + num_speculative_tokens) for MTP.
- Update all comments to reflect no-offload + 27B + MTP rationale (replace the long CPU-offload/Marlin-bug commentary).

**`charts/local-llm/templates/deployment.yaml`**
- Remove `--cpu-offload-gb` arg.
- Add `--reasoning-parser {{ .Values.model.reasoningParser }}`, `--speculative-config <json>` (from `vllm.speculative`), `--trust-remote-code`.
- Update the vLLM args header comment.
- Add FlashInfer/idle env vars; keep NCCL + `PYTORCH_ALLOC_CONF` env (retune the repack-specific wording).
- Keep probes; startupProbe comment updated to ~21GB download.

**Docs / version pins**
- `Chart.yaml`: update `description` to Qwen3.6-27B; bump `version` (e.g. `0.4.0`).
- `gitops/rtx2000-ada-128gb-se.yaml`: bump `spec.version` to match, same change.
- `templates/NOTES.txt`: ~21GB download wording; served name.
- `CLAUDE.md`, `.aiassistant/rules/helm-chart.md`: update the "Model/runtime is fixed" constraint to Qwen3.6-27B.
- `HARDWARE.md`: add a new decision-trail entry ("Switch to Qwen3.6-27B on vLLM") explaining the no-offload fit, MTP, and that it sidesteps the 80B Marlin-repack bug.
- `README.md`: minimal alignment edits only.

### Data Models / Contracts
MTP speculative config (serialized verbatim to `--speculative-config`):
```json
{"method": "qwen3_next_mtp", "num_speculative_tokens": 1}
```

### File Structure
- Modified: `charts/local-llm/values.yaml`, `charts/local-llm/templates/deployment.yaml`, `charts/local-llm/templates/NOTES.txt`, `charts/local-llm/Chart.yaml`, `gitops/rtx2000-ada-128gb-se.yaml`, `CLAUDE.md`, `HARDWARE.md`, `README.md`, `.aiassistant/rules/helm-chart.md`.
- No new files; no deletions.

### Risks
- **MoE-specific FlashInfer env from the QuantTrio doc doesn't apply to the dense 27B** — omit those; keep only generic sampler/allocator/idle env. Verify on device.
- **MTP draft head VRAM** — if headroom is tight at 128K, MTP or num_speculative_tokens may need lowering; documented as first knob to tune.
- **Sampling defaults** — Qwen3.6 may recommend different temperature/top_p than the coder model; verify and adjust.
- **Checkpoint quant format** — like the 80B, let vLLM auto-detect quantization (no explicit `--quantization`) unless the QuantTrio config requires otherwise.

# Testing

### Validation Approach
Static validation only (no live device in this environment): ensure the chart renders and lints, and that the rendered vLLM command matches the intended no-offload + MTP + 128K configuration.

### Key Scenarios
- `./scripts/lint.sh` passes (`helm lint` + `helm template`).
- Rendered `deployment.yaml` contains `--tensor-parallel-size 2`, `--max-model-len 131072`, the `--speculative-config` MTP JSON, `--reasoning-parser qwen3`, `--tool-call-parser qwen3_coder`, `--trust-remote-code`, and **does not** contain `--cpu-offload-gb`.
- Rendered args reference `QuantTrio/Qwen3.6-27B-AWQ` and served name `qwen3.6-27b`.
- `Chart.yaml.version` and `gitops` `spec.version` match.

### Edge Cases
- `--speculative-config` JSON is valid and single-quoted so YAML/shell pass it intact (mirror the existing `--override-generation-config | toJson` pattern).
- NCCL env + `--disable-custom-all-reduce` still present (TP=2 requirement unchanged).
- No stale references to "80B", "CPU offload", or `cpuOffloadGb` remain in chart or docs.

### Test Changes
No automated test framework exists beyond `scripts/lint.sh`; on-device runtime verification (VRAM fit, `/health`, tok/s with vs without MTP) is a manual follow-up noted in HARDWARE.md, not part of this change.

# Delivery Steps

### ✓ Step 1: Re-point chart values to Qwen3.6-27B with no offload + MTP
`charts/local-llm/values.yaml` describes Qwen3.6-27B AWQ, fitting in VRAM with no CPU offload and MTP enabled.

- Change `model.huggingfaceRepo` to `QuantTrio/Qwen3.6-27B-AWQ` and `model.servedName` to `qwen3.6-27b`.
- Remove the `vllm.cpuOffloadGb` value.
- Add `model.reasoningParser: qwen3` and a `vllm.speculative` block (`method: qwen3_next_mtp`, `num_speculative_tokens: 1`).
- Keep `tensorParallelSize: 2`, `maxModelLen: 131072`, `gpuMemoryUtilization: 0.90`; review sampling defaults for Qwen3.6.
- Rewrite the inline comments: replace the CPU-offload/Marlin-repack commentary with the VRAM-fit math (~10.5GB/GPU weights, ~1.5GB/GPU KV) and MTP rationale.

### ✓ Step 2: Update the vLLM deployment args and env
`charts/local-llm/templates/deployment.yaml` launches vLLM with no offload, MTP, reasoning parser, and trust-remote-code.

- Remove the `--cpu-offload-gb` arg and its comment.
- Add `--reasoning-parser {{ .Values.model.reasoningParser }}`, `--trust-remote-code`, and `--speculative-config` rendering `vllm.speculative` via `toJson` (single-quoted, mirroring `--override-generation-config`).
- Keep `--tensor-parallel-size`, `--disable-custom-all-reduce`, tool-call parser, generation-config override.
- Keep NCCL env + `PYTORCH_ALLOC_CONF`; add generic FlashInfer/idle env (`VLLM_USE_FLASHINFER_SAMPLER=0`, `VLLM_SLEEP_WHEN_IDLE=1`); omit MoE-only flags (dense model).
- Update the args header comment and startupProbe comment (~21GB download).

### ✓ Step 3: Bump versions and refresh user-facing chart docs
Chart version pins and NOTES reflect the new model, and the device rolls to the new version.

- Update `Chart.yaml` `description` to Qwen3.6-27B and bump `version` (e.g. `0.4.0`).
- Bump `gitops/rtx2000-ada-128gb-se.yaml` `spec.version` to match.
- Update `templates/NOTES.txt`: served name and ~21GB download wording.
- Run `./scripts/lint.sh` and verify the rendered deployment matches the intended args (no `--cpu-offload-gb`, has MTP/128K/parsers).

### ✓ Step 4: Update the canonical decision-trail and rules docs
`CLAUDE.md`, `HARDWARE.md`, and the AI-assistant rules document Qwen3.6-27B as the fixed model.

- Add a `HARDWARE.md` "Model decision trail" entry: switch to Qwen3.6-27B AWQ, fits both GPUs with no CPU offload, MTP speedup, sidesteps the 80B Marlin MoE-repack OOM bug.
- Update the "Model/runtime is fixed" constraint in `CLAUDE.md` and `.aiassistant/rules/helm-chart.md` to Qwen3.6-27B.
- Make minimal alignment edits to `README.md` (model name, no-offload, download size) keeping it short and emoji-free.