# Hardware: `rtx2000-ada-128gb-se`

Canonical, human-facing record of the target device's hardware, gathered via live
inspection (`tnctl ssh rtx2000-ada-128gb-se`) on 2026-07-13. Re-verify before trusting
this if it's more than a few months old — see "Re-verifying" below.

- **Device:** `rtx2000-ada-128gb-se`, namespace `teknoir-demo`, k3s v1.34.6+k3s1 (single-node server, containerd).
- **GPU:** 2x NVIDIA RTX 2000 **Ada Generation** (Ada Lovelace, compute capability **8.9** — not Blackwell), 16380 MiB VRAM each (32GB combined), no NVLink, driver 580.105.08, 70W power limit each.
- **CPU:** AMD Ryzen 5 5600X, 6 cores / 12 threads.
- **RAM:** 125GiB.
- **Disk:** 3.6T total; 751GB free at inspection time. An unrelated ~882GB `/home/anders` directory is why a `LowDiskSpace` alert fires on this node — not something this chart needs to address.
- **OS/runtime:** Teknoir OS on Ubuntu 22.04.5. GPU pods (`gpu-metrics-app`, `nvidia-exporter`) already run successfully on this node, confirming GPU passthrough works without an explicit `nvidia.com/gpu` device-plugin resource request.

## Correcting a stale claim

The sibling repo `openclaw-helm` (same device) describes its vLLM/DeepSeek-V4-Flash
config as running on "two 16GB RTX 2000 Pro **Blackwell** GPUs with NVFP4
acceleration." **This is incorrect for this device.** The GPUs are Ada Lovelace
(compute cap 8.9), not Blackwell, and Ada has no native FP4 tensor cores. Only
`openclaw-helm`'s Helm/GitOps structure and conventions were reused for this repo —
not its model or runtime choice. Do not repeat the Blackwell/NVFP4 assumption for
this device.

## Model decision trail

- **DeepSeek V4 Flash** (284B total / 13B active MoE): ruled out. Needs ~158GB
  native FP4 weights minimum; no viable quant fits the 32GB VRAM + 125GB RAM budget
  at usable speed, and mainline llama.cpp doesn't support the V4 architecture yet
  (unmerged, fork-only).
- **colibrì + GLM-5.2**: ruled out. Built for boxes *without* enough VRAM
  (disk-streamed experts, 0.05-2 tok/s); this device has two real GPUs that would
  sit idle under that approach.
- **Chosen: Qwen3-235B-A22B-Instruct-2507** (235B total / 22B active MoE) via
  llama.cpp, Unsloth `UD-Q4_K_XL` GGUF (~134GB on disk). MoE routed-expert
  tensors are kept on CPU/RAM (`-ot ".ffn_.*_exps.=CPU"`), everything else split
  across both GPUs (`--tensor-split 1,1`). This fits the real 32GB VRAM + 125GB RAM
  combined budget on mature, mainline-supported software. Reasoning quality is
  prioritized over throughput (expect low, single-digit tok/s from the heavy CPU
  offload — that's the accepted tradeoff, not a bug). See
  [`charts/local-llm/values.yaml`](charts/local-llm/values.yaml) and
  [`.aiassistant/rules/helm-chart.md`](.aiassistant/rules/helm-chart.md).

## Re-verifying

Specs can drift (driver updates, hardware swaps). Before trusting this document for
anything load-bearing:

```bash
tnctl device rtx2000-ada-128gb-se
tnctl ssh rtx2000-ada-128gb-se
```

Then check `nvidia-smi`, `free -h`, `df -h`, and `nproc` on the device directly.
