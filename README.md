# Local LLM Helm Chart

This chart deploys a local LLM server to a K3s cluster using the HelmChart CRD and
controller. Persistence uses hostPath under `/opt/teknoir/local-llm`.

The model backend serves **Qwen3-235B-A22B-Instruct-2507** (235B total / 22B active
MoE) via `llama-server` (llama.cpp), using Unsloth's `UD-Q4_K_XL` GGUF quant
(~134GB). MoE routed-expert tensors are kept on CPU/RAM; everything else is split
across both GPUs. This fits the target device's 32GB combined VRAM + 125GB RAM
budget on mature, mainline-supported software, prioritizing reasoning quality over
throughput. See [HARDWARE.md](HARDWARE.md) for the target device's specs and the
full model/runtime decision trail (why DeepSeek-V4-Flash, colibrì+GLM-5.2, and vLLM
were ruled out).

> The implementation of the Helm chart is the bare minimum to get it to work by design.

## Usage in Teknoir platform

Use the HelmChart CRD to deploy local-llm to a Device. A ready-to-use manifest for
`rtx2000-ada-128gb-se` is at
[gitops/rtx2000-ada-128gb-se.yaml](gitops/rtx2000-ada-128gb-se.yaml) — point the
platform's GitOps source at it directly.

```yaml
---
apiVersion: helm.cattle.io/v1
kind: HelmChart
metadata:
  name: local-llm
  namespace: default
spec:
  repo: https://tekn0ir.github.io/local-llm
  chart: local-llm
  targetNamespace: default
  valuesContent: |-
    # Example for minimal configuration (typically empty)
    
```

## Adding the repository

```bash
helm repo add local-llm https://tekn0ir.github.io/local-llm/
```

## Installing the chart

```bash
helm install local-llm local-llm/local-llm -f values.yaml
```

## Linting

```bash
./scripts/lint.sh
```

## Releasing

Bump `charts/local-llm/Chart.yaml`'s `version` (plain `X.Y.Z` on `main`,
`X.Y.Z-suffix` on `beta`) and push; `chart-releaser` publishes it to the GitHub
Pages repo automatically. To actually roll the new version out to
`rtx2000-ada-128gb-se` for testing, also bump `spec.version` in
[gitops/rtx2000-ada-128gb-se.yaml](gitops/rtx2000-ada-128gb-se.yaml) to match, in
the same commit — the device's helm-controller only re-applies the chart when
that field changes.
