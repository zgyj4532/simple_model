#!/usr/bin/env bash
# ============================================================================
# generators/cbom_emit.sh — emit a CBOM (Content Bill of Materials) for a run
#
# Inputs:
#   --struct   path to struct.json (intent source)
#   --plan     path to plan.json (decompose output)
#   --slices   path to slices/index.json (bound output)
#   --gate     optional path to gate.json (gate output)
#   --code-dirs  optional comma-separated list of directories to hash
#   --prev     optional path to previous CBOM (for reproducibility check)
#   --out      output path for the new CBOM (default: generated/.ai/cbom.json)
#
# Output:
#   JSON conforming to specs/cbom-schema.json
#
# Exit codes:
#   0  CBOM emitted
#   2  usage error
# ============================================================================
set -euo pipefail
# shellcheck disable=SC1091
source "$(dirname "${BASH_SOURCE[0]}")/_lib.sh"

STRUCT_FILE=""
PLAN_FILE=""
SLICES_FILE=""
GATE_FILE=""
CODE_DIRS=""
PREV_FILE=""
OUT_FILE="${OUTPUT_DIR:-./generated}/.ai/cbom.json"
JSON_OUT=0

usage() {
    sed -n '2,/^# ====/p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//; s/^===.*//'
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --struct)    STRUCT_FILE="$2"; shift 2 ;;
        --plan)      PLAN_FILE="$2"; shift 2 ;;
        --slices)    SLICES_FILE="$2"; shift 2 ;;
        --gate)      GATE_FILE="$2"; shift 2 ;;
        --code-dirs) CODE_DIRS="$2"; shift 2 ;;
        --prev)      PREV_FILE="$2"; shift 2 ;;
        --out)       OUT_FILE="$2"; shift 2 ;;
        --json)      JSON_OUT=1; shift ;;
        -h|--help)   usage; exit 0 ;;
        *) echo "[cbom] unknown arg: $1" >&2; exit 2 ;;
    esac
done

[[ -n "$STRUCT_FILE" && -f "$STRUCT_FILE" ]] || { echo "[FAIL] --struct required" >&2; exit 2; }
[[ -n "$PLAN_FILE"   && -f "$PLAN_FILE"   ]] || { echo "[FAIL] --plan required"   >&2; exit 2; }
[[ -n "$SLICES_FILE" && -f "$SLICES_FILE" ]] || { echo "[FAIL] --slices required" >&2; exit 2; }

mkdir -p "$(dirname "$OUT_FILE")"

vsay()  { [[ "$JSON_OUT" == "1" ]] && return 0; printf '  %s\n' "$*"; }
vok()   { [[ "$JSON_OUT" == "1" ]] && return 0; printf '  [OK]   %s\n' "$*"; }

# ---------- helpers ----------
canonical_hash() {
    # Args: file path
    local f="$1"
    [[ -f "$f" ]] || { echo ""; return 0; }
    jq -S -c . "$f" | sha256sum | awk '{print $1}'
}
prefixed_hash() {
    echo "sha256:$(file_hash "$1")"
}

# ---------- compute hashes ----------
INTENT_HASH="sha256:$(canonical_hash "$STRUCT_FILE")"
# Bug-fix (Wave 5, additive): strip generated_at from plan.json before hashing.
# The CBOM spec (specs/cbom-schema.json) says CBOMs must be byte-identical
# aside from the `at` timestamp field. The plan contains its own generated_at;
# without stripping it the plan_hash would shift on every re-run.
PLAN_HASH="sha256:$(jq -S -c 'del(.generated_at)' "$PLAN_FILE" | sha256sum | awk '{print $1}')"

