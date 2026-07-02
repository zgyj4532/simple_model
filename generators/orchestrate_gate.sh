#!/usr/bin/env bash
# ============================================================================
# generators/orchestrate_gate.sh — intent-conformance + contract merge gate (Wave 3)
#
# Runs the deterministic merge-gate on a (post-merge) struct + optional
# chimeric verify-results. Extends chimeric_verify exit-code semantics:
#
#   0  PASS — all gates passed (or skipped)
#   11 contract failed
#   12 round_trip failed
#   13 golden failed
#   14 invariants failed
#   15 multi-mode failed (>=2 modes)
#   16 intent conformance failed (NEW: the Gate-level invariant)
#   17 intent conformance failed AND another mode failed (composite)
#
# Inputs:
#   --struct           merged struct.json (post-merge state)
#   --invariants       optional invariants JSON array (custom Gate-level predicates)
#   --verify-results   optional chimeric verify-results.json (legacy contract checks)
#   --base             optional pre-merge struct for diff (informational)
#
# Outputs:
#   generated/.ai/gate.json — {decision, exit_code, checks, gate_id}
#
# Usage:
#   bash generators/orchestrate_gate.sh --struct struct.json --invariants inv.json
# ============================================================================
set -euo pipefail
# shellcheck disable=SC1091
source "$(dirname "${BASH_SOURCE[0]}")/_lib.sh"

STRUCT_FILE=""
INVARIANTS_FILE=""
VERIFY_RESULTS=""
BASE_STRUCT=""
OUT_FILE="${OUTPUT_DIR:-./generated}/.ai/gate.json"
JSON_OUT=0

usage() {
    sed -n '2,/^# ====/p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//; s/^===.*//'
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --struct)         STRUCT_FILE="$2"; shift 2 ;;
        --invariants)     INVARIANTS_FILE="$2"; shift 2 ;;
        --verify-results) VERIFY_RESULTS="$2"; shift 2 ;;
        --base)           BASE_STRUCT="$2"; shift 2 ;;
        --out)            OUT_FILE="$2"; shift 2 ;;
        --json)           JSON_OUT=1; shift ;;
        -h|--help)        usage; exit 0 ;;
        *) echo "[gate] unknown arg: $1" >&2; exit 2 ;;
    esac
done

[[ -n "$STRUCT_FILE" ]] || { echo "[FAIL] --struct required" >&2; exit 2; }
[[ -f "$STRUCT_FILE" ]] || { echo "[FAIL] struct not found: $STRUCT_FILE" >&2; exit 2; }

mkdir -p "$(dirname "$OUT_FILE")"

vsay()  { [[ "$JSON_OUT" == "1" ]] && return 0; printf '  %s\n' "$*"; }
vok()   { [[ "$JSON_OUT" == "1" ]] && return 0; printf '  [OK]   %s\n' "$*"; }
vfail() { printf '  [FAIL] %s\n' "$*" >&2; }

# ---------- 1. Intent conformance via intent_validate ----------
TMP=$(mktemp)
trap 'rm -f "$TMP"' EXIT

INV_ARGS=()
[[ -n "$INVARIANTS_FILE" ]] && INV_ARGS+=(--invariants "$INVARIANTS_FILE")

# intent_validate always exits 0 (PASS) or 1 (FAILURE). Capture both.
set +e
/opt/homebrew/bin/bash "$(dirname "${BASH_SOURCE[0]}")/intent_validate.sh" --struct "$STRUCT_FILE" "${INV_ARGS[@]}" --json > "$TMP.inv_report" 2>/dev/null
INV_RC=$?
set -e

INTENT_OK=$(jq -r '.ok' "$TMP.inv_report" 2>/dev/null || echo "false")
INTENT_VIOLATIONS=$(jq -c '.predicates | to_entries | map({predicate:.key, ok:.value.ok, violations:.value.violations}) | map(select(.ok == false))' "$TMP.inv_report" 2>/dev/null || echo "[]")

