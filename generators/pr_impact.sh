#!/usr/bin/env bash
set -euo pipefail
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SELF_DIR/_lib.sh"
ROOT="."; FILES=""; BASE=""; HEAD=""; JSON_OUT=0
while [[ $# -gt 0 ]]; do
    case "$1" in
        --root) ROOT="$2"; shift 2 ;;
        --struct|-s) STRUCT_FILE="$2"; shift 2 ;;
        --files) FILES="$2"; shift 2 ;;
        --base) BASE="$2"; shift 2 ;;
        --head) HEAD="$2"; shift 2 ;;
        --json) JSON_OUT=1; shift ;;
        *) echo "未知参数: $1" >&2; exit 64 ;;
    esac
done
ROOT="$(cd "$ROOT" && pwd)"
if [[ -z "$FILES" ]]; then
    if [[ -n "$BASE" && -n "$HEAD" ]]; then
        FILES=$(git -C "$ROOT" diff --name-only "$BASE" "$HEAD" 2>/dev/null | paste -sd,)
    else
        FILES=$(git -C "$ROOT" diff --name-only 2>/dev/null | paste -sd,)
    fi
fi
files_json=$(tr ',' '\n' <<<"$FILES" | sed '/^$/d' | jq -R -s 'split("\n")[:-1]')
components=$(jq -c --argjson files "$files_json" '
  [.modules[]? as $m | $m.components[]? | . as $c
   | select((($c.path // "") != "") and (($files | index($c.path)) != null))
   | {
       module:$m.name,
       component:.name,
       path:(.path // ""),
       owners:(if (.owners // null) != null then .owners elif ($m.owners // null) != null then $m.owners else [] end),
       risk:(.risk // "medium"),
       checks:(if (.checks // null) != null then .checks elif ($m.checks // null) != null then $m.checks else ({}) end)
     }]
' "$STRUCT_FILE")
tests=$(bash "$SELF_DIR/test_surface_scan.sh" --root "$ROOT" --struct "$STRUCT_FILE" --json | jq -c '.tests')
out=$(jq -n --argjson files "$files_json" --argjson components "$components" --argjson tests "$tests" '{
  ok:true,
  files:$files,
  impacted_components:$components,
  tests:$tests,
  summary:{files:($files|length), components:($components|length), tests:($tests|length)}
}')
[[ "$JSON_OUT" == "1" ]] && echo "$out" || jq -r '.'
