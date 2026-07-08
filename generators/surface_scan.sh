#!/usr/bin/env bash
set -euo pipefail
ROOT="."; STRUCT="${STRUCT_FILE:-./struct.json}"; JSON_OUT=0
while [[ $# -gt 0 ]]; do case "$1" in --root) ROOT="$2"; shift 2;; --struct|-s) STRUCT="$2"; shift 2;; --json) JSON_OUT=1; shift;; *) shift;; esac; done
ROOT="$(cd "$ROOT" && pwd)"
routes=$(find "$ROOT" -type f \( -name '*.py' -o -name '*.ts' -o -name '*.js' \) ! -path '*/node_modules/*' 2>/dev/null | while read -r f; do
  grep -nE '(@app\.route|router\.(get|post|put|delete)|app\.(get|post|put|delete))' "$f" 2>/dev/null | while IFS=: read -r line text; do
    rel="${f#$ROOT/}"; jq -cn --arg path "$rel" --arg line "$line" --arg text "$text" '{kind:"route", path:$path, line:($line|tonumber), text:$text}'
  done
done | jq -s '.')
envs=$(find "$ROOT" -type f \( -name '*.py' -o -name '*.ts' -o -name '*.js' -o -name '*.go' -o -name '*.rs' \) ! -path '*/node_modules/*' 2>/dev/null | while read -r f; do
  grep -nE '(process\.env|os\.environ|std::env|os\.Getenv)' "$f" 2>/dev/null | while IFS=: read -r line text; do
    rel="${f#$ROOT/}"; jq -cn --arg path "$rel" --arg line "$line" --arg text "$text" '{kind:"env", path:$path, line:($line|tonumber), text:$text}'
  done
done | jq -s '.')
out=$(jq -n --argjson routes "$routes" --argjson envs "$envs" '{ok:true, routes:$routes, env:$envs, summary:{routes:($routes|length), env:($envs|length)}}')
[[ "$JSON_OUT" == "1" ]] && echo "$out" || jq -r '.'
