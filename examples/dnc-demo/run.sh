#!/opt/homebrew/bin/bash
# ============================================================================
# examples/dnc-demo/run.sh — Project Intelligence end-to-end demo (Wave 5)
#
# Runs the full orchestration chain (decompose → bound → gate → cbom) twice
# against a tiny demo fixture and asserts that the two CBOMs are bit-identical
# aside from the `generated_at` timestamp. Demonstrates the five deterministic
# guarantees of Project Intelligence:
#   1. Sound plan: every intent predicate satisfied
#   2. Per-leaf context slices: each component gets a principled-minimum
#      projection of the project
#   3. Gate verdict: intent conformance + (skipped) contract verification
#   4. Content-addressed CBOM: hashes are deterministic for fixed inputs
#   5. Reproducibility: re-running the chain produces a byte-identical CBOM
#
# Usage:
#   bash examples/dnc-demo/run.sh               # run against the demo fixture
#   bash examples/dnc-demo/run.sh --json        # final summary as JSON
#   bash examples/dnc-demo/run.sh --self-test   # run against the real repo's
#                                               # struct.json to prove the
#                                               # same code works at scale
# ============================================================================
set -euo pipefail

# ---------- locate the script + project ----------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
GENERATORS="$ROOT_DIR/generators"

# ---------- flag parsing ----------
JSON_OUT=0
SELF_TEST=0
while [[ $# -gt 0 ]]; do
    case "$1" in
        --json)      JSON_OUT=1; shift ;;
        --self-test) SELF_TEST=1; shift ;;
        -h|--help)   sed -n '2,/^# ====/p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//; s/^===.*//'; exit 0 ;;
        *) echo "[run.sh] unknown arg: $1" >&2; exit 2 ;;
    esac
done

# ---------- inputs ----------
if [[ "$SELF_TEST" == "1" ]]; then
    STRUCT_FILE="$ROOT_DIR/struct.json"
    INVARIANTS_FILE=""
    LABEL="(self-test: real repo)"
    # Real repo has no invariants file by default; the invariant predicate is
    # an empty list (still valid — no per-leaf checks).
    INVARIANTS_FILE=$(mktemp)
    echo "[]" > "$INVARIANTS_FILE"
    trap 'rm -f "$INVARIANTS_FILE"' EXIT
else
    STRUCT_FILE="$SCRIPT_DIR/struct.json"
    INVARIANTS_FILE="$SCRIPT_DIR/invariants.json"
    LABEL="(demo fixture)"
fi

# ---------- output staging ----------
# The whole chain is deterministic on its inputs, so both runs can share the
# SAME slices/ dir (re-running bound regenerates byte-identical slices). We
# keep separate plan.json + gate.json + cbom.json files per run so we can
# diff the two CBOMs side by side.
OUT_BASE="$SCRIPT_DIR/.ai"
mkdir -p "$OUT_BASE/slices"
SLICES_DIR="$OUT_BASE/slices"
rm -f "$OUT_BASE/plan.json" "$OUT_BASE/plan.runA.json" \
      "$OUT_BASE/plan.runB.json" "$OUT_BASE/gate.json" \
      "$OUT_BASE/cbom.json" "$OUT_BASE/cbom.runA.json" \
      "$OUT_BASE/cbom.runB.json"

# ---------- pretty-printing helpers ----------
bar()   { printf '%s\n' "------------------------------------------------------------"; }
big()   { printf '\n%s\n' "============================================================"; }
say()   { [[ "$JSON_OUT" == "1" ]] && return 0; printf '  %s\n' "$*"; }
ok()    { [[ "$JSON_OUT" == "1" ]] && return 0; printf '  [OK]   %s\n' "$*"; }
fail()  { printf '  [FAIL] %s\n' "$*" >&2; }

# Run one full chain against a single staging dir.
# Args: $1 = suffix ("runA" or "runB") — used to name the per-run artifacts.
#       $2 = out_dir (always OUT_A == OUT_BASE in this design, but kept
#             as an arg for clarity).
# Side effects: writes plan.json + gate.json + cbom.json with the suffix.
run_chain() {
    local suffix="$1"
    local out_dir="$2"
    local plan="$out_dir/plan.${suffix}.json"
    local gate="$out_dir/gate.${suffix}.json"
    local cbom="$out_dir/cbom.${suffix}.json"
    local slices_idx="$out_dir/slices/index.json"
    local inv_args=()
    [[ -n "${INVARIANTS_FILE:-}" && -s "$INVARIANTS_FILE" ]] && inv_args=(--invariants "$INVARIANTS_FILE")

    say "1/4 decompose → $plan"
    /opt/homebrew/bin/bash "$GENERATORS/orchestrate_decompose.sh" \
        --struct "$STRUCT_FILE" --plan-out "$plan" "${inv_args[@]}" >/dev/null

    say "2/4 bound → $SLICES_DIR/"
    /opt/homebrew/bin/bash "$GENERATORS/orchestrate_bound.sh" \
        --struct "$STRUCT_FILE" --plan "$plan" \
        --out-dir "$SLICES_DIR" "${inv_args[@]}" >/dev/null

    say "3/4 gate → $gate (no chimeric verify-results → skip contract mode)"
    /opt/homebrew/bin/bash "$GENERATORS/orchestrate_gate.sh" \
        --struct "$STRUCT_FILE" --out "$gate" "${inv_args[@]}" >/dev/null

    say "4/4 cbom → $cbom"
    /opt/homebrew/bin/bash "$GENERATORS/cbom_emit.sh" \
        --struct "$STRUCT_FILE" --plan "$plan" --slices "$slices_idx" \
        --gate "$gate" --out "$cbom" >/dev/null
}

