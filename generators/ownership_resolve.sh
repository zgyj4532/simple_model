#!/usr/bin/env bash
set -euo pipefail
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SELF_DIR/_lib.sh"
ROOT="."; JSON_OUT=0
while [[ $# -gt 0 ]]; do
    case "$1" in
        --root) ROOT="$2"; shift 2 ;;
        --struct|-s) STRUCT_FILE="$2"; shift 2 ;;
        --json) JSON_OUT=1; shift ;;
        *) echo "未知参数: $1" >&2; exit 64 ;;
    esac
done
ROOT="$(cd "$ROOT" && pwd)"
codeowners=""
[[ -f "$ROOT/CODEOWNERS" ]] && codeowners=$(sed '/^[[:space:]]*#/d;/^[[:space:]]*$/d' "$ROOT/CODEOWNERS" | tail -n 1 | awk '{$1=""; sub(/^ /,""); print}')
owners=$(jq -c --arg fallback "$codeowners" '
  [.modules[]? as $m | $m.components[]? | {
    module:$m.name,
    component:.name,
    path:(.path//""),
    owners: ((.owners // $m.owners // []) + (if $fallback != "" then [$fallback] else [] end) | unique)
  }]
' "$STRUCT_FILE")
orphans=$(jq '[.[] | select((.owners|length)==0) | .component]' <<<"$owners")
out=$(jq -n --argjson owners "$owners" --argjson orphans "$orphans" '{ok:true, summary:{components:($owners|length), orphaned:($orphans|length)}, owners:$owners, orphaned:$orphans}')
[[ "$JSON_OUT" == "1" ]] && echo "$out" || jq -r '.summary' <<<"$out"
