#!/usr/bin/env bash
# Generate a conservative struct fragment from an existing repository tree.
set -euo pipefail

ROOT="."
OUT_FILE=""
JSON_OUT=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        --root) ROOT="$2"; shift 2 ;;
        --output|-o) OUT_FILE="$2"; shift 2 ;;
        --json) JSON_OUT=1; shift ;;
        -h|--help)
            sed -n '2,80p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
            exit 0
            ;;
        *) echo "未知参数: $1" >&2; exit 64 ;;
    esac
done

command -v jq >/dev/null 2>&1 || { echo "[FAIL] 缺少依赖: jq" >&2; exit 2; }
[[ -d "$ROOT" ]] || { echo "[FAIL] root 不存在: $ROOT" >&2; exit 2; }

ROOT="$(cd "$ROOT" && pwd)"
[[ -z "$OUT_FILE" ]] && OUT_FILE="$ROOT/struct.ingested.json"

TMP_PATHS="$(mktemp)"
TMP="$(mktemp)"
trap 'rm -f "$TMP_PATHS" "$TMP"' EXIT

export LC_ALL=C

json_array_from_lines() {
    if [[ $# -eq 0 ]]; then
        jq -n -c '[]'
    else
        printf '%s\n' "$@" | sed '/^$/d' | sort -u | jq -R -s -c 'split("\n")[:-1]'
    fi
}

scan_file_exports() {
    local f="$1"
    case "$f" in
        *.py)
            grep -E '^(class|def|async def)[[:space:]]+[A-Za-z_][A-Za-z0-9_]*' "$f" 2>/dev/null \
                | sed -E 's/^(class|def|async def)[[:space:]]+([A-Za-z_][A-Za-z0-9_]*).*/\2/' \
                | sort -u
            ;;
        *.ts|*.tsx|*.js|*.jsx)
            {
                grep -E '^export[[:space:]]+(async[[:space:]]+)?(class|function|const|let|var|interface|type|enum)[[:space:]]+[A-Za-z_][A-Za-z0-9_]*' "$f" 2>/dev/null \
                    | sed -E 's/^export[[:space:]]+(async[[:space:]]+)?(class|function|const|let|var|interface|type|enum)[[:space:]]+([A-Za-z_][A-Za-z0-9_]*).*/\3/'
                grep -E '^export[[:space:]]*\{[^}]+\}' "$f" 2>/dev/null \
                    | sed -E 's/^export[[:space:]]*\{//; s/\}.*$//; s/,/\n/g; s/[[:space:]]+as[[:space:]]+[A-Za-z_][A-Za-z0-9_]*//g; s/^[[:space:]]+//; s/[[:space:]]+$//'
            } | grep -E '^[A-Za-z_][A-Za-z0-9_]*$' | sort -u
            ;;
        *.go)
            {
                grep -E '^(func|type|const|var)[[:space:]]+[A-Z][A-Za-z0-9_]*' "$f" 2>/dev/null \
                    | sed -E 's/^(func|type|const|var)[[:space:]]+([A-Z][A-Za-z0-9_]*).*/\2/'
                grep -E '^func[[:space:]]+\([^)]*\)[[:space:]]+[A-Z][A-Za-z0-9_]*' "$f" 2>/dev/null \
                    | sed -E 's/^func[[:space:]]+\([^)]*\)[[:space:]]+([A-Z][A-Za-z0-9_]*).*/\1/'
            } | sort -u
            ;;
        *.rs)
            grep -E '^[[:space:]]*pub[[:space:]]+(fn|struct|enum|trait|const|static)[[:space:]]+[A-Za-z_][A-Za-z0-9_]*' "$f" 2>/dev/null \
                | sed -E 's/^[[:space:]]*pub[[:space:]]+(fn|struct|enum|trait|const|static)[[:space:]]+([A-Za-z_][A-Za-z0-9_]*).*/\2/' \
                | sort -u
            ;;
    esac
}

find "$ROOT" -maxdepth 3 -type f \
    \( -name '*.py' -o -name '*.ts' -o -name '*.tsx' -o -name '*.js' -o -name '*.jsx' -o -name '*.go' -o -name '*.rs' \) \
    ! -path '*/.git/*' ! -path '*/node_modules/*' ! -path '*/generated/*' \
    | sed "s#^$ROOT/##" \
    | awk -F/ '
        NF == 1 { print ".\t" $0; next }
        NF > 1 { print $1 "\t" $0 }
    ' \
    | sort -u > "$TMP_PATHS"

while IFS=$'\t' read -r module path; do
    [[ -z "$path" ]] && continue
    mapfile -t exports < <(scan_file_exports "$ROOT/$path")
    exports_json=$(json_array_from_lines "${exports[@]}")
    printf '%s\t%s\t%s\n' "$module" "$path" "$exports_json"
done < "$TMP_PATHS" > "$TMP"

jq -Rn '
  def comp_name($path):
    ($path | split("/")[-1] | sub("\\.[^.]+$"; "") | gsub("[^A-Za-z0-9_]"; "_"))
    | split("_")
    | map(select(length > 0) | (.[0:1] | ascii_upcase) + .[1:])
    | join("");

  [inputs | split("\t") | {module: .[0], path: .[1], exports: (.[2] | fromjson)}] as $rows
  | {
      schema_version: "3.0",
      description: "Generated adoption draft. Review names, imports, exports, todos, and ownership before using as source of truth.",
      modules: (
        $rows
        | group_by(.module)
        | map({
            name: (.[0].module | if . == "." then "root" else gsub("[^A-Za-z0-9_]"; "_") end),
            description: "Ingested from existing repository files.",
            adoption: {mode: "draft", managed: false},
            components: map({
              name: comp_name(.path),
              description: "Ingested component draft.",
              path: .path,
              imports: [],
              exports: .exports,
              todos: []
            })
          })
      )
    }
' "$TMP" > "$OUT_FILE"

if [[ "$JSON_OUT" == "1" ]]; then
    jq -n --arg output "$OUT_FILE" --argjson modules "$(jq '.modules|length' "$OUT_FILE")" --argjson components "$(jq '[.modules[].components|length]|add // 0' "$OUT_FILE")" \
      '{ok:true, output:$output, modules:$modules, components:$components}'
else
    echo "[OK] ingested repo draft: $OUT_FILE"
    echo "     modules: $(jq '.modules|length' "$OUT_FILE")"
    echo "     components: $(jq '[.modules[].components|length]|add // 0' "$OUT_FILE")"
fi
