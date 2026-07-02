#!/opt/homebrew/bin/bash
# ============================================================================
# tests/test_intent_validate.sh — intent-predicate validator e2e tests
#
# Covers:
#   1. Real repo struct.json — must PASS all six predicates
#   2. Fixture struct with select_one_of violation — must FAIL with predicate cited
#   3. Fixture struct with invariant violation — must FAIL with predicate cited
#   4. CLI surface (--json, exit codes)
# ============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

GENERATOR="$ROOT_DIR/generators/intent_validate.sh"

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
check_rc() {
    local name="$1" want="$2"; shift 2
    local got=0
    "$@" >/dev/null 2>&1 || got=$?
    if [[ "$got" == "$want" ]]; then
        printf '  [OK]   %s (exit %d)\n' "$name" "$got"
        pass=$((pass+1))
    else
        printf '  [FAIL] %s (exit %d, want %d)\n' "$name" "$got" "$want"
        fail=$((fail+1))
        EXIT_CODE=1
    fi
}

echo "==============================================="
echo "  intent_validate tests"
echo "==============================================="
echo

# ===================== Test 1: real repo struct.json =====================
echo "[test 1] real repo struct.json — all six predicates must PASS"
cd "$ROOT_DIR"
check_rc "intent_validate passes real struct.json" 0 \
    /opt/homebrew/bin/bash "$GENERATOR"

REPORT=$(/opt/homebrew/bin/bash "$GENERATOR" --json)
check "report.ok is true"  bash -c "echo '$REPORT' | jq -e '.ok == true'"
check "all 6 predicates ok" bash -c "echo '$REPORT' | jq -e '[.predicates | to_entries[].value.ok] | all'"
check "summary.predicates_passed == 6" bash -c "echo '$REPORT' | jq -e '.summary.predicates_passed == 6'"
check "summary.total_violations == 0" bash -c "echo '$REPORT' | jq -e '.summary.total_violations == 0'"
echo

# ===================== Test 2: select_one_of violation =====================
echo "[test 2] select_one_of violation — kept both branches in resolved set"
F2="$TMP_DIR/struct2.json"
cat > "$F2" <<'EOF'
{
  "schema_version": "3.0",
  "modules": [
    { "name": "x", "description": "x", "components": [
      { "name": "A", "description": "x", "imports": [] },
      { "name": "B", "description": "x", "imports": [] },
      { "name": "C", "description": "x", "imports": [] }
    ]}
  ],
  "phases": [
    { "phase": "p1", "order": 1, "mode": "select_one", "description": "x",
      "core_components": ["A"],
      "select_one_of": ["B", "C"] }
  ]
}
EOF

# Sanity: default rule (pick first option = B) should PASS.
check_rc "default rule picks first option and passes" 0 \
    /opt/homebrew/bin/bash "$GENERATOR" --struct "$F2"

# Now feed --selection C to violate (both B and C in resolved because no pruning).
# Actually, the validator checks |resolved ∩ S|; default puts B (selection) AND B is in resolved.
# To violate, we need a candidate plan where resolved has BOTH B and C.
PLAN_VIOLATING="$TMP_DIR/plan_violating.json"
cat > "$PLAN_VIOLATING" <<'EOF'
{
  "resolved": {
    "selected_components": ["A", "B", "C"],
    "selections": { "p1": "B" }
  }
}
EOF
check_rc "explicit plan with both branches FAILS" 1 \
    /opt/homebrew/bin/bash "$GENERATOR" --struct "$F2" --plan "$PLAN_VIOLATING"

# Confirm message cites the predicate.
set +e
REP=$(/opt/homebrew/bin/bash "$GENERATOR" --struct "$F2" --plan "$PLAN_VIOLATING" --json)
set -e
check "violation cites select_one_of" bash -c "echo '$REP' | jq -e '.predicates.select_one_of.ok == false'"
check "violation message names phase" bash -c "echo '$REP' | jq -e '.predicates.select_one_of.violations[0].message | contains(\"p1\")'"
echo

# ===================== Test 3: invariant violation =====================
echo "[test 3] invariant violation — predicate fails on resolved set"
F3="$TMP_DIR/struct3.json"
cat > "$F3" <<'EOF'
{
  "schema_version": "3.0",
  "modules": [
    { "name": "x", "description": "x", "components": [
      { "name": "Good", "description": "has description", "imports": [] },
      { "name": "Bad",  "description": "",             "imports": [] }
    ]}
  ],
  "phases": [
    { "phase": "p1", "order": 1, "mode": "sequential", "description": "x",
      "core_components": ["Good", "Bad"] }
  ]
}
EOF

INV3="$TMP_DIR/invariants3.json"
cat > "$INV3" <<'EOF'
[
  {
    "name": "every_component_has_description",
    "scope": "all_components",
    "quantifier": "forall",
    "predicate": "(.description // \"\") | length > 0",
    "message": "every component must have a non-empty description"
  }
]
EOF

check_rc "invariant violation FAILS gate" 1 \
    /opt/homebrew/bin/bash "$GENERATOR" --struct "$F3" --invariants "$INV3"

set +e
REP=$(/opt/homebrew/bin/bash "$GENERATOR" --struct "$F3" --invariants "$INV3" --json)
set -e
check "violation cites invariant" bash -c "echo '$REP' | jq -e '.predicates.invariant.ok == false'"
check "violation lists Bad as culprit" bash -c "echo '$REP' | jq -e '.predicates.invariant.violations[0].location | contains(\"Bad\")'"
check "violation message non-empty"   bash -c "echo '$REP' | jq -e '.predicates.invariant.violations[0].message | length > 0'"
echo

# ===================== Test 4: invariant satisfaction =====================
echo "[test 4] invariant satisfied — both components have descriptions"
F4="$TMP_DIR/struct4.json"
cat > "$F4" <<'EOF'
{
  "schema_version": "3.0",
  "modules": [
    { "name": "x", "description": "x", "components": [
      { "name": "Good1", "description": "first",  "imports": [] },
      { "name": "Good2", "description": "second", "imports": [] }
    ]}
  ],
  "phases": [
    { "phase": "p1", "order": 1, "mode": "sequential", "description": "x",
      "core_components": ["Good1", "Good2"] }
  ]
}
EOF
check_rc "all-descriptions invariant passes" 0 \
    /opt/homebrew/bin/bash "$GENERATOR" --struct "$F4" --invariants "$INV3"
echo

# ===================== Test 5: CLI surface =====================
echo "[test 5] CLI surface"
check "--json output is valid JSON"  bash -c "/opt/homebrew/bin/bash '$GENERATOR' --json | jq empty"
check_rc "missing struct fails (exit 2)" 2 \
    /opt/homebrew/bin/bash "$GENERATOR" --struct /nonexistent/struct.json
echo

echo "  passed: $pass"
echo "  failed: $fail"
echo "==============================================="
exit $EXIT_CODE