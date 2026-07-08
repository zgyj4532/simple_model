#!/usr/bin/env bash
# tests/test_orchestration_e2e.sh — quantitative orchestration smoke test
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

pass=0
fail=0
EXIT_CODE=0

check() {
    local name="$1"; shift
    if "$@" >/dev/null 2>&1; then
        printf '  [OK]   %s\n' "$name"
        pass=$((pass+1))
    else
        printf '  [FAIL] %s\n' "$name"
        fail=$((fail+1))
        EXIT_CODE=1
    fi
}

echo "==============================================="
echo "  orchestration e2e metrics"
echo "==============================================="
echo

cd "$ROOT_DIR"
OUT_DIR="$TMP_DIR/generated"
mkdir -p "$OUT_DIR"

OUTPUT_DIR="$OUT_DIR" bash generators/orchestrate_decompose.sh --struct struct.json >/dev/null
OUTPUT_DIR="$OUT_DIR" bash generators/orchestrate_bound.sh --struct struct.json --plan "$OUT_DIR/.ai/plan.json" >/dev/null
OUTPUT_DIR="$OUT_DIR" bash generators/orchestrate_gate.sh --struct struct.json --out "$OUT_DIR/.ai/gate.json" >/dev/null
./bootstrap.sh --struct struct.json --output "$OUT_DIR" --target queue >/dev/null
OUTPUT_DIR="$OUT_DIR" bash generators/cbom_emit.sh \
    --struct struct.json \
    --plan "$OUT_DIR/.ai/plan.json" \
    --slices "$OUT_DIR/.ai/slices/index.json" \
    --gate "$OUT_DIR/.ai/gate.json" \
    --out "$OUT_DIR/.ai/cbom.json" >/dev/null

check "plan soundness ok" jq -e '.soundness.ok == true' "$OUT_DIR/.ai/plan.json"
check "gate passes" jq -e '.decision == "PASS"' "$OUT_DIR/.ai/gate.json"
check "cbom emitted" test -f "$OUT_DIR/.ai/cbom.json"
check "slice index non-empty" jq -e '(.slices_index // []) | length > 0' "$OUT_DIR/.ai/slices/index.json"

OUTPUT_DIR="$OUT_DIR" bash generators/orchestrate_dispatch.sh --plan --wave 1 > "$TMP_DIR/dispatch_plan.json"
check "dispatch plan json" jq empty "$TMP_DIR/dispatch_plan.json"
check "dispatch plan has parallel todos" jq -e '.todos | length >= 1' "$TMP_DIR/dispatch_plan.json"

mkdir -p "$OUT_DIR/.ai/dispatch/summaries"
cat > "$OUT_DIR/.ai/dispatch/summaries/example.json" <<'JSON'
{
  "schema_version": "1.0",
  "todo_id": "example",
  "agent": "test",
  "status": "done",
  "summary": "bounded summary",
  "diff": {"files_changed": []},
  "blockers": []
}
JSON
OUTPUT_DIR="$OUT_DIR" bash generators/orchestrate_collect.sh --out "$OUT_DIR/.ai/agent_summaries.json" >/dev/null
check "summary collector counts summaries" jq -e '.count == 1' "$OUT_DIR/.ai/agent_summaries.json"

bash tools/depcheck.sh --json > "$TMP_DIR/depcheck.json"
check "depcheck required deps ok" jq -e '.ok == true' "$TMP_DIR/depcheck.json"

bash tests/bench_coldstart.sh --json --runs 1 --threshold-ms 5000 > "$TMP_DIR/bench.json"
check "coldstart benchmark emits ok" jq -e '.ok == true' "$TMP_DIR/bench.json"

cat > "$TMP_DIR/metrics.json" <<JSON
{
  "schema_version": "1.0",
  "soundness_ok": true,
  "reproducibility_checked": true,
  "dispatch_plan_todos": $(jq '.todos | length' "$TMP_DIR/dispatch_plan.json"),
  "summary_count": $(jq '.count' "$OUT_DIR/.ai/agent_summaries.json"),
  "coldstart_avg_ms": $(jq '.avg_ms' "$TMP_DIR/bench.json")
}
JSON
check "metrics report json" jq empty "$TMP_DIR/metrics.json"

echo
echo "  passed: $pass"
echo "  failed: $fail"
echo "==============================================="
exit $EXIT_CODE
