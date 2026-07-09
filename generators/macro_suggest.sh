#!/usr/bin/env bash
set -euo pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="."
STRUCT="${STRUCT_FILE:-./struct.json}"
OUT_DIR="generated/optimization"
JSON_OUT=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        --root) ROOT="$2"; shift 2 ;;
        --struct|-s) STRUCT="$2"; shift 2 ;;
        --output-dir) OUT_DIR="$2"; shift 2 ;;
        --json) JSON_OUT=1; shift ;;
        -h|--help)
            echo "macro_suggest.sh --root <repo> --struct <struct> [--output-dir generated/optimization] [--json]"
            exit 0
            ;;
        *) echo "unknown arg: $1" >&2; exit 64 ;;
    esac
done

command -v jq >/dev/null 2>&1 || { echo "[FAIL] missing jq" >&2; exit 2; }
[[ -d "$ROOT" ]] || { echo "[FAIL] root not found: $ROOT" >&2; exit 2; }
[[ -f "$STRUCT" ]] || { echo "[FAIL] struct not found: $STRUCT" >&2; exit 2; }
jq empty "$STRUCT"
mkdir -p "$OUT_DIR/specs"

ROOT="$(cd "$ROOT" && pwd)"
STRUCT_ABS="$(cd "$(dirname "$STRUCT")" && pwd)/$(basename "$STRUCT")"

adoption=$(bash "$SELF_DIR/adoption_audit.sh" --root "$ROOT" --struct "$STRUCT_ABS" --json || true)
interface=$(bash "$SELF_DIR/interface_scan.sh" --root "$ROOT" --struct "$STRUCT_ABS" --json || true)
imports=$(bash "$SELF_DIR/import_graph_scan.sh" --root "$ROOT" --struct "$STRUCT_ABS" --json || true)
struct_json=$(jq . "$STRUCT_ABS")

suggestions=$(jq -n \
  --arg root "$ROOT" \
  --arg struct "$STRUCT_ABS" \
  --arg generated_at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --argjson struct_json "$struct_json" \
  --argjson adoption "$adoption" \
  --argjson interface "$interface" \
  --argjson imports "$imports" '
  def spec($id; $template; $trigger; $description; $selector; $rewrite; $safety; $evidence):
    {
      schema_version:"1.0",
      id:$id,
      kind:"generated_macro",
      template:$template,
      trigger:$trigger,
      description:$description,
      selector:$selector,
      rewrite:$rewrite,
      safety:$safety,
      evidence:$evidence
    };
  [
    (if (($struct_json.includes // [])|length) == 0 and (($struct_json.modules // [])|length) > 1
     then spec(
       "generated.include_split.modules";
       "include_split";
       "multi_module_single_struct";
       "Split a multi-module root struct into include fragments.";
       {risk_max:"low"};
       {target_path:"$.includes", source_path:"$.modules", mode:"split_modules_to_includes", value:{module_count:(($struct_json.modules // [])|length)}};
       {dry_run_required:true, requires_clean_struct:true, max_components:1000, risk:"low", auto_apply:true};
       {modules:(($struct_json.modules // [])|length), struct:$struct}
     ) else empty end),
    ($interface.components[]? | select((.undeclared_exports|length) > 0)
      | spec(
        ("generated.field_sync.exports." + (.component|ascii_downcase));
        "field_sync";
        "undeclared_exports";
        "Synchronize component exports from interface_scan discovered exports.";
        {module:.module, component:.component, path:.path, risk_max:"medium"};
        {target_path:"component.exports", source_path:"interface_scan.components[].discovered_exports", mode:"replace_sorted_unique", value:{exports:.discovered_exports}};
        {dry_run_required:true, requires_clean_struct:true, max_components:1, risk:"medium", auto_apply:true};
        {declared_exports:.declared_exports, discovered_exports:.discovered_exports, undeclared_exports:.undeclared_exports}
      )),
    ($imports.findings[]? | select(.type == "undeclared_import")
      | spec(
        ("generated.field_sync.imports." + (.component|ascii_downcase) + "." + (.target|ascii_downcase));
        "field_sync";
        "undeclared_import";
        "Synchronize component imports from import_graph_scan observed edges.";
        {component:.component, target:.target, risk_max:"medium"};
        {target_path:"component.imports", source_path:"import_graph_scan.edges", mode:"append_sorted_unique", value:{target:.target}};
        {dry_run_required:true, requires_clean_struct:true, max_components:1, risk:"medium", auto_apply:true};
        {target:.target, message:.message}
      )),
    (if ($adoption.unmanaged_files // 0) > 0
      then spec(
        "generated.path_adoption.unmanaged_files";
        "path_adoption";
        "unmanaged_files";
        "Propose path adoption candidates from unmanaged source files.";
        {risk_max:"medium"};
        {target_path:"component.path", source_path:"adoption_audit.unmanaged", mode:"propose_component_paths", value:{unmanaged:($adoption.unmanaged // [])}};
        {dry_run_required:true, requires_clean_struct:true, max_components:50, risk:"medium", auto_apply:false};
        {unmanaged_files:($adoption.unmanaged_files // 0), unmanaged:($adoption.unmanaged // [])}
      ) else empty end)
  ] | sort_by(.id) as $specs
  | {
      schema_version:"1.0",
      ok:true,
      generated_at:$generated_at,
      root:$root,
      struct:$struct,
      templates:["field_sync", "include_split", "path_adoption"],
      summary:{
        suggestions:($specs|length),
        auto_apply:($specs|map(select(.safety.auto_apply == true))|length),
        manual:($specs|map(select(.safety.auto_apply != true))|length)
      },
      specs:$specs
    }')

printf '%s\n' "$suggestions" > "$OUT_DIR/macro-suggestions.json"
jq -c '.specs[]' <<<"$suggestions" | while IFS= read -r spec; do
    id=$(jq -r '.id' <<<"$spec" | tr '/ ' '__')
    printf '%s\n' "$spec" > "$OUT_DIR/specs/$id.json"
done

if [[ "$JSON_OUT" == "1" ]]; then
    printf '%s\n' "$suggestions"
else
    jq -r '"Macro Suggestions\n\nTarget: " + .root + "\nStruct: " + .struct + "\nSuggestions: " + (.summary.suggestions|tostring) + "\nAuto apply: " + (.summary.auto_apply|tostring) + "\nManual: " + (.summary.manual|tostring) + "\n\nSpecs:\n" + ((.specs | map("  - " + .id + " template=" + .template + " trigger=" + .trigger) | join("\n")) // "  none")' <<<"$suggestions"
fi
