#!/usr/bin/env bash
# ============================================================================
# generators/orchestrate_bound.sh — intent-consistent context bounding (Wave 3)
#
# For each leaf task (component) in a wave-plan, emit a context slice:
#   { leaf_id, phase, tier, sources:{self, deps, phase, invariants_visible}, token_estimate }
#
# Sources are derived purely from struct.json + the wave-plan + invariants file.
# No LLM, no symbol parser. The slice is the principled-minimum projection:
#   - self         : the component's name, description, exports, imports, phase
#   - deps         : direct imports (filtered to the resolved set)
#   - phase        : the phase's declaration (core/optional/select_one_of)
#   - invariants_visible : user-declared invariants whose scope intersects the leaf
#
# Output: one .ai/slices/<leaf>.json per leaf, plus .ai/slices-index.json summary.
#
# Exit codes:
#   0  all slices emitted
#   2  usage error
#   4  inconsistency (a leaf has no phase declared)
# ============================================================================
set -euo pipefail
# shellcheck disable=SC1091
source "$(dirname "${BASH_SOURCE[0]}")/_lib.sh"

STRUCT_FILE="${STRUCT_FILE:-./struct.json}"
PLAN_FILE="${PLAN_FILE:-./generated/.ai/plan.json}"
INVARIANTS_FILE=""
OUT_DIR="${OUTPUT_DIR:-./generated}/.ai/slices"
JSON_OUT=0

usage() {
    sed -n '2,/^# ====/p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//; s/^===.*//'
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        -s|--struct)         STRUCT_FILE="$2"; shift 2 ;;
        -p|--plan)           PLAN_FILE="$2"; shift 2 ;;
        --invariants)        INVARIANTS_FILE="$2"; shift 2 ;;
        --out-dir)           OUT_DIR="$2"; shift 2 ;;
        --json)              JSON_OUT=1; shift ;;
        -h|--help)           usage; exit 0 ;;
        -*) echo "[bound] unknown arg: $1" >&2; exit 2 ;;
        *)
            # Positional form: `bash orchestrate_bound.sh plan.json struct.json`
            # First non-flag arg = plan, second = struct (order matches docs).
            if [[ -z "${POSITIONAL_PLAN:-}" ]]; then
                POSITIONAL_PLAN="$1"; shift
            elif [[ -z "${POSITIONAL_STRUCT:-}" ]]; then
                POSITIONAL_STRUCT="$1"; shift
            else
                echo "[bound] unknown arg: $1" >&2; exit 2
            fi
            ;;
    esac
done

[[ -n "${POSITIONAL_PLAN:-}"   ]] && PLAN_FILE="$POSITIONAL_PLAN"
[[ -n "${POSITIONAL_STRUCT:-}" ]] && STRUCT_FILE="$POSITIONAL_STRUCT"

[[ -f "$STRUCT_FILE" ]] || { echo "[FAIL] struct.json not found: $STRUCT_FILE" >&2; exit 2; }
[[ -f "$PLAN_FILE" ]]   || { echo "[FAIL] plan not found: $PLAN_FILE (run orchestrate_decompose.sh first)" >&2; exit 2; }

mkdir -p "$OUT_DIR"

vsay()  { [[ "$JSON_OUT" == "1" ]] && return 0; printf '  %s\n' "$*"; }
vok()   { [[ "$JSON_OUT" == "1" ]] && return 0; printf '  [OK]   %s\n' "$*"; }
vfail() { printf '  [FAIL] %s\n' "$*" >&2; }

# Load plan + struct.
PLAN_JSON=$(cat "$PLAN_FILE")
SELECTED_JSON=$(echo "$PLAN_JSON" | jq -c '.resolved.selected_components // []')

