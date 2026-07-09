#!/usr/bin/env bash
set -euo pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SELF_DIR/.." && pwd)"
REGISTRY="$ROOT/macros/registry.json"
JSON_OUT=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        --registry) REGISTRY="$2"; shift 2 ;;
        --json) JSON_OUT=1; shift ;;
        -h|--help)
            echo "macro_registry.sh [--registry macros/registry.json] [--json]"
            exit 0
            ;;
        *) echo "unknown arg: $1" >&2; exit 64 ;;
    esac
done

command -v jq >/dev/null 2>&1 || { echo "[FAIL] missing jq" >&2; exit 2; }
[[ -f "$REGISTRY" ]] || { echo "[FAIL] registry not found: $REGISTRY" >&2; exit 2; }
jq empty "$REGISTRY"

report=$(jq '
  def valid_id: test("^[a-z][a-z0-9_]*$");
  . as $r
  | [($r.macros // [])[] | select((.id|valid_id|not) or ((.type == "code" or .type == "exec")|not) or ((.risk == "low" or .risk == "medium" or .risk == "high" or .risk == "critical")|not) or (.auto_apply|type != "boolean"))] as $invalid
  | {
      ok:($invalid|length == 0),
      registry: input_filename,
      schema_version:(.schema_version // ""),
      summary:{
        macros:(.macros|length),
        code:([.macros[]|select(.type=="code")]|length),
        exec:([.macros[]|select(.type=="exec")]|length),
        invalid:($invalid|length)
      },
      macros:.macros,
      invalid:$invalid
    }
' "$REGISTRY")

if [[ "$JSON_OUT" == "1" ]]; then
    printf '%s\n' "$report"
else
    jq -r '"Macro Registry\n  macros: " + (.summary.macros|tostring) + "\n  code: " + (.summary.code|tostring) + "\n  exec: " + (.summary.exec|tostring) + "\n  invalid: " + (.summary.invalid|tostring), (.macros[] | "  - " + .id + " [" + .type + "/" + .risk + "] " + .description)' <<<"$report"
fi

jq -e '.ok == true' <<<"$report" >/dev/null