# ---------- banner ----------
[[ "$JSON_OUT" == "1" ]] || {
    big
    printf ' %s Project Intelligence Demo  %s\n' "===" "$LABEL"
    big
    printf ' struct     : %s\n' "$STRUCT_FILE"
    [[ -n "${INVARIANTS_FILE:-}" ]] && printf ' invariants : %s\n' "$INVARIANTS_FILE"
    printf ' output     : %s\n' "$OUT_BASE"
    big
}

# ============================================================================
# Run A
# ============================================================================
[[ "$JSON_OUT" == "1" ]] || printf '\n[run A]\n'
run_chain "runA" "$OUT_BASE"

# ---------- Print plan summary ----------
PLAN_A="$OUT_BASE/plan.runA.json"
COMP_COUNT=$(jq '.stats.components' "$PLAN_A")
WAVE_COUNT=$(jq '.stats.waves' "$PLAN_A")
MAX_PAR=$(jq '.stats.parallelism_max' "$PLAN_A")
SOUND_OK=$(jq '.soundness.ok' "$PLAN_A")
SELECTIONS=$(jq -c '.resolved.selections' "$PLAN_A")
SELECTED=$(jq -r '.resolved.selected_components | join(", ")' "$PLAN_A")

if [[ "$JSON_OUT" == "1" ]]; then :; else
    bar
    printf ' plan summary\n'
    bar
    printf ' soundness         : %s\n' "$SOUND_OK"
    printf ' components        : %s\n' "$COMP_COUNT"
    printf ' waves             : %s\n' "$WAVE_COUNT"
    printf ' max parallelism   : %s\n' "$MAX_PAR"
    printf ' select_one picks  : %s\n' "$SELECTIONS"
    printf ' resolved set      : %s\n' "$SELECTED"
    bar
    printf ' waves (ascii):\n'
    while IFS= read -r row; do
        wave=$(echo "$row" | jq -r '.wave')
        comps=$(echo "$row" | jq -r '.components | join("  ")')
        printf '   wave %d  :  %s\n' "$wave" "$comps"
    done < <(jq -c '.plan[]' "$PLAN_A")
    bar
fi

