#!/usr/bin/env bash
# Scan component paths and compare discovered public interfaces with struct exports.
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
        -h|--help)
            sed -n '2,90p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
            exit 0
            ;;
        *) echo "未知参数: $1" >&2; exit 64 ;;
    esac
done

command -v jq >/dev/null 2>&1 || { echo "[FAIL] 缺少依赖: jq" >&2; exit 2; }
[[ -d "$ROOT" ]] || { echo "[FAIL] root 不存在: $ROOT" >&2; exit 2; }
[[ -f "$STRUCT_FILE" ]] || { echo "[FAIL] 找不到 struct: $STRUCT_FILE" >&2; exit 2; }
jq empty "$STRUCT_FILE" 2>/dev/null || { echo "[FAIL] $STRUCT_FILE 不是合法 JSON" >&2; exit 2; }

ROOT="$(cd "$ROOT" && pwd)"
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
    if command -v python3 >/dev/null 2>&1 && [[ -f "$SELF_DIR/interface_parser.inc" ]]; then
        if python3 "$SELF_DIR/interface_parser.inc" "$f"; then
            return 0
        fi
    fi
    case "$f" in
        *.py)
            {
                grep -nE '^(class|def|async def)[[:space:]]+[A-Za-z_][A-Za-z0-9_]*' "$f" 2>/dev/null \
                    | sed -E 's/^([0-9]+):(class|def|async def)[[:space:]]+([A-Za-z_][A-Za-z0-9_]*)(.*)$/\1\t\2\t\3\t\2 \3\4/'
            } | sort -u
            ;;
        *.ts|*.tsx|*.js|*.jsx)
            {
                grep -nE '^export[[:space:]]+(async[[:space:]]+)?(class|function|const|let|var|interface|type|enum)[[:space:]]+[A-Za-z_][A-Za-z0-9_]*' "$f" 2>/dev/null \
                    | sed -E 's/^([0-9]+):export[[:space:]]+(async[[:space:]]+)?(class|function|const|let|var|interface|type|enum)[[:space:]]+([A-Za-z_][A-Za-z0-9_]*)(.*)$/\1\t\3\t\4\texport \3 \4\5/' || true
                grep -nE '^export[[:space:]]*\{[^}]+\}' "$f" 2>/dev/null \
                    | while IFS=: read -r line text; do
                        echo "$text" | sed -E 's/^export[[:space:]]*\{//; s/\}.*$//; s/,/\n/g; s/[[:space:]]+as[[:space:]]+[A-Za-z_][A-Za-z0-9_]*//g; s/^[[:space:]]+//; s/[[:space:]]+$//' |
                        awk -v l="$line" 'NF{print l "\texport\t" $0 "\texport {" $0 "}"}'
                    done || true
            } | awk -F'\t' '$3 ~ /^[A-Za-z_][A-Za-z0-9_]*$/' | sort -u
            ;;
        *.go)
            {
                grep -nE '^(func|type|const|var)[[:space:]]+[A-Z][A-Za-z0-9_]*' "$f" 2>/dev/null \
                    | sed -E 's/^([0-9]+):(func|type|const|var)[[:space:]]+([A-Z][A-Za-z0-9_]*)(.*)$/\1\t\2\t\3\t\2 \3\4/'
                grep -nE '^func[[:space:]]+\([^)]*\)[[:space:]]+[A-Z][A-Za-z0-9_]*' "$f" 2>/dev/null \
                    | sed -E 's/^([0-9]+):func[[:space:]]+\([^)]*\)[[:space:]]+([A-Z][A-Za-z0-9_]*)(.*)$/\1\tmethod\t\2\tfunc \2\3/'
            } | sort -u
            ;;
        *.rs)
            grep -nE '^[[:space:]]*pub[[:space:]]+(fn|struct|enum|trait|const|static)[[:space:]]+[A-Za-z_][A-Za-z0-9_]*' "$f" 2>/dev/null \
                | sed -E 's/^([0-9]+):[[:space:]]*pub[[:space:]]+(fn|struct|enum|trait|const|static)[[:space:]]+([A-Za-z_][A-Za-z0-9_]*)(.*)$/\1\t\2\t\3\tpub \2 \3\4/' \
                | sort -u
            ;;
    esac
}

