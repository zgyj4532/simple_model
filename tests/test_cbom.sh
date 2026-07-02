#!/opt/homebrew/bin/bash
# ============================================================================
# tests/test_cbom.sh — cbom_emit.sh e2e tests
#
# Covers:
#   1. CBOM emits a valid JSON conforming to the schema's required fields
#   2. Reproducibility: re-run with identical inputs → bit-identical CBOM
#   3. Drift detection: mutate one input → CBOM diffs in the expected field
# ============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

GENERATOR="$ROOT_DIR/generators/cbom_emit.sh"

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
echo "  cbom tests"
echo "==============================================="
echo

# ===================== Setup: run decompose + bound + gate =====================
cd "$ROOT_DIR"
/opt/homebrew/bin/bash "$ROOT_DIR/generators/orchestrate_decompose.sh"  > /dev/null 2>&1
/opt/homebrew/bin/bash "$ROOT_DIR/generators/orchestrate_bound.sh"    > /dev/null 2>&1
/opt/homebrew/bin/bash "$ROOT_DIR/generators/orchestrate_gate.sh" --struct struct.json > /dev/null 2>&1

PLAN="$ROOT_DIR/generated/.ai/plan.json"
SLICES="$ROOT_DIR/generated/.ai/slices/index.json"
GATE="$ROOT_DIR/generated/.ai/gate.json"

# ===================== Test 1: schema validity =====================
echo "[test 1] CBOM conforms to schema's required fields"
CBOM1="$ROOT_DIR/generated/.ai/cbom.json"
rm -f "$CBOM1"

check_rc "cbom_emit exits 0" 0 \
    /opt/homebrew/bin/bash "$GENERATOR" \
        --struct struct.json --plan "$PLAN" --slices "$SLICES" --gate "$GATE"

check "cbom.json exists"     test -f "$CBOM1"
check "cbom.json valid JSON" jq empty "$CBOM1"
check "schema_version == 1.0"      bash -c "jq -e '.schema_version == \"1.0\"' '$CBOM1'"
check "project field present"      bash -c "jq -e '.project | length > 0' '$CBOM1'"
check "intent_hash matches sha256" bash -c "jq -e '.intent_hash | test(\"^sha256:[a-f0-9]{64}$\")' '$CBOM1'"
check "plan_hash matches sha256"   bash -c "jq -e '.plan_hash | test(\"^sha256:[a-f0-9]{64}$\")' '$CBOM1'"
check "context_slices non-empty"   bash -c "jq -e '(.context_slices | length) > 0' '$CBOM1'"
check "code_hashes is object"      bash -c "jq -e '.code_hashes | type == \"object\"' '$CBOM1'"
check "reproducible is null/bool"   bash -c "jq -e '.reproducible == null or .reproducible == true or .reproducible == false' '$CBOM1'"
check "gate block present"         bash -c "jq -e '.gate != null' '$CBOM1'"
echo

# ===================== Test 2: reproducibility =====================
echo "[test 2] reproducibility — re-run with identical inputs → bit-identical CBOM"
CBOM2="$TMP_DIR/cbom2.json"
cp "$CBOM1" "$TMP_DIR/cbom1.json"

/opt/homebrew/bin/bash "$GENERATOR" \
    --struct struct.json --plan "$PLAN" --slices "$SLICES" --gate "$GATE" \
    --out "$CBOM2" > /dev/null 2>&1

# Compare sans timestamp.
A=$(jq -S 'del(.generated_at, .reproducible)' "$TMP_DIR/cbom1.json")
B=$(jq -S 'del(.generated_at, .reproducible)' "$CBOM2")
if [[ "$A" == "$B" ]]; then
    printf '  [OK]   CBOMs bit-identical (sans timestamp + reproducible)\n'
    pass=$((pass+1))
else
    printf '  [FAIL] CBOMs differ\n'
    diff <(echo "$A") <(echo "$B") | head -10
    fail=$((fail+1))
    EXIT_CODE=1
fi
echo

# ===================== Test 3: drift detection =====================
echo "[test 3] drift — mutate plan, expect intent_hash or plan_hash to change"
# Make a copy of plan with one component renamed.
PLAN_BAD="$TMP_DIR/plan_bad.json"
jq '.plan[0].components[0] = "ModifiedComponent"' "$PLAN" > "$PLAN_BAD"

CBOM_BAD="$TMP_DIR/cbom_bad.json"
/opt/homebrew/bin/bash "$GENERATOR" \
    --struct struct.json --plan "$PLAN_BAD" --slices "$SLICES" --gate "$GATE" \
    --out "$CBOM_BAD" > /dev/null 2>&1

# Compare: plan_hash MUST differ; intent_hash SHOULD be unchanged.
ORIG_PLAN_HASH=$(jq -r '.plan_hash' "$CBOM1")
NEW_PLAN_HASH=$(jq -r '.plan_hash' "$CBOM_BAD")
ORIG_INTENT_HASH=$(jq -r '.intent_hash' "$CBOM1")
NEW_INTENT_HASH=$(jq -r '.intent_hash' "$CBOM_BAD")

if [[ "$ORIG_PLAN_HASH" != "$NEW_PLAN_HASH" ]]; then
    printf '  [OK]   plan_hash changed after plan mutation\n'
    pass=$((pass+1))
else
    printf '  [FAIL] plan_hash unchanged\n'
    fail=$((fail+1))
    EXIT_CODE=1
fi
if [[ "$ORIG_INTENT_HASH" == "$NEW_INTENT_HASH" ]]; then
    printf '  [OK]   intent_hash stable (struct.json unchanged)\n'
    pass=$((pass+1))
else
    printf '  [FAIL] intent_hash unexpectedly changed\n'
    fail=$((fail+1))
    EXIT_CODE=1
fi
echo

# ===================== Test 4: reproducibility flag =====================
echo "[test 4] reproducibility flag — previous-run comparison"
# Run with --prev pointing to the unchanged CBOM.
CBOM_REPRO="$TMP_DIR/cbom_repro.json"
/opt/homebrew/bin/bash "$GENERATOR" \
    --struct struct.json --plan "$PLAN" --slices "$SLICES" --gate "$GATE" \
    --prev "$CBOM1" --out "$CBOM_REPRO" > /dev/null 2>&1

REPRO=$(jq -r '.reproducible' "$CBOM_REPRO")
if [[ "$REPRO" == "true" ]]; then
    printf '  [OK]   reproducible=true (matches previous CBOM)\n'
    pass=$((pass+1))
else
    printf '  [FAIL] reproducible=%s (want true)\n' "$REPRO"
    fail=$((fail+1))
    EXIT_CODE=1
fi
echo

# ===================== Test 5: --json output =====================
echo "[test 5] CLI surface"
check "--json output is valid JSON" \
    bash -c "/opt/homebrew/bin/bash '$GENERATOR' --struct struct.json --plan '$PLAN' --slices '$SLICES' --json | jq empty"
check_rc "missing --plan fails (exit 2)" 2 \
    /opt/homebrew/bin/bash "$GENERATOR" --struct struct.json --slices "$SLICES"
echo

echo "  passed: $pass"
echo "  failed: $fail"
echo "==============================================="
exit $EXIT_CODE