# ---------- Predicate-by-predicate soundness summary ----------
if [[ "$JSON_OUT" == "1" ]]; then :; else
    printf ' predicates:\n'
    jq -r '
        .soundness.predicates | to_entries[] |
        "   [" + (if .value.ok then "OK  " else "FAIL" end) + "] " + .key +
        (if .value.ok then "" else "  -> " + ((.value.violations // []) | length | tostring) + " violation(s)" end)
    ' "$PLAN_A"
    bar
fi

# ---------- Slice sizes ----------
if [[ "$JSON_OUT" == "1" ]]; then :; else
    printf ' context slices:\n'
    for sf in "$SLICES_DIR"/*.json; do
        [[ "$(basename "$sf")" == "index.json" ]] && continue
        leaf=$(jq -r '.leaf_id' "$sf")
        size=$(wc -c < "$sf" | tr -d ' ')
        jq_len=$(jq 'length' "$sf")
        tier=$(jq -r '.tier' "$sf")
        phase=$(jq -r '.phase // "-"' "$sf")
        printf '   %-20s phase=%-12s tier=%-8s bytes=%-5s keys=%-3s\n' "$leaf" "$phase" "$tier" "$size" "$jq_len"
    done
    bar
fi

# ============================================================================
# Run B — must be byte-identical aside from `generated_at`
# ============================================================================
[[ "$JSON_OUT" == "1" ]] || printf '\n[run B] (identical inputs)\n'
run_chain "runB" "$OUT_BASE"

CBOM_A="$OUT_BASE/cbom.runA.json"
CBOM_B="$OUT_BASE/cbom.runB.json"

# Compare CBOMs sans timestamp + reproducible + gate.at (gate has its own at).
CMP_A=$(jq -S 'del(.generated_at, .reproducible) | del(.gate.generated_at // null)' "$CBOM_A" 2>/dev/null || \
        jq -S 'del(.generated_at, .reproducible)' "$CBOM_A")
CMP_B=$(jq -S 'del(.generated_at, .reproducible) | del(.gate.generated_at // null)' "$CBOM_B" 2>/dev/null || \
        jq -S 'del(.generated_at, .reproducible)' "$CBOM_B")

REPRO_OK=true
if [[ "$CMP_A" != "$CMP_B" ]]; then
    REPRO_OK=false
    [[ "$JSON_OUT" == "1" ]] || {
        fail "CBOMs differ — run.sh requires byte-identical CBOMs sans timestamps"
        diff <(echo "$CMP_A") <(echo "$CMP_B") | head -30
    }
fi

# Per-field hash comparison (the load-bearing reproducibility checks).
INTENT_A=$(jq -r '.intent_hash' "$CBOM_A")
INTENT_B=$(jq -r '.intent_hash' "$CBOM_B")
PLAN_A_HASH=$(jq -r '.plan_hash' "$CBOM_A")
PLAN_B_HASH=$(jq -r '.plan_hash' "$CBOM_B")

HASH_OK=true
[[ "$INTENT_A" != "$INTENT_B" ]] && HASH_OK=false
[[ "$PLAN_A_HASH" != "$PLAN_B_HASH" ]] && HASH_OK=false

# Per-slice hash check. We pull each cbom's slice hashes into two parallel
# lists keyed by leaf_id, then do the comparison in pure bash. This avoids
# the multi-line jq filter that bash's $() subshell handles inconsistently
# when combined with process substitution / heredoc inside a set -e script.
SLICE_HASHES_A=$(jq -c '.context_slices | map({leaf_id, slice_hash})' "$CBOM_A")
SLICE_HASHES_B=$(jq -c '.context_slices | map({leaf_id, slice_hash})' "$CBOM_B")

SLICE_HASH_OK=true
SLICE_DIFFS=""
LEAF_IDS=$(echo "$SLICE_HASHES_A" | jq -r '.[].leaf_id')
for leaf in $LEAF_IDS; do
    h_a=$(echo "$SLICE_HASHES_A" | jq -r --arg l "$leaf" '.[] | select(.leaf_id == $l) | .slice_hash')
    h_b=$(echo "$SLICE_HASHES_B" | jq -r --arg l "$leaf" '.[] | select(.leaf_id == $l) | .slice_hash // "missing"')
    if [[ "$h_a" != "$h_b" ]]; then
        SLICE_HASH_OK=false
        SLICE_DIFFS+="$leaf "
    fi
done

if [[ "$JSON_OUT" == "1" ]]; then
    # Machine-readable summary.
    jq -n \
        --arg project "$(jq -r '.project' "$CBOM_A")" \
        --argjson components "$COMP_COUNT" \
        --argjson waves "$WAVE_COUNT" \
        --argjson max_parallelism "$MAX_PAR" \
        --arg intent_hash "$INTENT_A" \
        --arg plan_hash "$PLAN_A_HASH" \
        --argjson reproducible "$REPRO_OK" \
        --argjson hash_ok "$HASH_OK" \
        --argjson soundness_ok "$SOUND_OK" \
        --argjson slices "$(jq '.context_slices | length' "$CBOM_A")" \
        --argjson slice_hash_ok "$SLICE_HASH_OK" \
        '{
            project: $project,
            components: $components,
            waves: $waves,
            max_parallelism: $max_parallelism,
            soundness_ok: $soundness_ok,
            intent_hash: $intent_hash,
            plan_hash: $plan_hash,
            slices: $slices,
            slice_hash_ok: $slice_hash_ok,
            hash_ok: $hash_ok,
            reproducible: $reproducible,
            label: "Project Intelligence: online"
        }'
else
    bar
    printf ' reproducibility (run A vs run B):\n'
    printf '   intent_hash    : %s  %s\n' "$INTENT_A" "$([[ $HASH_OK == true && $INTENT_A == $INTENT_B ]] && echo MATCH || echo DIFF)"
    printf '   plan_hash      : %s  %s\n' "$PLAN_A_HASH" "$([[ $HASH_OK == true && $PLAN_A_HASH == $PLAN_B_HASH ]] && echo MATCH || echo DIFF)"
    printf '   slice_hashes   : %s\n' "$([[ $SLICE_HASH_OK == true ]] && echo MATCH || echo "DIFF ($SLICE_DIFFS)")"
    printf '   full cbom diff : %s\n' "$([[ $REPRO_OK == true ]] && echo MATCH || echo DIFF)"
    bar
    printf '\n'
    printf '  +----------------------------------------------+\n'
    printf '  |   Project Intelligence: online               |\n'
    printf '  +----------------------------------------------+\n'
    printf '  | components      : %-26s |\n' "$COMP_COUNT"
    printf '  | waves           : %-26s |\n' "$WAVE_COUNT"
    printf '  | max parallelism : %-26s |\n' "$MAX_PAR"
    printf '  | soundness       : %-26s |\n' "$SOUND_OK"
    printf '  | cbom.intent     : %s... |\n' "${INTENT_A:7:24}"
    printf '  | cbom.plan       : %s... |\n' "${PLAN_A_HASH:7:24}"
    printf '  | reproducible    : %-26s |\n' "$REPRO_OK"
    printf '  +----------------------------------------------+\n'
    bar
fi

# ---------- exit code ----------
if [[ "$SOUND_OK" == "true" && "$REPRO_OK" == "true" && "$HASH_OK" == "true" && "$SLICE_HASH_OK" == "true" ]]; then
    exit 0
else
    exit 1
fi