# ---------- 2. Contract verification (if chimeric results supplied) ----------
CONTRACT_OK=true
CONTRACT_FAIL_MODES="[]"
if [[ -n "$VERIFY_RESULTS" ]] && [[ -f "$VERIFY_RESULTS" ]]; then
    # Reuse chimeric's per-mode status.
    MODES_STATUS=$(jq -c '.results // [] | map(.modes // {}) |
        {
            contract:    ([.[] | select(.contract.status == "fail")] | length),
            round_trip:  ([.[] | select(.round_trip.status == "fail")] | length),
            golden:      ([.[] | select(.golden.status == "fail")] | length),
            invariants:  ([.[] | select(.invariants.status == "fail")] | length)
        }' "$VERIFY_RESULTS" 2>/dev/null || echo '{}')
    contract_fail=$(echo "$MODES_STATUS" | jq '.contract // 0')
    rt_fail=$(echo "$MODES_STATUS" | jq '.round_trip // 0')
    gold_fail=$(echo "$MODES_STATUS" | jq '.golden // 0')
    inv_fail_chim=$(echo "$MODES_STATUS" | jq '.invariants // 0')

    fails=()
    [[ "$contract_fail" -gt 0 ]] && fails+=(11)
    [[ "$rt_fail"       -gt 0 ]] && fails+=(12)
    [[ "$gold_fail"     -gt 0 ]] && fails+=(13)
    [[ "$inv_fail_chim" -gt 0 ]] && fails+=(14)

    if [[ ${#fails[@]} -gt 0 ]]; then
        CONTRACT_OK=false
        if [[ ${#fails[@]} -ge 2 ]]; then
            CONTRACT_FAIL_MODES='[15]'
        else
            CONTRACT_FAIL_MODES=$(printf '%s\n' "${fails[@]}" | jq -c '. | map(tonumber)')
        fi
    fi
fi

# ---------- 3. Decide exit code + write gate.json ----------
INTENT_OK_BOOL="$INTENT_OK"
[[ "$INTENT_OK_BOOL" == "true" ]] && INTENT_OK_BOOL=true || INTENT_OK_BOOL=false
CONTRACT_OK_BOOL="$CONTRACT_OK"

# Exit code precedence:
#   - if intent conformance failed AND any contract mode failed → 17
#   - else if contract multi → 15
#   - else if any contract single mode → 11|12|13|14 (first one)
#   - else if intent conformance failed → 16
#   - else → 0
EXIT_CODE=0
if [[ "$INTENT_OK_BOOL" != "true" ]] && [[ "$CONTRACT_OK_BOOL" != "true" ]]; then
    EXIT_CODE=17
elif [[ "$CONTRACT_OK_BOOL" != "true" ]]; then
    if [[ $(echo "$CONTRACT_FAIL_MODES" | jq '.[0]') == "15" ]]; then
        EXIT_CODE=15
    else
        EXIT_CODE=$(echo "$CONTRACT_FAIL_MODES" | jq '.[0]')
    fi
elif [[ "$INTENT_OK_BOOL" != "true" ]]; then
    EXIT_CODE=16
fi

DECISION="PASS"
[[ $EXIT_CODE -ne 0 ]] && DECISION="FAIL"

# gate_id = sha256(canonical(struct + invariants))
if [[ -n "$INVARIANTS_FILE" ]]; then
    GATE_INPUT=$( ( jq -S -c . "$STRUCT_FILE" ; jq -S -c . "$INVARIANTS_FILE" ) | sha256sum )
else
    GATE_INPUT=$( jq -S -c . "$STRUCT_FILE" | sha256sum )
fi
GATE_ID="sha256:${GATE_INPUT%% *}"

# ---------- 4. base_diff (when --base is supplied) ----------
# Deterministic top-level field diff between current and base struct.
# Emitted as {added, removed, modified} key lists so callers can reason
# about merge candidates without re-running the diff themselves.
BASE_DIFF='null'
if [[ -n "$BASE_STRUCT" ]] && [[ -f "$BASE_STRUCT" ]]; then
    BASE_DIFF=$(jq -c --slurpfile cur "$STRUCT_FILE" --slurpfile base "$BASE_STRUCT" \
        "($cur[0] | keys) as \$ckeys |
         ($base[0] | keys) as \$bkeys |
         { added:    ( \$ckeys - \$bkeys | sort ),
           removed:  ( \$bkeys - \$ckeys | sort ),
           modified: ( \$ckeys | map(select(. as \$k | \$bkeys | index(\$k)))
                               | map(. as \$k | select((\$cur[0][\$k] | type) != (\$base[0][\$k] | type) or (\$cur[0][\$k] != \$base[0][\$k])))
                               | sort ) }" <<< "null")
fi

NOW=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

jq -n \
    --arg decision "$DECISION" \
    --argjson exit_code "$EXIT_CODE" \
    --arg gate_id "$GATE_ID" \
    --arg now "$NOW" \
    --argjson intent_ok "$INTENT_OK_BOOL" \
    --argjson intent_violations "$INTENT_VIOLATIONS" \
    --argjson contract_ok "$CONTRACT_OK_BOOL" \
    --argjson contract_fail_modes "$CONTRACT_FAIL_MODES" \
    --argjson base_diff "$BASE_DIFF" \
    --arg struct "$STRUCT_FILE" \
    --arg invariants "${INVARIANTS_FILE:-}" \
    --arg verify_results "${VERIFY_RESULTS:-}" \
    --arg base "${BASE_STRUCT:-}" \
    '
    {
      schema_version: "1.0",
      generated_at: $now,
      gate_id: $gate_id,
      decision: $decision,
      exit_code: $exit_code,
      inputs: {
        struct: $struct,
        invariants: ($invariants | if . == "" then null else . end),
        verify_results: ($verify_results | if . == "" then null else . end),
        base:    ($base        | if . == "" then null else . end)
      },
      checks: {
        intent_conformance: {
          ok: $intent_ok,
          violations: $intent_violations
        },
        contracts: {
          ok: $contract_ok,
          failed_modes: $contract_fail_modes
        }
      },
      base_diff: $base_diff
    }
' > "$OUT_FILE"

if [[ "$JSON_OUT" == "1" ]]; then
    cat "$OUT_FILE"
else
    if [[ $EXIT_CODE -eq 0 ]]; then
        vok "gate decision: PASS (exit 0)"
    else
        vfail "gate decision: FAIL (exit $EXIT_CODE)"
        jq -r '.checks | to_entries[] |
            "    [\("OK"if .value.ok else "FAIL")] \(.key): " +
            (if .value.ok then "no violations" else
                (.value | tostring | .[0:200])
            end)
        ' "$OUT_FILE" 2>/dev/null
    fi
    vsay "wrote $OUT_FILE"
fi

exit $EXIT_CODE