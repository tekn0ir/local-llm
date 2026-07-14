# CLAUDE.md

## Project overview

Single-chart Helm GitOps repo that deploys a local LLM server to a K3s
cluster on the Teknoir platform, targeting the device `rtx2000-ada-128gb-se`
(2x NVIDIA RTX 2000 Ada, 32GB combined VRAM, 125GB RAM). The model backend is
**Qwen3.6-27B** (AWQ 4-bit) served via **vLLM**, tensor-parallel across both
GPUs with no CPU offload. See [README.md](README.md) for usage/install and
[HARDWARE.md](HARDWARE.md) for the device specs and full model/runtime
decision trail.

## Key files

- `charts/local-llm/` — the Helm chart: `Chart.yaml`, `values.yaml`,
  `templates/deployment.yaml`, `templates/service.yaml`, `templates/NOTES.txt`,
  plus `templates/deployment-open-webui.yaml` /
  `templates/service-open-webui.yaml` for the Open WebUI chat interface.
- `HARDWARE.md` — canonical hardware specs (re-verify before trusting if
  stale) and the model/runtime decision trail.
- `scripts/lint.sh` — helm lint + helm template smoke test.
- `.aiassistant/rules/hardware.md` and `.aiassistant/rules/helm-chart.md` —
  equivalent always-applied rules for a different AI assistant; kept in sync
  with the constraints below.

## Hard constraints

- **Zero configuration**: chart defaults are tuned specifically for
  `rtx2000-ada-128gb-se`. Everything else is hardcoded in the chart.
  `valuesContent` during install should stay empty in normal use.
- **Model/runtime is fixed**: Qwen3.6-27B (AWQ 4-bit) via vLLM — not
  llama.cpp, not DeepSeek-V4-Flash, not colibrì+GLM-5.2, not the other frontier
  open coders (GLM-5.2, DeepSeek V4, Qwen3-Coder-480B). Read HARDWARE.md's
  "Model decision trail" before proposing a different model or runtime for
  this device.
- **Persistence** must use `hostPath` under `/opt/teknoir/local-llm`.
- **Service type** must stay `ClusterIP` for the model API — NodePort is
  reserved for actual web UIs on this platform.
- **No `nvidia.com/gpu` resource request/limit.** This device's nvidia
  runtime doesn't register GPU as a schedulable device-plugin resource;
  setting it leaves the pod stuck Pending. GPU access is granted purely via
  `runtimeClassName: nvidia`.
- Do not repeat the sibling `openclaw-helm` repo's claim that this device has
  Blackwell/NVFP4 GPUs — it's Ada Lovelace (compute capability 8.9), not
  Blackwell.
- Keep `README.md` short, without icons/emojis; edit it only to align with
  actual changes made or to fix direct errors.

## Commands

- `./scripts/lint.sh` — runs `helm lint` and `helm template` as a smoke test.
  No other build or test tooling exists in this repo yet.

## CI/Release

- `.github/workflows/beta.yml` — push to `beta` releases a pre-release chart
  version; `charts/local-llm/Chart.yaml`'s `version` must match
  `X.Y.Z-suffix`.
- `.github/workflows/release.yml` — push to `main` releases a stable chart
  version; `version` must match plain `X.Y.Z`.
- Both are driven by `helm/chart-releaser-action` off the version field in
  `charts/local-llm/Chart.yaml`. CI does **not** touch
  `gitops/rtx2000-ada-128gb-se.yaml` — that's a manual step (next).

## Rolling a new version out to the device

`gitops/rtx2000-ada-128gb-se.yaml`'s `spec.version` pins the chart version the
device actually runs; the platform's helm-controller only re-applies the chart
when that field changes. When bumping `charts/local-llm/Chart.yaml`'s
`version` to cut a release or beta build meant to be tested on
`rtx2000-ada-128gb-se`, also bump `spec.version` in
`gitops/rtx2000-ada-128gb-se.yaml` to match, in the same commit.
