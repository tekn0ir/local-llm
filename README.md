# Local LLM Helm Chart

This chart deploys a local LLM server to a K3s cluster using the HelmChart CRD and
controller. Persistence uses hostPath under `/opt/teknoir/local-llm`.

The model backend serves **Qwen3-Coder-Next** (80B total / 3B active MoE), a
coding/agentic specialist, via **vLLM**, using the `bullpoint/Qwen3-Coder-Next-AWQ-4bit`
AWQ INT4 checkpoint (~40GB). The model is split across both GPUs with tensor
parallelism, and the remainder that doesn't fit in 32GB combined VRAM is spilled to
system RAM via vLLM's CPU offload. This is dense, PCIe-bound offload, so throughput
is modest — the tradeoff accepted for the 80B's coding quality over a smaller model
that fits entirely in VRAM. See [HARDWARE.md](HARDWARE.md) for the target device's
specs and the full model/runtime decision trail (why DeepSeek-V4-Flash,
colibrì+GLM-5.2, and the other open coders were ruled out).

The chart also deploys [Open WebUI](https://github.com/open-webui/open-webui) as a
chat interface for testing/evaluating the model, wired to vLLM's
OpenAI-compatible API. It's exposed via NodePort `30080` (the model API itself
stays ClusterIP-only).

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
