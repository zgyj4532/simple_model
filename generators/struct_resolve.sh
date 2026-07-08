#!/usr/bin/env bash
# Resolve a multi-file struct.json into one deterministic struct document.
set -euo pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SELF_DIR/_lib.sh"

ROOT_STRUCT="${STRUCT_FILE:-./struct.json}"
OUT_FILE="${OUTPUT_DIR:-./generated}/.bootstrap/resolved.struct.json"
JSON_OUT=0
PLAN_ONLY="${PLAN_ONLY:-0}"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --struct|-s) ROOT_STRUCT="$2"; shift 2 ;;
        --output|-o) OUT_FILE="$2"; shift 2 ;;
        --json) JSON_OUT=1; shift ;;
        --plan) PLAN_ONLY=1; shift ;;
        -h|--help)
            sed -n '2,80p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
            exit 0
            ;;
        *) echo "未知参数: $1" >&2; exit 64 ;;
    esac
done

command -v jq >/dev/null 2>&1 || { echo "[FAIL] 缺少依赖: jq" >&2; exit 2; }
[[ -f "$ROOT_STRUCT" ]] || { echo "[FAIL] 找不到 struct: $ROOT_STRUCT" >&2; exit 2; }
jq empty "$ROOT_STRUCT" 2>/dev/null || { echo "[FAIL] $ROOT_STRUCT 不是合法 JSON" >&2; exit 2; }

ROOT_STRUCT="$(cd "$(dirname "$ROOT_STRUCT")" && pwd)/$(basename "$ROOT_STRUCT")"
ROOT_DIR="$(cd "$(dirname "$ROOT_STRUCT")" && pwd)"

declare -A SEEN=()
SOURCES=()