# Per-phase membership map.
PHASE_MEMBERSHIP=$(jq -c --argjson sel "$SELECTED_JSON" '
    . as $root |
    # Per-component flat record.
    [ ($root.modules // []) | .[] | (.components // []) | .[] |
      .name as $n | .module as $mod |
      { name: $n, module: $mod,
        exports:    ((.exports // []) | sort),
        imports:    ((.imports // []) | sort),
        description: (.description // ""),
        optional:   (.optional // false)
      }
    ] as $all |
    # Build phase-of-name map: {name: phase} via (phase, name) tuples then fold.
    ([ $root.phases[] |
        . as $p |
        ((.core_components // []) + (.optional_components // []) +
         (.select_one_of // []) + (.select_subset_of // [])) as $cs |
        [ $cs[] | { key: ., value: $p.phase } ]
    ] | add // []) as $kvs |
    ([ $kvs[] | { (.key): .value } ] | add // {}) as $phase_of |
    [ $all[] | . as $c |
        { ($c.name): { module: $c.module, phase: ($phase_of[$c.name] // null),
                       exports: $c.exports, imports: $c.imports,
                       description: $c.description, optional: $c.optional } }
    ] | add // {}
' "$STRUCT_FILE")

# Invariants visible per leaf (filter the invariant list by scope intersection).
INV_INDEX="[]"
if [[ -n "$INVARIANTS_FILE" ]] && [[ -f "$INVARIANTS_FILE" ]]; then
    INV_INDEX=$(jq -c '.' "$INVARIANTS_FILE")
fi

# Emit slices.
INDEX_ENTRIES="[]"

# Iterate leaves in plan order.
LEAVES=$(echo "$PLAN_JSON" | jq -c '[.plan[].components[]] | unique')

# Pre-check: every leaf must belong to a declared phase.
# Doc'd exit code 4 = "Phase inconsistency — a resolved component has no phase".
# This is a different class of failure than "slice missing" or "deps empty":
# the leaf is genuinely orphaned and cannot be sliced meaningfully.
NO_PHASE_LEAVES=$(jq -c --argjson sel "$SELECTED_JSON" '
    . as $root |
    ([ ($root.phases // []) | .[] |
        ((.core_components // []) + (.optional_components // []) +
         (.select_one_of // []) + (.select_subset_of // [])) ] | flatten | unique) as $phase_components |
    ([ ($root.cross_cutting // []) | .[] |
       select((.default_enabled // true) == true) | .components[] ] | unique) as $xcut_components |
    ($phase_components + $xcut_components | unique) as $all_components |
    [ $sel[] | select(. as $n | $all_components | index($n) | not) ]
' "$STRUCT_FILE")
NO_PHASE_COUNT=$(echo "$NO_PHASE_LEAVES" | jq 'length')
if [[ "$NO_PHASE_COUNT" -gt 0 ]]; then
    vfail "phase inconsistency: $NO_PHASE_COUNT resolved component(s) have no phase declaration"
    NO_PHASE_DISPLAY=$(echo "$NO_PHASE_LEAVES" | jq -c '. | join(", ")')
    printf '         -> leaves without phase: %s\n' "$NO_PHASE_DISPLAY"
    exit 4
fi

while IFS= read -r leaf; do
    [[ -z "$leaf" ]] && continue

    # self
    SELF=$(jq -c --arg leaf "$leaf" --argjson pm "$PHASE_MEMBERSHIP" '
        $pm[$leaf] // null
    ' <<< "$PHASE_MEMBERSHIP")

    # deps (intersect with selected)
    DEPS=$(jq -c --arg leaf "$leaf" --argjson sel "$SELECTED_JSON" --argjson pm "$PHASE_MEMBERSHIP" '
        ([ ($pm[$leaf].imports // [])[] | select(. as $n | $sel | index($n)) ]) as $direct |
        ([ $direct[] as $d | { name: $d,
                                module: ($pm[$d].module // null),
                                phase:  ($pm[$d].phase  // null),
                                exports: ($pm[$d].exports // []),
                                description: ($pm[$d].description // "")
                              } ])
    ' <<< "$PHASE_MEMBERSHIP")

    # phase (the leaf's phase declaration)
    PHASE_BLOCK=$(jq -c --arg leaf "$leaf" '
        . as $root |
        [ $root.phases[] | select(
            ((.core_components // []) | index($leaf)) != null or
            ((.optional_components // []) | index($leaf)) != null or
            ((.select_one_of // []) | index($leaf)) != null or
            ((.select_subset_of // []) | index($leaf)) != null
        ) | { phase: .phase, order: .order, mode: .mode,
               core_components: (.core_components // []),
               optional_components: (.optional_components // []),
               select_one_of: (.select_one_of // []),
               select_subset_of: (.select_subset_of // []) }
    ] | (if length == 0 then null else .[0] end)
    ' "$STRUCT_FILE")

    # invariants_visible: filter INV_INDEX by scope.
    INV_VISIBLE=$(jq -c --arg leaf "$leaf" --argjson pm "$PHASE_MEMBERSHIP" --argjson inv "$INV_INDEX" '
        [ $inv[] | select(
            (.scope == "all_components") or
            (.scope | startswith("components_in_phase:") | not) and false or
            (.scope == ("components_in_phase:" + ($pm[$leaf].phase // ""))) or
            false
        ) ]
    ' <<< '{}')

    # Simpler: build invariants_visible directly via two branches.
    LEAF_PHASE=$(jq -r --arg leaf "$leaf" --argjson pm "$PHASE_MEMBERSHIP" '$pm[$leaf].phase // ""' <<< "$PHASE_MEMBERSHIP")
    INV_VISIBLE=$(jq -c --arg leaf "$leaf" --arg leaf_phase "$LEAF_PHASE" --argjson inv "$INV_INDEX" '
        [ $inv[] | select(
            (.scope == "all_components") or
            (.scope == ("components_in_phase:" + $leaf_phase))
        ) ]
    ' <<< '{}')

    # tier (core | optional | xcut) — derived from membership.
    TIER="core"
    if [[ "$(echo "$SELF" | jq '.optional // false')" == "true" ]]; then
        TIER="optional"
    fi

    # token_estimate — sum of self+deps+phase+inv text length (cheap heuristic).
    TOK=$(echo "$SELF $DEPS $PHASE_BLOCK $INV_VISIBLE" | wc -c)

    SLICE_JSON=$(jq -c -n \
        --arg leaf "$leaf" \
        --argjson self "$SELF" \
        --argjson deps "$DEPS" \
        --argjson phase "$PHASE_BLOCK" \
        --argjson inv_v "$INV_VISIBLE" \
        --arg tier "$TIER" \
        --argjson tok "$TOK" \
        '{
            schema_version: "1.0",
            leaf_id: $leaf,
            phase: ($self.phase // null),
            tier: $tier,
            sources: {
                self:     $self,
                deps:     $deps,
                phase:    $phase,
                invariants_visible: $inv_v
            },
            token_estimate: ($tok | tonumber)
        }')

    echo "$SLICE_JSON" > "$OUT_DIR/$leaf.json"

    INDEX_ENTRIES=$(echo "$INDEX_ENTRIES" | jq -c \
        --arg leaf "$leaf" --argjson slice "$SLICE_JSON" \
        '. + [{ leaf_id: $leaf, slice_file: ("'"$OUT_DIR"'/" + $leaf + ".json"),
                phase: ($slice.phase // null), tier: $slice.tier }]')
done < <(echo "$LEAVES" | jq -r '.[]')

# Write index.
jq -c -n --argjson entries "$INDEX_ENTRIES" \
    '{ schema_version: "1.0",
       slices_index: $entries,
       count: ($entries | length) }' > "$OUT_DIR/index.json"

vok "emitted $(echo "$INDEX_ENTRIES" | jq 'length') slice(s) to $OUT_DIR"
vsay "index: $OUT_DIR/index.json"

if [[ "$JSON_OUT" == "1" ]]; then
    jq . "$OUT_DIR/index.json"
fi

exit 0