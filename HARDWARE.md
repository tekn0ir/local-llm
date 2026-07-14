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
- **Prior choice: Qwen3-235B-A22B-Instruct-2507** (235B total / 22B active MoE)
  via llama.cpp, Unsloth `UD-Q4_K_XL` GGUF (~134GB on disk), MoE routed-expert
  tensors kept on CPU/RAM. Served general-purpose instruct use well on mature,
  mainline-supported software, prioritizing reasoning quality over throughput.
  Superseded below by a coding-specialist pick on vLLM.

### Switch to Qwen3-Coder-Next on vLLM (2026-07)

Re-picked the model for **coding** and switched serving frameworks to **vLLM**
(user request, overriding the prior "llama.cpp, not vLLM" choice above):

- **GLM-5.2, DeepSeek V4, Qwen3-Coder-480B**: ruled out. None fit the 32GB
  VRAM + 125GB RAM budget at any usable quant.
- **DeepSeek "Coder" line**: ruled out. V2-236B is older/slower and fills RAM;
  Lite-16B is too weak; V3.2/V4 are too big.
- **Qwen3-Coder-Next-30B** (fits entirely in 32GB VRAM): considered as the
  fallback if the 80B's CPU-offload throughput proves unacceptable on device,
  but not chosen — the user prioritized the 80B's coding quality.
- **Chosen: Qwen3-Coder-Next** (80B total / 3B active MoE, Feb 2026), a
  coding/agentic specialist (~70.6% SWE-bench Verified, #1 self-hostable coder
  at release, 256K native context, Apache-2.0), served via **vLLM** using the
  `bullpoint/Qwen3-Coder-Next-AWQ-4bit` checkpoint (AWQ INT4, ~40–46GB).
  - vLLM was chosen over llama.cpp here because it natively supports the
    Qwen3-Next hybrid DeltaNet+MoE architecture (since Sep 2025), multi-token
    prediction, and a dedicated `qwen3_coder` tool-call parser for agentic use.
  - Quant: the checkpoint is packaged as **compressed-tensors** (an
    llm-compressor AWQ recipe), not vLLM's native AWQ format -- vLLM must
    auto-detect the quantization method rather than being told `awq_marlin`
    explicitly, or it errors out on a mismatch with the checkpoint's own
    config. FP8 W8A8 is also supported on Ada (cc 8.9) but its ~92GB
    footprint is far too large for this budget. GGUF is not vLLM's native path.
  - **Critical hardware reality:** the 80B at 4-bit (~40GB) does not fit in
    32GB combined VRAM, so vLLM spills part of the weights to system RAM via
    `--cpu-offload-gb` (a per-GPU value). This is dense, PCIe-bound offload —
    slower than llama.cpp's expert-specific offload, giving up much of vLLM's
    throughput advantage — but the user accepted this tradeoff for the 80B's
    coding quality over the 30B-that-fits-in-VRAM alternative. The 125GB RAM
    easily covers the offloaded remainder. See
    [`charts/local-llm/values.yaml`](charts/local-llm/values.yaml) and
    [`.aiassistant/rules/helm-chart.md`](.aiassistant/rules/helm-chart.md).
  - **NCCL multi-GPU init hang (no NVLink / no PCIe P2P).** With
    `--tensor-parallel-size 2`, NCCL by default probes PCIe P2P and InfiniBand
    to set up the two-GPU collective. This board has no NVLink and P2P between
    the two cards isn't usable, so NCCL hangs at distributed init: both GPUs
    sit at 100% util with almost no memory allocated, the pod never reaches
    weight download, and `/health` never comes up (observed: 40+ min, no error
    in the logs, last line `vLLM is using nccl==...`). Fix baked into the
    deployment: `NCCL_P2P_DISABLE=1` + `NCCL_IB_DISABLE=1` (fall back to
    shared-memory/host staging) and `--disable-custom-all-reduce` (vLLM's
    custom all-reduce also needs P2P). This is the same "verify TP sees both
    GPUs" risk flagged during the switch, resolved.

## Re-verifying

Specs can drift (driver updates, hardware swaps). Before trusting this document for
anything load-bearing:

```bash
tnctl device rtx2000-ada-128gb-se
tnctl ssh rtx2000-ada-128gb-se
```

Then check `nvidia-smi`, `free -h`, `df -h`, and `nproc` on the device directly.