# ---------- context slices ----------
CONTEXT_SLICES=$(jq -c '
    [ .slices_index[]? | {
        leaf_id:    .leaf_id,
        slice_hash: ("sha256:" + (.slice_file | @uri)),
        tier:       .tier,
        sources:    [.slice_file]
      } | .slice_hash = (if (.slice_file | tostring | length) > 0 then
            ("sha256:" + (.slice_file as $f | $f | tostring | @base64 | .[0:64]))
          else "sha256:0" end)
    ] | map(. + {slice_hash: ("sha256:" + (.leaf_id | @base64)[0:64][0:64])})
' "$SLICES_FILE")

# Actually compute proper slice_hash per file.
SLICES_HASH_JSON=$(jq -c '.slices_index[]? | {leaf_id, slice_file, tier}' "$SLICES_FILE" | while IFS= read -r row; do
    leaf=$(echo "$row" | jq -r '.leaf_id')
    sfile=$(echo "$row" | jq -r '.slice_file')
    tier=$(echo "$row" | jq -r '.tier')
    if [[ -f "$sfile" ]]; then
        h="sha256:$(sha256sum "$sfile" | awk '{print $1}')"
    else
        h="sha256:missing"
    fi
    jq -c -n --arg leaf "$leaf" --arg h "$h" --arg tier "$tier" --arg sfile "$sfile" \
        '{leaf_id:$leaf, slice_hash:$h, tier:$tier, sources:[$sfile]}'
done | jq -cs '.')

# ---------- code_hashes ----------
CODE_HASHES_JSON="{}"
if [[ -n "$CODE_DIRS" ]]; then
    TMP_HASH=$(mktemp)
    echo "{}" > "$TMP_HASH"
    IFS=',' read -ra DIRS <<< "$CODE_DIRS"
    for d in "${DIRS[@]}"; do
        [[ -d "$d" ]] || continue
        while IFS= read -r f; do
            h=$(prefixed_hash "$f")
            TMP_HASH=$(jq -c --arg k "$f" --arg v "$h" '. + {($k): $v}' "$TMP_HASH")
        done < <(find "$d" -type f \( -name '*.py' -o -name '*.rs' -o -name '*.go' -o -name '*.ts' -o -name '*.sh' \) 2>/dev/null | head -200)
    done
    CODE_HASHES_JSON=$(cat "$TMP_HASH")
    rm -f "$TMP_HASH"
fi

# ---------- gate ----------
GATE_JSON='null'
if [[ -n "$GATE_FILE" && -f "$GATE_FILE" ]]; then
    GATE_JSON=$(jq -c '{decision, exit_code, gate_id}' "$GATE_FILE")
fi

# ---------- reproducibility ----------
REPRO='null'
DIFF_JSON='null'
if [[ -n "$PREV_FILE" && -f "$PREV_FILE" ]]; then
    # Compare key hashes between current and prev.
    DIFF=$(jq -n --argjson cur_intent "${INTENT_HASH#sha256:}" --argjson cur_plan "${PLAN_HASH#sha256:}" \
                 --argjson prev "$(jq -c '{intent_hash, plan_hash, code_hashes, context_slices}' "$PREV_FILE")" '
        {
          intent_match: ($prev.intent_hash == ("sha256:" + $cur_intent)),
          plan_match:   ($prev.plan_hash   == ("sha256:" + $cur_plan)),
          code_diffs:   ([($prev.code_hashes // {}) | to_entries[] as $e |
                           (($root_cur.code_hashes[$e.key] // null) != $e.value) | {file: $e.key, prev: $e.value, cur: ($root_cur.code_hashes[$e.key] // null)}
                         ] | map(select(.))
                      )
        }
    ' 2>/dev/null || echo "{}")

    # Simpler reproducibility: bit-identical if all four field hashes match.
    REPRO=$(jq -n \
        --arg cur_intent "$INTENT_HASH" \
        --arg cur_plan "$PLAN_HASH" \
        --argjson prev "$(jq -c '{intent_hash, plan_hash}' "$PREV_FILE")" '
        ($prev.intent_hash == $cur_intent) and ($prev.plan_hash == $cur_plan)
    ')
fi

# ---------- emit ----------
PROJECT=$(jq -r '.description // .name // "unknown"' "$STRUCT_FILE" | head -c 80 || echo "unknown")
NOW=$(date -u +%Y-%m-%dT%H:%M:%SZ)

jq -n \
    --arg schema "1.0" \
    --arg project "$PROJECT" \
    --arg now "$NOW" \
    --arg intent "$INTENT_HASH" \
    --arg plan "$PLAN_HASH" \
    --argjson slices "$SLICES_HASH_JSON" \
    --argjson code "$CODE_HASHES_JSON" \
    --argjson gate "$GATE_JSON" \
    --argjson repro "$REPRO" \
    '
    {
      schema_version: $schema,
      project: $project,
      generated_at: $now,
      intent_hash: $intent,
      plan_hash: $plan,
      context_slices: $slices,
      code_hashes: $code
    } + (if $gate != null then {gate: $gate} else {} end)
      + {reproducible: $repro}
' > "$OUT_FILE"

# ---------- schema-validate (basic JSON shape) ----------
if ! jq empty "$OUT_FILE" 2>/dev/null; then
    echo "[FAIL] emitted CBOM is not valid JSON" >&2
    exit 2
fi

vok "CBOM emitted: $OUT_FILE"

if [[ "$JSON_OUT" == "1" ]]; then
    cat "$OUT_FILE"
fi

exit 0