#!/usr/bin/env bash
set -euo pipefail
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SELF_DIR/_lib.sh"

ROOT="."
OUT="${OUTPUT_DIR:-./generated}/.ai/code_facts.json"
JSON_OUT=0
CACHE_FILE="${OUTPUT_DIR:-./generated}/.bootstrap/fact_cache.json"
while [[ $# -gt 0 ]]; do
    case "$1" in
        --root) ROOT="$2"; shift 2 ;;
        --struct|-s) STRUCT_FILE="$2"; shift 2 ;;
        --output|-o) OUT="$2"; shift 2 ;;
        --json) JSON_OUT=1; shift ;;
        --cache) CACHE_FILE="$2"; shift 2 ;;
        --plan) echo "code facts -> $OUT"; exit 0 ;;
        *) echo "未知参数: $1" >&2; exit 64 ;;
    esac
done
ROOT="$(cd "$ROOT" && pwd)"
mkdir -p "$(dirname "$OUT")"
mkdir -p "$(dirname "$CACHE_FILE")"

old_cache="[]"
[[ -f "$CACHE_FILE" ]] && old_cache=$(jq -c '.files // []' "$CACHE_FILE" 2>/dev/null || echo "[]")
files_json=$(jq -r '.modules[]?.components[]?.path // empty' "$STRUCT_FILE" | while read -r p; do
    [[ -f "$ROOT/$p" ]] || continue
    h=$(sha256sum "$ROOT/$p" | awk '{print $1}')
    old=$(jq -r --arg path "$p" --arg hash "$h" '.[] | select(.path==$path and .hash==$hash) | .hash' <<<"$old_cache")
    if [[ -n "$old" ]]; then status=hit; else status=miss; fi
    jq -cn --arg path "$p" --arg hash "$h" --arg status "$status" '{path:$path, hash:$hash, status:$status}'
done | jq -s '.')

interface_json=$(bash "$SELF_DIR/interface_scan.sh" --root "$ROOT" --struct "$STRUCT_FILE" --json || true)
imports_json=$(bash "$SELF_DIR/import_graph_scan.sh" --root "$ROOT" --struct "$STRUCT_FILE" --json || true)
tests_json=$(bash "$SELF_DIR/test_surface_scan.sh" --root "$ROOT" --struct "$STRUCT_FILE" --json || true)
owners_json=$(bash "$SELF_DIR/ownership_resolve.sh" --root "$ROOT" --struct "$STRUCT_FILE" --json || true)

jq -n \
  --arg struct "$STRUCT_FILE" \
  --arg root "$ROOT" \
  --arg cache "$CACHE_FILE" \
  --argjson files "$files_json" \
  --argjson interface "$interface_json" \
  --argjson imports "$imports_json" \
  --argjson tests "$tests_json" \
  --argjson owners "$owners_json" \
  '{
    schema_version:"1.0",
    components: ($interface.components // []),
    imports: ($imports.edges // []),
    tests: ($tests.tests // []),
    owners: ($owners.owners // []),
    cache:{file:$cache, files:$files, hits:($files|map(select(.status=="hit"))|length), misses:($files|map(select(.status=="miss"))|length)},
    provenance:{struct:$struct, root:$root}
  }' > "$OUT"

jq -n --argjson files "$files_json" '{schema_version:"1.0", files:$files}' > "$CACHE_FILE"

if [[ "$JSON_OUT" == "1" ]]; then
    jq . "$OUT"
else
    echo "[OK] code facts: $OUT"
fi
