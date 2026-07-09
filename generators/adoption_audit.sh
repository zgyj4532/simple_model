#!/usr/bin/env bash
# Audit how much of an existing repo is represented by struct component paths.
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
            sed -n '2,80p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
            exit 0
            ;;
        *) echo "未知参数: $1" >&2; exit 64 ;;
    esac
done

command -v jq >/dev/null 2>&1 || { echo "[FAIL] 缺少依赖: jq" >&2; exit 2; }
[[ -d "$ROOT" ]] || { echo "[FAIL] root 不存在: $ROOT" >&2; exit 2; }
[[ -f "$STRUCT_FILE" ]] || { echo "[FAIL] 找不到 struct: $STRUCT_FILE" >&2; exit 2; }

ROOT="$(cd "$ROOT" && pwd)"
TMP_FILES="$(mktemp)"
TMP_MANAGED="$(mktemp)"
trap 'rm -f "$TMP_FILES" "$TMP_MANAGED"' EXIT

find "$ROOT" -maxdepth 3 -type f \
    \( -name '*.py' -o -name '*.ts' -o -name '*.tsx' -o -name '*.js' -o -name '*.jsx' -o -name '*.go' -o -name '*.rs' \) \
    ! -path '*/.git/*' ! -path '*/node_modules/*' ! -path '*/generated/*' \
    | sed "s#^$ROOT/##" \
    | sort -u > "$TMP_FILES"

jq -r '
  .modules[]?.components[]?
  | (.path // .source // empty)
' "$STRUCT_FILE" | sort -u > "$TMP_MANAGED"

TOTAL=$(wc -l < "$TMP_FILES" | tr -d ' ')
MANAGED=0
UNMANAGED=()

while IFS= read -r f; do
    [[ -z "$f" ]] && continue
    if grep -Fxq "$f" "$TMP_MANAGED"; then
        MANAGED=$((MANAGED + 1))
    else
        UNMANAGED+=("$f")
    fi
done < "$TMP_FILES"

UNMANAGED_COUNT=${#UNMANAGED[@]}
if [[ $UNMANAGED_COUNT -eq 0 ]]; then
    UNMANAGED_JSON="[]"
else
    UNMANAGED_JSON="$(printf '%s\n' "${UNMANAGED[@]}" | jq -R -s 'split("\n")[:-1]')"
fi
if [[ "$JSON_OUT" == "1" ]]; then
    jq -n \
      --arg struct "$STRUCT_FILE" \
      --arg root "$ROOT" \
      --argjson total "$TOTAL" \
      --argjson managed "$MANAGED" \
      --argjson unmanaged "$UNMANAGED_COUNT" \
      --argjson files "$UNMANAGED_JSON" \
      '{ok:($unmanaged == 0), struct:$struct, root:$root, total_files:$total, managed_files:$managed, unmanaged_files:$unmanaged, unmanaged:$files}'
else
    echo "============================================================"
    echo " adoption audit"
    echo " struct : $STRUCT_FILE"
    echo " root   : $ROOT"
    echo "============================================================"
    echo " files      : $TOTAL"
    echo " managed    : $MANAGED"
    echo " unmanaged  : $UNMANAGED_COUNT"
    if [[ $UNMANAGED_COUNT -gt 0 ]]; then
        printf '  - %s\n' "${UNMANAGED[@]:0:20}"
        [[ $UNMANAGED_COUNT -gt 20 ]] && echo "  ... $((UNMANAGED_COUNT - 20)) more"
    fi
fi

if [[ "$STRICT" == "1" && $UNMANAGED_COUNT -gt 0 ]]; then
    exit 1
fi
