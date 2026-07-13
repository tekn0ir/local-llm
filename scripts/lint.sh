#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CHART_DIR="$ROOT_DIR/charts/local-llm"

helm lint "$CHART_DIR"
helm template local-llm "$CHART_DIR" >/dev/null

echo "Helm lint and template completed."
