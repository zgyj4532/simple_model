#!/usr/bin/env bash
# ============================================================================
# generators/intent_validate.sh — Intent-predicate validator (Wave 2)
#
# Evaluates the six intent predicates (select_one_of, optional,
# phase_membership, cross_cutting_injection, blocks, invariant) against
# either the declared state of struct.json OR a candidate plan JSON.
#
# Outputs a validation report to stdout (--json for machine-readable):
#   {
#     "ok": true|false,
#     "predicates": { "<name>": { "ok": bool, "violations": [...] } },
#     "summary": { "passed": N, "failed": M }
#   }
#
# Exit codes:
#   0  all predicates satisfied
#   1  one or more predicate violations
#   2  usage / input error (missing struct, malformed --plan, etc.)
#
# Conventions:
#   * Default behaviour: choose first option for select_one_of (matches
#     "the system picks the canonical branch" assumption); drop optional
#     components whose default_enabled is absent or false.
#   * --plan <file>    : candidate plan JSON; the validator verifies that the
#                       plan satisfies every predicate.
#   * --invariants <f> : JSON array of invariant objects (see specs/intent-model.examples.json).
#   * --selection p=c  : override the select_one_of choice (repeatable).
# ============================================================================
set -euo pipefail

# shellcheck disable=SC1091
source "$(dirname "${BASH_SOURCE[0]}")/_lib.sh"

STRUCT_FILE="${STRUCT_FILE:-./struct.json}"
PLAN_FILE=""
INVARIANTS_FILE=""
JSON_OUT=0
SELECTION_ARGS=()

usage() {
    sed -n '2,/^# ====/p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//; s/^===.*//'
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        -s|--struct)         STRUCT_FILE="$2"; shift 2 ;;
        -p|--plan)           PLAN_FILE="$2"; shift 2 ;;
        --invariants)        INVARIANTS_FILE="$2"; shift 2 ;;
        --selection)         SELECTION_ARGS+=("$2"); shift 2 ;;
        --json)              JSON_OUT=1; shift ;;
        -h|--help)           usage; exit 0 ;;
        *) echo "[intent_validate] unknown arg: $1" >&2; exit 2 ;;
    esac
done

[[ -f "$STRUCT_FILE" ]] || { echo "[FAIL] struct.json not found: $STRUCT_FILE" >&2; exit 2; }

isatty=0
[[ -t 1 ]] && isatty=1

vsay()  { [[ "$JSON_OUT" == "1" ]] && return 0; printf '  %s\n' "$*"; }
vok()   { [[ "$JSON_OUT" == "1" ]] && return 0; printf '  [OK]   %s\n' "$*"; }
vfail() { printf '  [FAIL] %s\n' "$*" >&2; }

# ---------- Build candidate resolved selection (or read --plan) ----------
TMP=$(mktemp)
trap 'rm -f "$TMP"' EXIT

if [[ -n "$PLAN_FILE" ]]; then
    [[ -f "$PLAN_FILE" ]] || { echo "[FAIL] --plan not found: $PLAN_FILE" >&2; exit 2; }
    jq -c '.resolved.selected_components // []' "$PLAN_FILE" > "$TMP.selected"
    jq -c '.resolved.selections // {}'      "$PLAN_FILE" > "$TMP.selections"
