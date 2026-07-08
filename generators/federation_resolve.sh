#!/usr/bin/env bash
set -euo pipefail
SPEC="${1:-federation.json}"; JSON_OUT=0
[[ "${2:-}" == "--json" ]] && JSON_OUT=1
[[ -f "$SPEC" ]] || { echo "[FAIL] federation spec not found: $SPEC" >&2; exit 2; }
repos=$(jq -c '.repos' "$SPEC")
resolved=$(jq -c '.[]' <<<"$repos" | while read -r r; do
  name=$(jq -r '.name' <<<"$r"); path=$(jq -r '.path' <<<"$r"); struct=$(jq -r '.struct' <<<"$r")
  file="$path/$struct"
  jq -c --arg repo "$name" --arg root "$path" '{repo:$repo, root:$root, modules:(.modules//[]), components:[.modules[]? as $m | $m.components[]? | {id:($repo + ":" + $m.name + ":" + .name), repo:$repo, module:$m.name, component:.name, path:(.path//"")}]} ' "$file"
done | jq -s '.')
out=$(jq -n --argjson repos "$resolved" '{ok:true, repos:$repos, components:[$repos[].components[]?], summary:{repos:($repos|length), modules:([$repos[].modules|length]|add//0), components:([$repos[].components|length]|add//0)}}')
[[ "$JSON_OUT" == "1" ]] && echo "$out" || jq -r '.summary' <<<"$out"
