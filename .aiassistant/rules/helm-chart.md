---
apply: always
---

* Zero configuration
  * All configuration has defaults tuned for the `rtx2000-ada-128gb-se` device; see [HARDWARE.md](../../HARDWARE.md).
  * Everything else is hardcoded in the Helm chart.
  * Values/valuesContent during chart installation should be empty in most use cases.
* Model/runtime choice: Qwen3-235B-A22B-Instruct-2507 via llama.cpp (not vLLM,
  not DeepSeek-V4-Flash, not colibrì+GLM-5.2). This was decided after live hardware
  inspection and research — see HARDWARE.md's "Model decision trail" before
  proposing a different model or runtime for this device.
* README.md should be updated
  * Keep it short, without icons, mostly adjusting things to align with changes made or fixing direct errors.
* Teknoir platform requirements
  * Persistence volumes should use hostPath under /opt/teknoir/local-llm.
  * ClusterIP for the model API service (NodePort is reserved for actual web UIs).
  * Open WebUI (`templates/deployment-open-webui.yaml` / `service-open-webui.yaml`)
    is the actual web UI using that reserved NodePort (`30080`); it talks to
    llama-server's OpenAI-compatible API, no GPU needed.
* Rolling a new version out to the device
  * `gitops/rtx2000-ada-128gb-se.yaml`'s `spec.version` pins the chart version the device runs; CI does not update it.
  * When bumping `charts/local-llm/Chart.yaml`'s `version` for a release/beta meant to be tested on `rtx2000-ada-128gb-se`, bump `spec.version` there too, in the same commit.