scan_path_exports() {
    local rel="$1"
    local full="$ROOT/$rel"
    if [[ -f "$full" ]]; then
        scan_file_exports "$full"
    elif [[ -d "$full" ]]; then
        while IFS= read -r f; do
            scan_file_exports "$f"
        done < <(find "$full" -type f \( -name '*.py' -o -name '*.ts' -o -name '*.tsx' -o -name '*.js' -o -name '*.jsx' -o -name '*.go' -o -name '*.rs' \) | sort)
    fi
}

COMPONENTS=()
while IFS= read -r c; do
    COMPONENTS+=("$c")
done < <(jq -c '
  .modules[]? as $m
  | $m.components[]?
  | {
      module: $m.name,
      component: .name,
      path: (.path // ""),
      declared_exports: (.exports // [])
    }
' "$STRUCT_FILE")

REPORTS=()
FINDINGS=()
MISSING_COUNT=0
UNDECLARED_COUNT=0
PATH_MISSING_COUNT=0
SCANNED=0

for comp in "${COMPONENTS[@]}"; do
    module=$(jq -r '.module' <<<"$comp")
    component=$(jq -r '.component' <<<"$comp")
    rel=$(jq -r '.path' <<<"$comp")
    declared_json=$(jq -c '.declared_exports' <<<"$comp")
    interfaces_json="[]"

    if [[ -z "$rel" || ! -e "$ROOT/$rel" ]]; then
        PATH_MISSING_COUNT=$((PATH_MISSING_COUNT + 1))
        finding=$(jq -n --arg module "$module" --arg component "$component" --arg path "$rel" \
            '{severity:"warning", type:"missing_path", module:$module, component:$component, path:$path, message:"component has no readable path"}')
        FINDINGS+=("$finding")
        discovered_json="[]"
    else
        interfaces_json=$(scan_path_exports "$rel" | awk -F'\t' -v comp="$component" -v path="$rel" '
          NF>=4 {gsub(/^[ \t]+|[ \t]+$/, "", $3); print $1 "\t" $2 "\t" $3 "\t" $4 "\t" ($5 == "" ? "regex_fallback" : $5)}
        ' | while IFS=$'\t' read -r line kind name sig parser; do
            hash=$(printf '%s' "$sig" | sha256sum | awk '{print $1}')
            jq -cn --arg name "$name" --arg kind "$kind" --arg signature "$sig" --arg path "$rel" --arg parser "${parser:-regex_fallback}" --argjson line "${line:-0}" --arg hash "$hash" \
              '{name:$name, kind:$kind, visibility:"public", signature:$signature, path:$path, line:$line, hash:$hash, parser:$parser}'
        done | jq -s '.')
        discovered_json=$(jq -c '[.[].name] | unique' <<<"$interfaces_json")
        SCANNED=$((SCANNED + 1))
    fi

    missing_json=$(jq -n --argjson declared "$declared_json" --argjson discovered "$discovered_json" \
        '$declared | map(. as $sym | select(($discovered | index($sym)) == null))')
    undeclared_json=$(jq -n --argjson declared "$declared_json" --argjson discovered "$discovered_json" \
        '$discovered | map(. as $sym | select(($declared | index($sym)) == null))')
    missing_len=$(jq 'length' <<<"$missing_json")
    undeclared_len=$(jq 'length' <<<"$undeclared_json")
    MISSING_COUNT=$((MISSING_COUNT + missing_len))
    UNDECLARED_COUNT=$((UNDECLARED_COUNT + undeclared_len))

    if [[ $missing_len -gt 0 ]]; then
        finding=$(jq -n --arg module "$module" --arg component "$component" --argjson symbols "$missing_json" \
            '{severity:"error", type:"missing_declared_exports", module:$module, component:$component, symbols:$symbols, message:"struct declares exports not found in code"}')
        FINDINGS+=("$finding")
    fi
    if [[ $undeclared_len -gt 0 ]]; then
        finding=$(jq -n --arg module "$module" --arg component "$component" --argjson symbols "$undeclared_json" \
            '{severity:"warning", type:"undeclared_exports", module:$module, component:$component, symbols:$symbols, message:"code exposes public symbols missing from struct exports"}')
        FINDINGS+=("$finding")
    fi

    REPORTS+=("$(jq -n \
        --arg module "$module" \
        --arg component "$component" \
        --arg path "$rel" \
        --argjson declared_exports "$declared_json" \
        --argjson discovered_exports "$discovered_json" \
        --argjson interfaces "${interfaces_json:-[]}" \
        --argjson missing_exports "$missing_json" \
        --argjson undeclared_exports "$undeclared_json" \
        '{module:$module, component:$component, path:$path, declared_exports:$declared_exports, discovered_exports:$discovered_exports, interfaces:$interfaces, interface_hash:($interfaces|map(.hash)|join(":")), missing_exports:$missing_exports, undeclared_exports:$undeclared_exports}')")
done

components_json="[]"
findings_json="[]"
[[ ${#REPORTS[@]} -gt 0 ]] && components_json=$(printf '%s\n' "${REPORTS[@]}" | jq -s '.')
[[ ${#FINDINGS[@]} -gt 0 ]] && findings_json=$(printf '%s\n' "${FINDINGS[@]}" | jq -s '.')

if [[ "$JSON_OUT" == "1" ]]; then
    jq -n \
      --arg struct "$STRUCT_FILE" \
      --arg root "$ROOT" \
      --argjson total_components "${#COMPONENTS[@]}" \
      --argjson components_scanned "$SCANNED" \
      --argjson missing_exports "$MISSING_COUNT" \
      --argjson undeclared_exports "$UNDECLARED_COUNT" \
      --argjson missing_paths "$PATH_MISSING_COUNT" \
      --argjson components "$components_json" \
      --argjson findings "$findings_json" \
      '{
        ok: ($missing_exports == 0 and $missing_paths == 0),
        struct:$struct,
        root:$root,
        summary:{total_components:$total_components, components_scanned:$components_scanned, missing_exports:$missing_exports, undeclared_exports:$undeclared_exports, missing_paths:$missing_paths},
        components:$components,
        findings:$findings
      }'
else
    echo "============================================================"
    echo " interface scan"
    echo " struct : $STRUCT_FILE"
    echo " root   : $ROOT"
    echo "============================================================"
    echo " components        : ${#COMPONENTS[@]}"
    echo " scanned           : $SCANNED"
    echo " missing exports   : $MISSING_COUNT"
    echo " undeclared exports: $UNDECLARED_COUNT"
    echo " missing paths     : $PATH_MISSING_COUNT"
    if [[ ${#FINDINGS[@]} -gt 0 ]]; then
        printf '%s\n' "${FINDINGS[@]}" | jq -r '.[]? // empty' >/dev/null 2>&1 || true
        printf '%s\n' "${FINDINGS[@]}" | jq -r '"  - [" + .severity + "] " + .module + "/" + .component + " " + .type + ": " + (.symbols // [] | join(","))'
    fi
fi

if [[ "$STRICT" == "1" ]] && [[ $MISSING_COUNT -gt 0 || $PATH_MISSING_COUNT -gt 0 || $UNDECLARED_COUNT -gt 0 ]]; then
    exit 1
fi
if [[ $MISSING_COUNT -gt 0 || $PATH_MISSING_COUNT -gt 0 ]]; then
    exit 1
fi
