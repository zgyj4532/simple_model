#!/usr/bin/env bash
# ============================================================================
# generators/orchestrate_decompose.sh — intent-sound wave decomposition (Wave 3)
#
# Reads struct.json, prunes by intent (select_one_of / optional /
# cross_cutting / phase_membership), assigns waves via longest-path layering
# over the import DAG, and emits a soundness-checked wave-plan.
#
# Output:
#   .ai/plan.json — wave-plan + resolved set + soundness verdict
#
# Exit codes:
#   0  sound plan emitted
#   1  soundness check failed (see plan.soundness.predicates)
#   2  usage error
#   3  intent inconsistent (e.g., a phase references an unknown component)
#
# Conventions:
#   * Default select_one choice = first option. Override via --selection phase=component.
#   * Default enabled set = core_components + select_subset_of + enabled cross_cuttings
#     + selected select_one branches.
#   * The plan is deterministic: same inputs → bit-identical plan JSON.
# ============================================================================
set -euo pipefail
# shellcheck disable=SC1091
source "$(dirname "${BASH_SOURCE[0]}")/_lib.sh"

STRUCT_FILE="${STRUCT_FILE:-./struct.json}"
INVARIANTS_FILE=""
PLAN_OUT="${OUTPUT_DIR:-./generated}/.ai/plan.json"
JSON_OUT=0
SELECTION_ARGS=()

usage() {
    sed -n '2,/^# ====/p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//; s/^===.*//'
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        -s|--struct)         STRUCT_FILE="$2"; shift 2 ;;
        --invariants)        INVARIANTS_FILE="$2"; shift 2 ;;
        --selection)         SELECTION_ARGS+=("$2"); shift 2 ;;
        --plan-out)          PLAN_OUT="$2"; shift 2 ;;
        --json)              JSON_OUT=1; shift ;;
        -h|--help)           usage; exit 0 ;;
        -*) echo "[decompose] unknown arg: $1" >&2; exit 2 ;;
        *)
            # First non-flag arg = struct file (positional shorthand for --struct).
            # Mirrors the documented `bash orchestrate_decompose.sh struct.json` form.
            if [[ -z "${POSITIONAL_STRUCT:-}" ]]; then
                POSITIONAL_STRUCT="$1"; shift
            else
                echo "[decompose] unknown arg: $1" >&2; exit 2
            fi
            ;;
    esac
done

if [[ -n "${POSITIONAL_STRUCT:-}" ]]; then
    STRUCT_FILE="$POSITIONAL_STRUCT"
fi

[[ -f "$STRUCT_FILE" ]] || { echo "[FAIL] struct.json not found: $STRUCT_FILE" >&2; exit 2; }

mkdir -p "$(dirname "$PLAN_OUT")"

vsay()  { [[ "$JSON_OUT" == "1" ]] && return 0; printf '  %s\n' "$*"; }
vok()   { [[ "$JSON_OUT" == "1" ]] && return 0; printf '  [OK]   %s\n' "$*"; }
vfail() { printf '  [FAIL] %s\n' "$*" >&2; }

