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
            echo "optimization_plan.sh --root <repo> --struct <struct> [--output-dir generated/optimization] [--json]"
            exit 0
            ;;
        *) echo "unknown arg: $1" >&2; exit 64 ;;
    esac
done

command -v jq >/dev/null 2>&1 || { echo "[FAIL] missing jq" >&2; exit 2; }
[[ -d "$ROOT" ]] || { echo "[FAIL] root not found: $ROOT" >&2; exit 2; }
[[ -f "$STRUCT" ]] || { echo "[FAIL] struct not found: $STRUCT" >&2; exit 2; }
jq empty "$STRUCT"
mkdir -p "$OUT_DIR"

ROOT="$(cd "$ROOT" && pwd)"
STRUCT_ABS="$(cd "$(dirname "$STRUCT")" && pwd)/$(basename "$STRUCT")"

adoption=$(bash "$SELF_DIR/adoption_audit.sh" --root "$ROOT" --struct "$STRUCT_ABS" --json || true)
interface=$(bash "$SELF_DIR/interface_scan.sh" --root "$ROOT" --struct "$STRUCT_ABS" --json || true)
imports=$(bash "$SELF_DIR/import_graph_scan.sh" --root "$ROOT" --struct "$STRUCT_ABS" --json || true)
debt=$(bash "$SELF_DIR/architecture_debt.sh" --root "$ROOT" --struct "$STRUCT_ABS" --json || true)
registry=$(bash "$SELF_DIR/macro_registry.sh" --json)

plan=$(jq -n \
  --arg root "$ROOT" \
  --arg struct "$STRUCT_ABS" \
  --arg generated_at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --argjson struct_json "$(jq . "$STRUCT_ABS")" \
  --argjson adoption "$adoption" \
  --argjson interface "$interface" \
  --argjson imports "$imports" \
  --argjson debt "$debt" \
  --argjson registry "$registry" '
  def macro($id): $registry.macros[] | select(.id == $id);
  def mk_action($id; $reason; $target; $evidence; $priority):
    (macro($id)) as $m
    | {
        id:("macro." + $id + "." + ($priority|tostring)),
        macro_id:$id,
        macro_type:$m.type,
        description:$m.description,
        reason:$reason,
        risk:$m.risk,
        auto_apply:$m.auto_apply,
        target:$target,
        evidence:$evidence,
        validations:$m.validations,
        writes:$m.writes,
        status:"planned",
        priority:$priority
      };
  [
    (if (($struct_json.includes // [])|length) == 0 and (($struct_json.modules // [])|length) > 1
     then mk_action("split_struct_include"; "single struct has multiple modules and can be split into includes"; {struct:$struct}; {modules:(($struct_json.modules // [])|length)}; 90)
     else empty end),
    ($interface.components[]? | select((.undeclared_exports|length) > 0)
      | mk_action("normalize_component_exports"; "code exposes public symbols missing from struct exports"; {module:.module, component:.component, path:.path, struct:$struct}; {undeclared_exports:.undeclared_exports, discovered_exports:.discovered_exports, declared_exports:.declared_exports}; 20)),
    ($imports.findings[]? | select(.type == "undeclared_import")
      | mk_action("sync_struct_imports_from_code_facts"; "code imports component not declared in struct imports"; {component:.component, target:.target, struct:$struct}; {import:.message, target:.target}; 30))
  ] | sort_by(.priority, .macro_id, (.target.component // "")) as $actions
  | {
      schema_version:"1.0",
      generated_at:$generated_at,
      root:$root,
      struct:$struct,
      mode:"plan",
      ok:true,
      facts:{
        adoption:{unmanaged_files:($adoption.unmanaged_files // 0), total_files:($adoption.total_files // 0)},
        interface:$interface.summary,
        imports:$imports.summary,
        debt:$debt.summary
      },
      summary:{
        actions:($actions|length),
        auto_apply:($actions|map(select(.auto_apply == true))|length),
        high_risk:($actions|map(select(.risk == "high" or .risk == "critical"))|length),
        unmanaged_files:($adoption.unmanaged_files // 0),
        interface_drift:($interface.summary.undeclared_exports // 0),
        import_drift:($imports.summary.warnings // 0),
        debt_findings:($debt.summary.findings // 0)
      },
      actions:$actions
    }')

printf '%s\n' "$plan" > "$OUT_DIR/plan.json"
{
    echo "# Project Optimization Plan"
    echo
    jq -r '"- target: " + .root, "- struct: " + .struct, "- actions: " + (.summary.actions|tostring), "- auto_apply: " + (.summary.auto_apply|tostring), "- interface_drift: " + (.summary.interface_drift|tostring), "- import_drift: " + (.summary.import_drift|tostring), "- unmanaged_files: " + (.summary.unmanaged_files|tostring)' <<<"$plan"
    echo
    echo "## Planned Macros"
    jq -r '.actions[]? | "- " + .macro_id + " risk=" + .risk + " target=" + ((.target.component // .target.struct // "repo")|tostring) + " reason=" + .reason' <<<"$plan"
} > "$OUT_DIR/report.md"

if [[ "$JSON_OUT" == "1" ]]; then
    printf '%s\n' "$plan"
else
    jq -r '"Project Optimization Plan\n\nTarget: " + .root + "\nStruct: " + .struct + "\n\nFindings:\n  unmanaged files: " + (.summary.unmanaged_files|tostring) + "\n  interface drift: " + (.summary.interface_drift|tostring) + "\n  import drift: " + (.summary.import_drift|tostring) + "\n  debt findings: " + (.summary.debt_findings|tostring) + "\n\nPlanned Macros:\n" + ((.actions | map("  - " + .macro_id + " risk=" + .risk + " target=" + ((.target.component // .target.struct // "repo")|tostring)) | join("\n")) // "  none") + "\n\nReport: generated/optimization/report.md"' <<<"$plan"
fi
