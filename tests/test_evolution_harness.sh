#!/opt/homebrew/bin/bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
out=$(bash "$ROOT_DIR/examples/evolution-bench/run.sh")
echo "$out" | jq -e '.ok == true and .summary.steps == 3' >/dev/null
echo "  [OK]   evolution harness smoke"
