## Context

The user asked which web interface is best for testing and evaluating LLMs, in the context of this repo's llama-server-based Qwen3-235B deployment. After research confirmed no web UI currently exists in this repo (the chart is intentionally API-only, `ClusterIP`, with `NodePort` reserved by convention for a future dedicated web UI chart, mirroring the sibling `openclaw-helm` pattern), I asked the user whether they wanted a recommendation or a deployment plan. They chose **just a recommendation** — no code changes.

## Outcome

No implementation is needed. The recommendation (Open WebUI as primary suggestion, with llama-server's built-in UI and Promptfoo as situational alternatives) was delivered directly in the chat response.

## If the user later wants this deployed

Revisit this as a new chart/template following the `openclaw-helm` sibling convention: a separate Helm chart (or template within this chart) exposing the UI via a fixed `NodePort`, configured to point at the existing `local-llm` `ClusterIP` service's OpenAI-compatible `/v1` endpoint. No changes to `charts/local-llm/values.yaml`, `templates/deployment.yaml`, or `templates/service.yaml` would be required for the existing API service itself.
