#!/usr/bin/env bash
set -euo pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SELF_DIR/.." && pwd)"
SUGGESTIONS="generated/optimization/macro-suggestions.json"
ROOT=""
STRUCT=""
OUT_DIR="generated/optimization"
JSON_OUT=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        --suggestions) SUGGESTIONS="$2"; shift 2 ;;
        --root) ROOT="$2"; shift 2 ;;
        --struct|-s) STRUCT="$2"; shift 2 ;;
        --output-dir) OUT_DIR="$2"; shift 2 ;;
        --json) JSON_OUT=1; shift ;;
        -h|--help)
            echo "macro_compile.sh --suggestions generated/optimization/macro-suggestions.json [--root <repo>] [--struct <struct>] [--json]"
            exit 0
            ;;
        *) echo "unknown arg: $1" >&2; exit 64 ;;
    esac
done

command -v jq >/dev/null 2>&1 || { echo "[FAIL] missing jq" >&2; exit 2; }
[[ -f "$SUGGESTIONS" ]] || { echo "[FAIL] suggestions not found: $SUGGESTIONS" >&2; exit 2; }
jq empty "$SUGGESTIONS"
mkdir -p "$OUT_DIR"

ROOT="${ROOT:-$(jq -r '.root' "$SUGGESTIONS")}"
STRUCT="${STRUCT:-$(jq -r '.struct' "$SUGGESTIONS")}"
[[ -d "$ROOT" ]] || { echo "[FAIL] root not found: $ROOT" >&2; exit 2; }
[[ -f "$STRUCT" ]] || { echo "[FAIL] struct not found: $STRUCT" >&2; exit 2; }
ROOT="$(cd "$ROOT" && pwd)"
STRUCT="$(cd "$(dirname "$STRUCT")" && pwd)/$(basename "$STRUCT")"

spec_errors=$(jq '
  def valid_id: . as $s | (($s.id|type) == "string" and ($s.id|test("^[a-z][a-z0-9_.-]*$")));
  [
    .specs[]? |
    select(
      (.schema_version != "1.0") or
      (.kind != "generated_macro") or
      ((.template == "field_sync" or .template == "include_split" or .template == "path_adoption")|not) or
      ((.rewrite.mode == "replace_sorted_unique" or .rewrite.mode == "append_sorted_unique" or .rewrite.mode == "split_modules_to_includes" or .rewrite.mode == "propose_component_paths")|not) or
      ((.safety.dry_run_required|type) != "boolean") or
      ((.safety.max_components|type) != "number") or
      (valid_id|not)
    ) |
    {id:(.id // "unknown"), template:(.template // ""), rewrite:(.rewrite.mode // ""), error:"invalid_macro_spec"}
  ]
' "$SUGGESTIONS")
if [[ "$(jq 'length' <<<"$spec_errors")" -gt 0 ]]; then
    jq -n --argjson errors "$spec_errors" '{ok:false, error:"macro_spec_validation_failed", errors:$errors}'
    exit 1
fi

plan=$(jq -n \
  --arg root "$ROOT" \
  --arg struct "$STRUCT" \
  --arg generated_at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --argjson suggestions "$(jq . "$SUGGESTIONS")" '
  def action($spec; $macro_id; $target; $evidence; $priority):
    {
      id:("compiled." + $spec.id),
      macro_id:$macro_id,
      macro_type:"code",
      description:$spec.description,
      reason:("compiled from declarative macro spec " + $spec.id),
      risk:$spec.safety.risk,
      auto_apply:($spec.safety.auto_apply // false),
      target:$target,
      evidence:$evidence,
      validations:[],
      writes:["struct.json"],
      status:"planned",
      priority:$priority,
      compiled_from:$spec.id
    };
  [
    ($suggestions.specs[]? as $s
      | if $s.template == "include_split" and $s.rewrite.mode == "split_modules_to_includes" then
          action($s; "split_struct_include"; {struct:$struct}; $s.evidence; 90)
        elif $s.template == "field_sync" and $s.rewrite.target_path == "component.exports" then
          action($s; "normalize_component_exports"; {module:$s.selector.module, component:$s.selector.component, path:$s.selector.path, struct:$struct}; {declared_exports:$s.evidence.declared_exports, discovered_exports:$s.evidence.discovered_exports, undeclared_exports:$s.evidence.undeclared_exports}; 20)
        elif $s.template == "field_sync" and $s.rewrite.target_path == "component.imports" then
          action($s; "sync_struct_imports_from_code_facts"; {component:$s.selector.component, target:$s.selector.target, struct:$struct}; {target:$s.evidence.target, import:$s.evidence.message}; 30)
        else
          empty
        end)
  ] | sort_by(.priority, .macro_id, (.target.component // "")) as $actions
  | {
      schema_version:"1.0",
      generated_at:$generated_at,
      root:$root,
      struct:$struct,
      mode:"compiled-plan",
      ok:true,
      source:$suggestions,
      summary:{
        specs:($suggestions.specs|length),
        actions:($actions|length),
        skipped:(($suggestions.specs|length) - ($actions|length)),
        auto_apply:($actions|map(select(.auto_apply == true))|length)
      },
      actions:$actions
    }')

printf '%s\n' "$plan" > "$OUT_DIR/compiled-plan.json"
printf '%s\n' "$plan" > "$OUT_DIR/plan.json"

if [[ "$JSON_OUT" == "1" ]]; then
    printf '%s\n' "$plan"
else
    jq -r '"Macro Compile\n\nSpecs: " + (.summary.specs|tostring) + "\nActions: " + (.summary.actions|tostring) + "\nSkipped: " + (.summary.skipped|tostring) + "\n\nPlan: generated/optimization/compiled-plan.json"' <<<"$plan"
fi