safe_include_path() {
    local inc="$1"
    [[ -n "$inc" ]] || return 1
    [[ "$inc" != /* ]] || return 1
    case "$inc" in
        *".."*|*"//"*) return 1 ;;
    esac
    return 0
}

collect_sources() {
    local file="$1"
    local depth="${2:-0}"
    [[ $depth -le 32 ]] || { echo "[FAIL] include 嵌套过深: $file" >&2; exit 1; }
    [[ -f "$file" ]] || { echo "[FAIL] include 文件不存在: $file" >&2; exit 1; }
    jq empty "$file" 2>/dev/null || { echo "[FAIL] include 不是合法 JSON: $file" >&2; exit 1; }

    local canon
    canon="$(cd "$(dirname "$file")" && pwd)/$(basename "$file")"
    [[ -n "${SEEN[$canon]:-}" ]] && return 0
    SEEN[$canon]=1

    local inc
    while IFS= read -r inc; do
        [[ -z "$inc" ]] && continue
        if ! safe_include_path "$inc"; then
            echo "[FAIL] 非法 include 路径: $inc (只允许相对路径，禁止绝对路径和 '..')" >&2
            exit 1
        fi
        collect_sources "$ROOT_DIR/$inc" $((depth + 1))
    done < <(jq -r '.includes[]? // empty' "$canon")

    SOURCES+=("$canon")
}

collect_sources "$ROOT_STRUCT" 0

if [[ "$PLAN_ONLY" == "1" ]]; then
    printf 'resolve struct -> %s\n' "$OUT_FILE"
    printf 'sources:\n'
    printf '  - %s\n' "${SOURCES[@]}"
    exit 0
fi

mkdir -p "$(dirname "$OUT_FILE")"

if ! jq -s '
  def scalar($path; $a; $b):
    if $a == null then $b
    elif $b == null then $a
    elif $a == $b then $a
    else error("struct merge conflict at " + ($path | join(".")))
    end;

  def array_unique($a; $b):
    (($a // []) + ($b // []) | unique);

  def object_merge($path; $a; $b):
    reduce ((($a // {}) | keys_unsorted) + (($b // {}) | keys_unsorted) | unique[]) as $k
      ({};
        .[$k] = (
          if (($a[$k] // null) | type) == "object" and (($b[$k] // null) | type) == "object" then
            object_merge($path + [$k]; $a[$k]; $b[$k])
          else
            scalar($path + [$k]; ($a[$k] // null); ($b[$k] // null))
          end
        )
      );

  def merge_todo($path; $a; $b):
    reduce ((($a // {}) | keys_unsorted) + (($b // {}) | keys_unsorted) | unique[]) as $k
      ({};
        .[$k] = (
          if $k == "blocks" then array_unique($a[$k]; $b[$k])
          else scalar($path + [$k]; ($a[$k] // null); ($b[$k] // null))
          end
        )
      );

  def merge_todos($path; $a; $b):
    reduce ((($a // []) + ($b // []))[]) as $item
      ([];
        ($item.id // "") as $key
        | (map(.id // "") | index($key)) as $idx
        | if ($key == "" or $idx == null) then
            . + [$item]
          else
            .[0:$idx] + [merge_todo($path + [$key]; .[$idx]; $item)] + .[$idx + 1:]
          end
      );

  def merge_component($path; $a; $b):
    reduce ((($a // {}) | keys_unsorted) + (($b // {}) | keys_unsorted) | unique[]) as $k
      ({};
        .[$k] = (
          if ($k | IN("exports", "imports", "owners")) then array_unique($a[$k]; $b[$k])
          elif $k == "todos" then merge_todos($path + [$k]; $a[$k]; $b[$k])
          elif ($k | IN("checks", "adoption")) then object_merge($path + [$k]; $a[$k]; $b[$k])
          else scalar($path + [$k]; ($a[$k] // null); ($b[$k] // null))
          end
        )
      );

  def merge_components($path; $a; $b):
    reduce ((($a // []) + ($b // []))[]) as $item
      ([];
        ($item.name // "") as $key
        | (map(.name // "") | index($key)) as $idx
        | if ($key == "" or $idx == null) then
            . + [$item]
          else
            .[0:$idx] + [merge_component($path + [$key]; .[$idx]; $item)] + .[$idx + 1:]
          end
      );

  def merge_module($path; $a; $b):
    reduce ((($a // {}) | keys_unsorted) + (($b // {}) | keys_unsorted) | unique[]) as $k
      ({};
        .[$k] = (
          if $k == "components" then merge_components($path + [$k]; $a[$k]; $b[$k])
          elif $k == "owners" then array_unique($a[$k]; $b[$k])
          elif ($k | IN("checks", "adoption")) then object_merge($path + [$k]; $a[$k]; $b[$k])
          else scalar($path + [$k]; ($a[$k] // null); ($b[$k] // null))
          end
        )
      );

  def merge_modules($path; $a; $b):
    reduce ((($a // []) + ($b // []))[]) as $item
      ([];
        ($item.name // "") as $key
        | (map(.name // "") | index($key)) as $idx
        | if ($key == "" or $idx == null) then
            . + [$item]
          else
            .[0:$idx] + [merge_module($path + [$key]; .[$idx]; $item)] + .[$idx + 1:]
          end
      );

  def merge_named_top($path; $key_field; $a; $b):
    reduce ((($a // []) + ($b // []))[]) as $item
      ([];
        ($item[$key_field] // "") as $key
        | (map(.[$key_field] // "") | index($key)) as $idx
        | if ($key == "" or $idx == null) then
            . + [$item]
          else
            .[0:$idx] + [object_merge($path + [$key]; .[$idx]; $item)] + .[$idx + 1:]
          end
      );

  def merge_root($a; $b):
    reduce ((($a // {}) | keys_unsorted) + (($b // {}) | keys_unsorted) | unique[]) as $k
      ({};
        if $k == "includes" then .
        else
          .[$k] = (
            if $k == "modules" then merge_modules([$k]; $a[$k]; $b[$k])
            elif $k == "phases" then merge_named_top([$k]; "phase"; $a[$k]; $b[$k])
            elif $k == "cross_cutting" then merge_named_top([$k]; "name"; $a[$k]; $b[$k])
            elif $k == "invariants" then merge_named_top([$k]; "name"; $a[$k]; $b[$k])
            elif $k == "conventions" then object_merge([$k]; $a[$k]; $b[$k])
            else scalar([$k]; ($a[$k] // null); ($b[$k] // null))
            end
          )
        end
      );

  reduce .[] as $doc ({}; merge_root(.; $doc))
  | . + {
      _resolved: {
        resolver: "generators/struct_resolve.sh",
        source_count: ($sources | length),
        sources: $sources
      }
    }
' --argjson sources "$(printf '%s\n' "${SOURCES[@]}" | jq -R -s 'split("\n")[:-1]')" "${SOURCES[@]}" > "$OUT_FILE"; then
    echo "[FAIL] struct include 合并失败" >&2
    rm -f "$OUT_FILE"
    exit 1
fi

if [[ "$JSON_OUT" == "1" ]]; then
    jq -n \
      --arg output "$OUT_FILE" \
      --argjson sources "$(printf '%s\n' "${SOURCES[@]}" | jq -R -s 'split("\n")[:-1]')" \
      '{ok:true, output:$output, source_count:($sources|length), sources:$sources}'
else
    echo "[OK] resolved struct: $OUT_FILE"
    echo "     sources: ${#SOURCES[@]}"
fi