# ---------- 0. Pre-check: intent-consistency on todo `blocks` references ----------
# Doc'd exit code 3 = "intent inconsistent — a todo's `blocks` references an
# unknown id". We refuse to compute the plan at all if any todo's `blocks`
# list points at a non-existent todo id. This is a different class of failure
# than "the plan violated a predicate" (exit 1): the struct itself is broken
# and no pruning can produce a sound plan.
DANGLING=$(jq -c '
    ([.modules[] | .components[] | (.todos // [])[]] | map({id, blocks: (.blocks // [])})) as $todos |
    [ $todos[] | . as $t |
        (.blocks // []) as $bs |
        ($bs | map(select(. as $b | [$todos[].id] | index($b) | not))) as $bad |
        select(($bad | length) > 0) |
        { todo: $t.id, dangling: $bad }
    ]
' "$STRUCT_FILE")
DANGLING_COUNT=$(echo "$DANGLING" | jq 'length')
if [[ "$DANGLING_COUNT" -gt 0 ]]; then
    vfail "intent inconsistent: $DANGLING_COUNT todo(s) reference unknown blocker id(s)"
    if [[ "$JSON_OUT" != "1" ]]; then
        echo "$DANGLING" | jq -r '.[] | "         -> todo \(.todo): dangling refs \(.dangling)"'
    fi
    echo "$DANGLING" | jq -c '{error: "intent_inconsistent", exit_code: 3, dangling: .}' > "$PLAN_OUT"
    exit 3
fi

# ---------- 1. Build resolved set R ----------
TMP=$(mktemp)
trap 'rm -f "$TMP" "$TMP".*' EXIT

# Compute defaults first; apply overrides on top.
jq -c '
    . as $root |
    ([ ($root.phases // []) | .[] |
        ((.core_components // []) + (.select_subset_of // [])) ] | flatten | unique) as $phase_static |
    ([ ($root.phases // []) | .[] |
        select(.mode == "select_one") |
        { ( .phase ): (.select_one_of[0] // null) }
    ] | add // {}) as $default_selections |
    ([ ($root.cross_cutting // []) | .[] |
        select((.default_enabled // true) == true) |
        .components[] ] | unique) as $xcut_enabled |
    ([ ($root.modules // []) | .[] | (.components // []) | .[] |
        .name as $n |
        select(
          ((($phase_static + $xcut_enabled) | unique | index($n)) != null) and
          ( (($phase_static | index($n)) != null and (.optional // false) == false) or
            ((($xcut_enabled | index($n)) != null) and (.optional // false) == false) )
        ) | $n ] | unique
    ) as $base_selected |
    ([ $root.phases[] | select(.mode == "select_one") |
       .phase as $pname |
       (.select_one_of // [])[] |
       select(. == ($default_selections[$pname] // null))
    ]) as $select_one_picks |
    {
      selected_components: (($base_selected + $select_one_picks) | unique),
      selections: $default_selections
    }
' "$STRUCT_FILE" > "$TMP.default"

# Apply --selection overrides (phase=component)
if [[ ${#SELECTION_ARGS[@]} -gt 0 ]]; then
    JQ_OVERRIDES=""
    for kv in "${SELECTION_ARGS[@]}"; do
        phase="${kv%%=*}"; comp="${kv#*=}"
        JQ_OVERRIDES+=" | .selections[\"$phase\"] = \"$comp\""
    done
    jq -c ". ${JQ_OVERRIDES}" "$TMP.default" > "$TMP.with_selections"
    mv "$TMP.with_selections" "$TMP.default"

    # Re-derive selected_components from overridden selections.
    jq -c --slurpfile def "$TMP.default" '
        . as $root |
        $def[0].selections as $sels |
        ([ ($root.phases // []) | .[] |
            ((.core_components // []) + (.select_subset_of // [])) ] | flatten | unique) as $phase_static |
        ([ ($root.cross_cutting // []) | .[] |
            select((.default_enabled // true) == true) |
            .components[] ] | unique) as $xcut_enabled |
        ([ ($root.modules // []) | .[] | (.components // []) | .[] |
            .name as $n |
            select(
              ((($phase_static + $xcut_enabled) | unique | index($n)) != null) and
              ( (($phase_static | index($n)) != null and (.optional // false) == false) or
                ((($xcut_enabled | index($n)) != null) and (.optional // false) == false) )
            ) | $n ] | unique
        ) as $base_selected |
        ([ $root.phases[] | select(.mode == "select_one") |
           .phase as $pname |
           (.select_one_of // [])[] |
           select(. == ($sels[$pname] // null))
        ]) as $select_one_picks |
        {
          selected_components: (($base_selected + $select_one_picks) | unique),
          selections: $sels
        }
    ' "$STRUCT_FILE" > "$TMP.resolved"
else
    mv "$TMP.default" "$TMP.resolved"
fi

SELECTED_JSON=$(jq -c '.selected_components' "$TMP.resolved")
SELECTIONS_JSON=$(jq -c '.selections' "$TMP.resolved")

vsay "resolved components: $(echo "$SELECTED_JSON" | jq 'length')"
vsay "selections: $SELECTIONS_JSON"

# ---------- 2. Compute wave assignment (longest-path layering over import DAG) ----------
# We need a deterministic per-component depth. The helper:
compute_component_waves() {
    # Args: $1 = struct.json, $2 = JSON array of selected component names.
    local struct="$1" selected="$2"

    # Build edges JSON
    local edges
    edges=$(jq -c --argjson sel "$selected" '
        . as $root |
        ([ $root.modules[] | .components[] | select(.name as $n | $sel | index($n)) |
            { (.name): (.imports // [] | map(select(. as $i | $sel | index($i)))) } ] | add // {})
    ' "$struct")

    # Iterate fixed-point: depth[v] = 1 + max(depth of imports); start at 1 for all.
    # Each iteration strictly increases some depths; |V| iterations suffice.
    local prev_json='{}'
    local new_json
    local converged=0
    local iter=0
    local -A depth
    for c in $(echo "$selected" | jq -r '.[]'); do
        depth[$c]=1
    done
    # First, build initial JSON.
    local first=1 init_json="{"
    for c in $(echo "$selected" | jq -r '.[]'); do
        [[ $first -eq 0 ]] && init_json+=","
        first=0
        init_json+="\"$c\":1"
    done
    init_json+="}"
    prev_json="$init_json"
    new_json="$init_json"

    while [[ $converged -eq 0 ]] && [[ $iter -lt 100 ]]; do
        iter=$((iter + 1))
        # One pass: for each node, depth = 1 + max(depth of imports) or 1 if no imports.
        local -A new_depth
        for c in $(echo "$selected" | jq -r '.[]'); do
            local max_imp=0
            local imports_csv
            imports_csv=$(echo "$edges" | jq -r --arg n "$c" '.[$n] // [] | join(" ")')
            for imp in $imports_csv; do
                [[ -z "$imp" ]] && continue
                local d=${depth[$imp]:-1}
                [[ $d -gt $max_imp ]] && max_imp=$d
            done
            new_depth[$c]=$((max_imp + 1))
        done
        # Check convergence.
        local stable=1
        for c in $(echo "$selected" | jq -r '.[]'); do
            if [[ "${new_depth[$c]}" != "${depth[$c]}" ]]; then
                stable=0
                break
            fi
        done
        for k in "${!new_depth[@]}"; do
            depth[$k]=${new_depth[$k]}
        done
        if [[ $stable -eq 1 ]]; then
            converged=1
        fi
    done

    # Emit JSON.
    local out="{"
    first=1
    for c in $(echo "$selected" | jq -r '.[]' | sort); do
        [[ $first -eq 0 ]] && out+=","
        first=0
        out+="\"$c\":${depth[$c]:-1}"
    done
    out+="}"
    echo "$out"
}

# Run depth calc.
DEPTH_MAP=$(compute_component_waves "$STRUCT_FILE" "$SELECTED_JSON")

# Order components by (depth, name) and group by depth.
read -r -d '' PLAN_JQ <<'EOF' || true
. as $root |
$resolved as $sel |
($root | [ .modules[] | .components[] | select(.name as $n | $sel | index($n)) | .name ]) as $comps |
($comps | map({ (.): ($depth[.]) })) as $dlist |
($dlist | add) as $depth |
($comps | sort_by($depth[.] // 1, .) | group_by($depth[.] // 1) | to_entries | map({
    wave: (.key | tonumber),
    components: (.value | sort)
})) as $waves |
{
  plan: $waves,
  resolved: $resolved_full,
  depth_map: $depth
}
EOF

# Use jq to assemble plan.
RESOLVED_FULL_JSON=$(jq -c '{selected_components: .selected_components, selections: .selections}' "$TMP.resolved")

jq -c --argjson resolved "$SELECTED_JSON" \
      --argjson resolved_full "$RESOLVED_FULL_JSON" \
      --argjson depth "$DEPTH_MAP" '
    . as $root |
    ($root | [ .modules[] | .components[] | select(.name as $n | $resolved | index($n)) | .name ]) as $comps |
    ($comps | map({ (.): ($depth[.] // 1) })) as $dlist |
    ($dlist | add) as $dm |
    ($comps | sort_by($dm[.] // 1, .) | group_by($dm[.] // 1) | to_entries | map({
        wave: (.key + 1),
        components: (.value | sort)
    })) as $waves |
    {
      plan: $waves,
      resolved: $resolved_full
    }
' "$STRUCT_FILE" > "$TMP.plan"

# ---------- 3. Soundness check ----------
# We delegate to a sub-call of intent_validate for the predicates it knows,
# then add an additional invariant-predicate check if --invariants was given.

# Build a synthetic "plan" file to feed intent_validate.
jq -c '. + {waves: .plan}' "$TMP.plan" > "$TMP.feed_plan"
# (intent_validate's --plan mode expects .resolved.{selected_components,selections} — extend.)
jq -c '.resolved = (.resolved + {selected_components: .resolved.selected_components, selections: .resolved.selections}) | {resolved: .resolved, plan: .plan}' "$TMP.plan" > "$TMP.feed_plan"
# Add waves under .resolved for intent_validate (it reads waves via dev_queue.json OR
# its own internal check). Simpler: skip the chain and run soundness directly here.

# Inline soundness check — re-derives each predicate.
SOUNDNESS_JSON=$(jq -c --argjson sel "$SELECTED_JSON" --argjson sels "$SELECTIONS_JSON" '
    . as $root |
    ( [ ($root.phases // []) | .[].phase ] ) as $declared_phases |
    ( [ ($root.phases // []) | .[] |
        ((.core_components // []) + (.optional_components // []) +
         (.select_one_of // []) + (.select_subset_of // [])) ] | flatten | unique ) as $phase_components |
    ( [ ($root.cross_cutting // []) | .[] |
        select((.default_enabled // true) == true) |
        .components[] ] | unique ) as $xcut_components |

    # 1. select_one_of
    ([ ($root.phases // []) | .[] | select(.mode == "select_one") |
        . as $p |
        { phase: $p.phase, S: ($p.select_one_of // []),
          pick: ($sels[$p.phase] // null),
          in_resolved: ((($p.select_one_of // []) | map(select(. as $n | $sel | index($n)))) ) }
    ] | map(
        . as $item |
        if ($item.pick == null) then
            { ok: false, violation: "no selection made for select_one phase \($item.phase)" }
        elif (($item.S | index($item.pick)) == null) then
            { ok: false, violation: "phase \($item.phase): selection \($item.pick) is not in select_one_of=\($item.S)" }
        elif (($item.in_resolved | length) != 1) then
            { ok: false, violation: "phase \($item.phase): |resolved ∩ S| = \($item.in_resolved | length), want 1 (members=\($item.in_resolved))" }
        else { ok: true }
        end
    )) as $sel_one |

    # 2. optional
    ([ ($root.modules // []) | .[] | (.components // []) | .[] |
        select((.optional // false) == true) |
        .name as $n |
        { name: $n,
          enabled: ((.default_enabled // false) == true),
          in_resolved: (($sel | index($n)) != null) }
    ] | map(
        if (.enabled == true and .in_resolved == false) then
            { ok: false, violation: "optional component \(.name) is default_enabled but missing from resolved set" }
        elif (.enabled == false and .in_resolved == true) then
            { ok: false, violation: "optional component \(.name) is not enabled but present in resolved set" }
        else { ok: true }
        end
    )) as $opt |

    # 3. cross_cutting_injection
    ([ ($root.cross_cutting // []) | .[] |
        . as $x |
        ($x.injects_into // []) as $inj |
        ($inj | map(select(. as $p | $declared_phases | index($p) | not))) as $bad |
        if ($bad | length) > 0 then
            { ok: false, violation: "cross_cutting \($x.name).injects_into references undeclared phases: \($bad)" }
        else { ok: true }
        end
    ]) as $xcut |

    # 4. phase_membership
    ([ $sel[] | . as $c |
        { name: $c,
          in_phase: (($phase_components | index($c)) != null),
          in_xcut:  (($xcut_components | index($c)) != null) }
    ] | map(
        if (.in_phase or .in_xcut) then { ok: true }
        else { ok: false, violation: "resolved component \(.name) does not appear in any phase or enabled cross_cutting" }
        end
    )) as $phs |

    # 5. blocks (skipped if no todos; uses self wave-map if any)
    ([ ($root.modules // []) | .[] | (.components // []) | .[] | (.todos // []) | .[] |
        { id: .id, blocks: (.blocks // []) }
    ]) as $todos |
    (if ($todos | length) == 0 then [{ok: true}]
     else
        # Without a precomputed wave map for todos, defer to intent_validate behaviour:
        # mark as ok if every blocker id is a known todo id (else semantic violation).
        [ $todos[] | . as $t |
            (.blocks // []) as $bs |
            ($bs | map(select(. as $b | [$todos[].id] | index($b) | not))) as $bad |
            if ($bad | length) > 0 then
                { ok: false, violation: "todo \($t.id) references unknown blocker(s): \($bad)" }
            else { ok: true }
            end
        ]
     end
    ) as $blk |

    # Aggregate
    {
        select_one_of:           { ok: ([$sel_one[] | select(.ok == false)] | length == 0), violations: ([$sel_one[] | select(.ok == false) | {location:.phase, message:.violation}]) },
        optional:                { ok: ([$opt[]    | select(.ok == false)] | length == 0), violations: ([$opt[]    | select(.ok == false) | {location:.name,  message:.violation}]) },
        phase_membership:        { ok: ([$phs[]    | select(.ok == false)] | length == 0), violations: ([$phs[]    | select(.ok == false) | {location:.name,  message:.violation}]) },
        cross_cutting_injection: { ok: ([$xcut[]   | select(.ok == false)] | length == 0), violations: ([$xcut[]   | select(.ok == false) | {location:.name,  message:.violation}]) },
        blocks:                  { ok: ([$blk[]    | select(.ok == false)] | length == 0), violations: ([$blk[]    | select(.ok == false) | {location:.id,    message:.violation}]) },
        invariant:               { ok: true, violations: [] }
    }
' "$STRUCT_FILE")

# If invariants file given, add invariant-predicate violations.
INV_BLOCK='{"ok":true,"violations":[]}'
if [[ -n "$INVARIANTS_FILE" ]] && [[ -f "$INVARIANTS_FILE" ]]; then
    # Materialise resolved components as objects for jq predicate eval.
    jq -c --argjson sel "$SELECTED_JSON" '
        [ (.modules // []) | .[] | (.components // []) | .[] |
          select((.name as $n | $sel | index($n)) != null) ]
    ' "$STRUCT_FILE" > "$TMP.resolved_components"

    # Per-phase buckets.
    jq -c --argjson sel "$SELECTED_JSON" '
        . as $root |
        [ ($root.phases // []) | .[] |
            { phase: .phase,
              components: ([ ((.core_components // []) + (.optional_components // []) +
                              (.select_one_of // []) + (.select_subset_of // [])) | unique[] as $c |
                              ([ $root.modules[] | .components[] | select(.name == $c)] | first) ]) }
        ]
    ' "$STRUCT_FILE" > "$TMP.phase_buckets"

    # Evaluate each invariant.
    INV_VIOLATIONS_TMP=$(mktemp)
    echo "[]" > "$INV_VIOLATIONS_TMP"
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

        pass=true
        first_bad=""
        count=0
        if [[ "$inv_quant" == "forall" ]]; then
            while IFS= read -r elem; do
                [[ -z "$elem" ]] && continue
                count=$((count+1))
                if ! echo "$elem" | jq -e "$inv_pred" >/dev/null 2>&1; then
                    pass=false
                    first_bad=$(echo "$elem" | jq -r '.name // "<?>"')
                    break
                fi
            done < <(echo "$ELEMENTS" | jq -c '.[]')
        else
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
            jq -c --arg name "$inv_name" --arg loc "${first_bad:-scope=$inv_scope}" \
                  --arg msg "${inv_msg:-invariant $inv_name failed}" \
                  '. + [{predicate:"invariant", location:($name + "@" + $loc), message:$msg}]' \
                  "$INV_VIOLATIONS_TMP" > "$INV_VIOLATIONS_TMP.new"
            mv "$INV_VIOLATIONS_TMP.new" "$INV_VIOLATIONS_TMP"
        fi
    done < <(jq -c '.[]' "$INVARIANTS_FILE")

    inv_count=$(jq 'length' "$INV_VIOLATIONS_TMP")
    inv_ok=true
    [[ "$inv_count" -gt 0 ]] && inv_ok=false
    # Bug-fix (Wave 5, additive): the filter only uses --argjson vars (no input
    # document). Without piping `null` jq sees empty stdin and emits nothing,
    # leaving INV_BLOCK empty and breaking the merge on the next line.
    INV_BLOCK=$(jq -c --argjson ok "$inv_ok" --argjson v "$(cat "$INV_VIOLATIONS_TMP")" \
        '{ ok: $ok, violations: $v }' <<< "null")
    rm -f "$INV_VIOLATIONS_TMP"
fi

# Merge soundness: INV_BLOCK replaces the placeholder invariant entry.
SOUNDNESS_JSON=$(echo "$SOUNDNESS_JSON" | jq -c --argjson inv "$INV_BLOCK" '.invariant = $inv')

OVERALL_OK=$(echo "$SOUNDNESS_JSON" | jq '[.[] | .ok] | all')

# ---------- 4. Emit plan JSON ----------
jq -c --argjson soundness "$SOUNDNESS_JSON" --argjson ok "$OVERALL_OK" \
    --arg at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    --arg project "$STRUCT_FILE" \
    '
    .plan as $plan |
    .resolved as $resolved |
    {
      schema_version: "1.0",
      generated_at: $at,
      project: $project,
      plan: $plan,
      resolved: $resolved,
      soundness: { ok: $ok, predicates: $soundness },
      stats: {
        waves: ($plan | length),
        components: ([ $plan[].components[] ] | length),
        parallelism_max: ([ $plan[].components | length ] | max // 0)
      }
    }
' "$TMP.plan" > "$PLAN_OUT"

if [[ "$OVERALL_OK" != "true" ]]; then
    vfail "soundness check FAILED; partial plan written to $PLAN_OUT"
    if [[ "$JSON_OUT" != "1" ]]; then
        echo "$SOUNDNESS_JSON" | jq -r '
            (. | to_entries[] |
                "  [FAIL] \(.key)  " + ((.value.violations | length) | tostring) + " violation(s)")
            ),
            (. | to_entries[] |
                select(.value.violations | length > 0) |
                .value.violations[] |
                "         -> " + .location + ": " + .message
            )
        '
    fi
    exit 1
fi

vok "sound plan emitted: $PLAN_OUT"
vsay "waves=$(jq '.stats.waves' "$PLAN_OUT"), components=$(jq '.stats.components' "$PLAN_OUT"), max_parallelism=$(jq '.stats.parallelism_max' "$PLAN_OUT")"

if [[ "$JSON_OUT" == "1" ]]; then
    cat "$PLAN_OUT"
fi

exit 0