#!/usr/bin/env bash
set -euo pipefail
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SELF_DIR/_lib.sh"

ROOT="."
JSON_OUT=0
STRICT=0
while [[ $# -gt 0 ]]; do
    case "$1" in
        --root) ROOT="$2"; shift 2 ;;
        --struct|-s) STRUCT_FILE="$2"; shift 2 ;;
        --json) JSON_OUT=1; shift ;;
        --strict) STRICT=1; shift ;;
        *) echo "未知参数: $1" >&2; exit 64 ;;
    esac
done
ROOT="$(cd "$ROOT" && pwd)"

components=$(jq -c '[.modules[]? as $m | $m.components[]? | {module:$m.name, component:.name, path:(.path//""), declared:(.imports//[])}]' "$STRUCT_FILE")
edges_tmp="$(mktemp)"
trap 'rm -f "$edges_tmp"' EXIT

jq -r '.[] | select(.path != "") | [.component,.path] | @tsv' <<<"$components" | while IFS=$'\t' read -r comp rel; do
    full="$ROOT/$rel"
    [[ -f "$full" ]] || continue
    {
    case "$full" in
        *.py)
            grep -E '^(from|import)[[:space:]]+' "$full" 2>/dev/null | sed -E 's/^(from|import)[[:space:]]+([A-Za-z0-9_\.]+).*/\2/' || true ;;
        *.ts|*.tsx|*.js|*.jsx)
            grep -E '^(import|export).*from[[:space:]]+["'\'']' "$full" 2>/dev/null | sed -E 's/.*from[[:space:]]+["'\'']([^"'\'']+)["'\''].*/\1/' || true ;;
        *.go)
            grep -E '^[[:space:]]*"[A-Za-z0-9_./-]+"' "$full" 2>/dev/null | sed -E 's/^[[:space:]]*"([^"]+)".*/\1/' || true ;;
        *.rs)
            grep -E '^[[:space:]]*(use|mod)[[:space:]]+' "$full" 2>/dev/null | sed -E 's/^[[:space:]]*(use|mod)[[:space:]]+([^;]+).*/\2/' || true ;;
    esac
    } | while IFS= read -r imp; do
        [[ -z "$imp" ]] && continue
        target=$(jq -r --arg imp "$imp" '
          def norm: ascii_downcase | gsub("[^a-z0-9]"; "");
          [.[] | select(.path != "" and (
            (($imp | split("/")[-1] | norm) == (.path | split("/")[-1] | sub("\\.[^.]+$"; "") | norm)) or
            (($imp | split("/")[-1] | norm) == (.component | norm))
          )) | .component][0] // empty
        ' <<<"$components")
        [[ -n "$target" && "$target" != "$comp" ]] && printf '%s\t%s\t%s\n' "$comp" "$target" "$imp" >> "$edges_tmp"
    done
done

edges_json=$(awk -F'\t' 'NF>=3{print}' "$edges_tmp" | jq -R -s '
  split("\n")[:-1] | map(split("\t") | {from:.[0], to:.[1], import:.[2]}) | unique
')
findings=$(jq -n --argjson comps "$components" --argjson edges "$edges_json" '
  [$edges[] as $e
   | ($comps[] | select(.component == $e.from)) as $c
   | select(($c.declared | index($e.to)) == null)
   | {severity:"warning", type:"undeclared_import", component:$e.from, target:$e.to, message:"code imports component not declared in struct"}]
')
errors=0
warnings=$(jq 'length' <<<"$findings")
out=$(jq -n --arg struct "$STRUCT_FILE" --arg root "$ROOT" --argjson edges "$edges_json" --argjson findings "$findings" --argjson warnings "$warnings" --argjson errors "$errors" \
  '{ok:($errors==0), struct:$struct, root:$root, summary:{edges:($edges|length), warnings:$warnings, errors:$errors}, edges:$edges, findings:$findings}')
if [[ "$JSON_OUT" == "1" ]]; then echo "$out"; else jq -r '.summary' <<<"$out"; fi
[[ "$STRICT" == "1" && "$warnings" -gt 0 ]] && exit 1
exit 0
