#!/usr/bin/env bash
set -euo pipefail
OUT="${1:-examples/github-actions/pr-gate.yml}"
mkdir -p "$(dirname "$OUT")"
cat > "$OUT" <<'YAML'
name: simple_model PR gate
on:
  pull_request:
    branches: ["**"]
permissions:
  contents: read
  pull-requests: write
jobs:
  simple-model:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 0
      - run: sudo apt-get update && sudo apt-get install -y jq
      - run: bash ./bootstrap.sh --validate
      - run: bash ./bootstrap.sh --pr-gate . --json > simple_model_pr_gate.json
      - run: bash generators/pr_comment.sh simple_model_pr_gate.json > simple_model_pr_gate.md
      - uses: actions/upload-artifact@v4
        with:
          name: simple-model-pr-gate
          path: |
            simple_model_pr_gate.json
            simple_model_pr_gate.md
YAML
echo "[OK] github action: $OUT"
