#!/opt/homebrew/bin/bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT
COUNT="${COUNT:-100}"
mkdir -p "$TMP_DIR/src"
printf '{"schema_version":"3.0","modules":[{"name":"app","description":"app","components":[' > "$TMP_DIR/struct.json"
for i in $(seq 1 "$COUNT"); do
  name="Comp$i"
  file="src/comp$i.ts"
  printf 'export function f%s() { return %s; }\n' "$i" "$i" > "$TMP_DIR/$file"
  [[ $i -gt 1 ]] && printf ',' >> "$TMP_DIR/struct.json"
  printf '{"name":"%s","description":"c","path":"%s","exports":["f%s"]}' "$name" "$file" "$i" >> "$TMP_DIR/struct.json"
done
printf ']}]}\n' >> "$TMP_DIR/struct.json"
start=$(date +%s)
bash "$ROOT_DIR/generators/code_facts.sh" --root "$TMP_DIR" --struct "$TMP_DIR/struct.json" --output "$TMP_DIR/facts1.json" --cache "$TMP_DIR/cache.json" --json >/dev/null
mid=$(date +%s)
bash "$ROOT_DIR/generators/code_facts.sh" --root "$TMP_DIR" --struct "$TMP_DIR/struct.json" --output "$TMP_DIR/facts2.json" --cache "$TMP_DIR/cache.json" --json >/dev/null
end=$(date +%s)
jq -n --argjson files "$COUNT" --argjson cold "$((mid-start))" --argjson warm "$((end-mid))" --argjson hits "$(jq '.cache.hits' "$TMP_DIR/facts2.json")" '{ok:true, files:$files, cold_seconds:$cold, warm_seconds:$warm, warm_hits:$hits}'