else
    # Default rules:
    #   - keep only components that are scheduled by some phase or enabled cross_cutting
    #     (i.e. appear in core_components/optional_components/select_one_of/select_subset_of,
    #      or in a cross_cutting.components whose default_enabled != false).
    #   - optional components require default_enabled=true to be included.
    #   - select_one_of: pick first option.
    jq -c '
        . as $root |
        # core_components + select_subset_of are statically included.
        ([ ($root.phases // []) | .[] |
            ((.core_components // []) + (.select_subset_of // [])) ] | flatten | unique) as $phase_static |
        # select_one_of defaults: pick first option from each select_one phase.
        ([ ($root.phases // []) | .[] |
            select(.mode == "select_one") |
            { ( .phase ): (.select_one_of[0] // null) }
        ] | add // {}) as $default_selections |
        # enabled cross-cutting components (default_enabled != false)
        ([ ($root.cross_cutting // []) | .[] |
            select((.default_enabled // true) == true) |
            .components[] ] | unique) as $xcut_enabled |
        # selected_components: core_components + select_subset_of + (optionally enabled) cross_cutting.
        # NOTE: optional_components and select_one_of are NOT included by default
        # (the user must enable them). For select_one_of, only the chosen branch is added.
        ([ ($root.modules // []) | .[] | (.components // []) | .[] |
            .name as $n |
            select(
              ((($phase_static + $xcut_enabled) | unique | index($n)) != null) and
              ( (($phase_static | index($n)) != null and (.optional // false) == false) or
                ((($xcut_enabled | index($n)) != null) and (.optional // false) == false) )
            ) | $n ] | unique
        ) as $base_selected |
        # select_one branch additions: include the chosen option for each select_one phase.
        ([ $root.phases[] | select(.mode == "select_one") |
           .phase as $pname |
           (.select_one_of // [])[] |
           select(. == ($default_selections[$pname] // null))
        ]) as $select_one_picks |
        {
          selected_components: (($base_selected + $select_one_picks) | unique),
          selections: $default_selections
        }
    ' "$STRUCT_FILE" > "$TMP.resolved"

    jq -c '.selected_components' "$TMP.resolved" > "$TMP.selected"
    jq -c '.selections'           "$TMP.resolved" > "$TMP.selections"
fi

# Apply --selection overrides (phase=component)
if [[ ${#SELECTION_ARGS[@]} -gt 0 ]]; then
    JQ_OVERRIDES=""
    for kv in "${SELECTION_ARGS[@]}"; do
        phase="${kv%%=*}"; comp="${kv#*=}"
        JQ_OVERRIDES+=" | .[$phase] = \"$comp\""
    done
    jq -c ". ${JQ_OVERRIDES}" "$TMP.selections" > "$TMP.selections.tmp"
    mv "$TMP.selections.tmp" "$TMP.selections"
fi

SELECTED_JSON=$(cat "$TMP.selected")
SELECTIONS_JSON=$(cat "$TMP.selections")

# ---------- Evaluate each predicate ----------
violations_select_one="[]"
violations_optional="[]"
violations_phase="[]"
violations_xcut="[]"
violations_blocks="[]"
violations_invariant="[]"

# ---- 1. select_one_of ----
# For each phase with mode=select_one, check: |resolved.selected ∩ S| == 1,
# and that the resolved.selection[phase] is in S.
SEL_CHECK=$(jq -c --argjson sel "$SELECTED_JSON" --argjson sels "$SELECTIONS_JSON" '
    [ (.phases // []) | .[] | select(.mode == "select_one") |
      {
        phase: .phase,
        S: (.select_one_of // []),
        pick: ($sels[.phase] // null),
        in_resolved: ((.select_one_of // []) | map(select(. as $n | $sel | index($n))))
      }
    ] | map(
        if (.pick == null) then
            { ok: false, violation: "no selection made for select_one phase \(.phase)" }
        elif ((.pick as $p | (.S | index($p))) == null) then
            { ok: false, violation: "phase \(.phase): selection \(.pick) is not in select_one_of=\(.S)" }
        elif ((.in_resolved | length) != 1) then
            { ok: false, violation: "phase \(.phase): |resolved ∩ S| = \(.in_resolved | length), want 1 (members=\(.in_resolved))" }
        else
            { ok: true }
        end
    )
' "$STRUCT_FILE")
violations_select_one=$(echo "$SEL_CHECK" | jq -c '[ .[] | select(.ok == false) | {predicate:"select_one_of", location:.phase, message:.violation} ]')

# ---- 2. optional ----
# Each component with optional=true and no default_enabled=true is NOT in resolved.selected.
# Each component with optional=true and default_enabled=true IS in resolved.selected.
OPT_CHECK=$(jq -c --argjson sel "$SELECTED_JSON" '
    [ (.modules // []) | .[] | (.components // []) | .[] |
      select((.optional // false) == true) |
      { name: .name, enabled: ((.default_enabled // false) == true),
        in_resolved: ((.name as $n | $sel | index($n)) != null) }
    ] | map(
        if (.enabled == true and .in_resolved == false) then
            { ok: false, violation: "optional component \(.name) is default_enabled but missing from resolved set" }
        elif (.enabled == false and .in_resolved == true) then
            { ok: false, violation: "optional component \(.name) is not enabled but present in resolved set" }
        else
            { ok: true }
        end
    )
' "$STRUCT_FILE")
violations_optional=$(echo "$OPT_CHECK" | jq -c '[ .[] | select(.ok == false) | {predicate:"optional", location:.name, message:.violation} ]')

# ---- 3. cross_cutting injection ----
# Each cross_cutting.injects_into must be a subset of {phases[].phase}.
XCHECK=$(jq -c '
    ( [ (.phases // []) | .[] | .phase ] ) as $declared_phases |
    [ (.cross_cutting // []) | .[] |
      { name: .name, injects_into: (.injects_into // []) }
    ] | map(
        . as $x |
        ($x.injects_into | map(select(. as $p | $declared_phases | index($p) | not))) as $bad |
        if ($bad | length) > 0 then
            { ok: false, violation: "cross_cutting \($x.name).injects_into references undeclared phases: \($bad)" }
        else
            { ok: true }
        end
    )
' "$STRUCT_FILE")
violations_xcut=$(echo "$XCHECK" | jq -c '[ .[] | select(.ok == false) | {predicate:"cross_cutting_injection", location:.name, message:.violation} ]')

# ---- 4. phase_membership ----
# Every resolved component must appear in some phase's component set
# OR be in a cross_cutting whose injects_into intersects active phases.
PHASE_CHECK=$(jq -c --argjson sel "$SELECTED_JSON" '
    . as $root |
    ( [ ($root.phases // []) | .[] |
        (.core_components // []) + (.optional_components // []) +
        (.select_one_of // []) + (.select_subset_of // []) ] | flatten | unique ) as $phase_components |
    ( [ ($root.cross_cutting // []) | .[] |
        select((.default_enabled // true) == true) |
        .components[] ] | unique ) as $xcut_components |
    [ $sel[] | . as $c |
        {
          name: $c,
          in_phase: (($phase_components | index($c)) != null),
          in_xcut:  (($xcut_components | index($c)) != null)
        }
    ] | map(
        if (.in_phase or .in_xcut) then { ok: true }
        else { ok: false, violation: "resolved component \(.name) does not appear in any phase or enabled cross_cutting" }
        end
    )
' "$STRUCT_FILE")
violations_phase=$(echo "$PHASE_CHECK" | jq -c '[ .[] | select(.ok == false) | {predicate:"phase_membership", location:.name, message:.violation} ]')

# ---- 5. blocks ----
# Only meaningful if the struct has todos. We read waves from the dev_queue.json
# in OUTPUT_DIR if present; otherwise skip.
WAVES_JSON="{}"
DQ="${OUTPUT_DIR:-./generated}/.ai/dev_queue.json"
if [[ -f "$DQ" ]]; then
    WAVES_JSON=$(jq -c '
        [ (.waves // []) | .[] | . as $w | (.todos // []) | map({ (.:id // .id // "?"): $w.wave }) ] | add // {}
    ' "$DQ" 2>/dev/null || echo "{}")
fi
# Also check struct-defined todos directly if no dev_queue.
INTERNAL_BLOCKS_CHECK=$(jq -c --argjson waves "$WAVES_JSON" '
    [ (.modules // []) | .[] | (.components // []) | .[] | (.todos // []) | .[] |
      { id: .id, blocks: (.blocks // []) }
    ] as $todos |
    (if ($todos | length) == 0 then []
     else
        [ $todos[] | . as $t |
          (.blocks // []) as $bs |
          ($bs | map(. as $b | {b: $b, w_b: ($waves[$b] // null), w_t: ($waves[$t.id] // null)})) as $bw |
          ($bw | map(select(.w_b != null and .w_t != null and .w_t <= .w_b))) as $bad |
          if ($bad | length) > 0 then
            { ok: false, violation: "todo \($t.id) violates blocks: \($bad)" }
          else
            { ok: true }
          end
        ]
     end)
' "$STRUCT_FILE")
violations_blocks=$(echo "$INTERNAL_BLOCKS_CHECK" | jq -c '[ .[] | select(.ok == false) | {predicate:"blocks", location:.id, message:.violation} ]')

# ---- 6. invariant (custom user-defined predicates over resolved set) ----
if [[ -n "$INVARIANTS_FILE" ]] && [[ -f "$INVARIANTS_FILE" ]]; then
    # Materialise the resolved component set as JSON objects (for jq predicate eval).
    jq -c --argjson sel "$SELECTED_JSON" '
        [ (.modules // []) | .[] | (.components // []) | .[] |
          select((.name as $n | $sel | index($n)) != null) ]
    ' "$STRUCT_FILE" > "$TMP.resolved_components"

    # Build per-phase buckets.
    jq -c --argjson sel "$SELECTED_JSON" '
        . as $root |
        [ ($root.phases // []) | .[] |
            . as $p |
            { phase: $p.phase,
              components: (
                [ (($p.core_components // []) + ($p.optional_components // []) +
                   ($p.select_one_of // []) + ($p.select_subset_of // [])) | unique[] as $c |
                  ([ $root.modules[] | .components[] | select(.name == $c)] | first) ]
              )
            }
        ]
    ' "$STRUCT_FILE" > "$TMP.phase_buckets"

    violations_invariant="[]"
    while IFS= read -r inv; do
        inv_name=$(echo "$inv" | jq -r '.name')
        inv_scope=$(echo "$inv" | jq -r '.scope')
        inv_quant=$(echo "$inv" | jq -r '.quantifier // "forall"')
        inv_pred=$(echo "$inv" | jq -r '.predicate')
        inv_msg=$(echo "$inv" | jq -r '.message // ""')

        case "$inv_scope" in
            all_components)
                ELEMENTS=$(cat "$TMP.resolved_components")
                ;;
            components_in_phase:*)
                pname="${inv_scope#components_in_phase:}"
                ELEMENTS=$(jq -c --arg p "$pname" '.[] | select(.phase == $p) | .components' "$TMP.phase_buckets")
                ;;
            *)
                ELEMENTS="[]"
                ;;
        esac

        # Evaluate predicate against each element; aggregate by quantifier.
        # For each element, jq -e '<pred>' returns 0 if predicate true.
        pass=true
        first_bad_name=""
        count=0
        if [[ "$inv_quant" == "forall" ]]; then
            # All elements must satisfy.
            while IFS= read -r elem; do
                [[ -z "$elem" ]] && continue
                count=$((count+1))
                if ! echo "$elem" | jq -e "$inv_pred" >/dev/null 2>&1; then
                    pass=false
                    first_bad_name=$(echo "$elem" | jq -r '.name // "??"')
                    break
                fi
            done < <(echo "$ELEMENTS" | jq -c '.[]')
        else
            # At least one must satisfy.
            found=false
            while IFS= read -r elem; do
                [[ -z "$elem" ]] && continue
                count=$((count+1))
                if echo "$elem" | jq -e "$inv_pred" >/dev/null 2>&1; then
                    found=true
                    break
                fi
            done < <(echo "$ELEMENTS" | jq -c '.[]')
            if [[ "$found" != "true" ]] && [[ $count -gt 0 ]]; then pass=false; fi
        fi

        if [[ "$pass" != "true" ]]; then
            violations_invariant=$(echo "$violations_invariant" | jq -c \
                --arg name "$inv_name" \
                --arg msg "${inv_msg:-invariant $inv_name failed}" \
                --arg locname "${inv_name}@${first_bad_name:-scope=$inv_scope}" \
                '. + [{predicate:"invariant", location:$locname, message:$msg}]')
        fi
    done < <(jq -c '.[]' "$INVARIANTS_FILE")
fi

# ---------- Aggregate ----------
total_violations=$(jq -n --argjson a "$violations_select_one" --argjson b "$violations_optional" \
                            --argjson c "$violations_phase" --argjson d "$violations_xcut" \
                            --argjson e "$violations_blocks" --argjson f "$violations_invariant" \
                            '($a + $b + $c + $d + $e + $f) | length')
passed=$((6 - $(jq -n --argjson a "$violations_select_one" --argjson b "$violations_optional" \
                              --argjson c "$violations_phase" --argjson d "$violations_xcut" \
                              --argjson e "$violations_blocks" --argjson f "$violations_invariant" \
                              '[($a + $b + $c + $d + $e + $f) | length] | (.[0] > 0 | if . then 0 else 6 end) - 0')))

# Simpler: count predicates with zero violations.
count_passing() {
    local v="$1"
    if [[ "$(echo "$v" | jq 'length')" == "0" ]]; then echo 1; else echo 0; fi
}
p=$(($(count_passing "$violations_select_one") + $(count_passing "$violations_optional") + \
     $(count_passing "$violations_phase") + $(count_passing "$violations_xcut") + \
     $(count_passing "$violations_blocks") + $(count_passing "$violations_invariant")))
f=$((6 - p))

OK_FLAG=true
[[ $f -gt 0 ]] && OK_FLAG=false

REPORT=$(jq -n \
    --argjson ok "$OK_FLAG" \
    --argjson sel_one "$violations_select_one" \
    --argjson opt "$violations_optional" \
    --argjson phs "$violations_phase" \
    --argjson xc "$violations_xcut" \
    --argjson blk "$violations_blocks" \
    --argjson inv "$violations_invariant" \
    --argjson p "$p" --argjson f "$f" '
    {
        ok: $ok,
        predicates: {
            select_one_of:          { ok: ($sel_one | length == 0), violations: $sel_one },
            optional:               { ok: ($opt   | length == 0), violations: $opt },
            phase_membership:       { ok: ($phs   | length == 0), violations: $phs },
            cross_cutting_injection:{ ok: ($xc    | length == 0), violations: $xc },
            blocks:                 { ok: ($blk   | length == 0), violations: $blk },
            invariant:              { ok: ($inv   | length == 0), violations: $inv }
        },
        summary: { predicates_passed: $p, predicates_failed: $f, total_violations: ($sel_one + $opt + $phs + $xc + $blk + $inv | length) }
    }
')

if [[ "$JSON_OUT" == "1" ]]; then
    echo "$REPORT" | jq .
else
    echo "$REPORT" | jq -r '
        "intent validation: " + (if .ok then "PASS" else "FAIL" end) + "  (" + (.summary.predicates_passed|tostring) + "/6 predicates, " + (.summary.total_violations|tostring) + " violations)",
        (.predicates | to_entries[] |
            "  [" + (if .value.ok then "OK  " else "FAIL" end) + "] " + .key +
            (if .value.ok then "" else "  -> " + (.value.violations | length|tostring) + " violation(s)" end)
        )
    '
fi

if [[ "$OK_FLAG" == "true" ]]; then
    exit 0
else
    exit 1
fi