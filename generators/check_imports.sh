#!/usr/bin/env bash
# ============================================================================
# generators/check_imports.sh — schema-aware cross-component import check
#
# Validates the `imports` arrays in struct.json against the actual component
# definitions. Catches bugs AI agents (and humans) typically introduce:
#   1. import targets a non-existent component
#   2. import target has no `exports` (so the import is meaningless)
#   3. circular import chains (A -> B -> A)
#   4. imported component has empty work surface (no imports & no todos) but
#      is depended on by others — flag as suspicious (likely orphaned / stub).
#
# Usage:
#   bash generators/check_imports.sh            # human output
#   bash generators/check_imports.sh --json     # JSON output
#
# Exit codes:
#   0  no errors  (warnings may exist)
#   1  one or more errors
#   2  environment error (no struct.json, no jq)
#
# Self-bootstrapping: uses bootstrap_env() from _lib.sh so it can be run from
# any cwd and standalone (same pattern as validate.sh).
# ============================================================================

set -euo pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SELF_DIR/_lib.sh"

# ---------- CLI flags ----------
JSON_OUT=0
while [[ $# -gt 0 ]]; do
    case "$1" in
        --json|-j)     JSON_OUT=1; shift ;;
        -h|--help)
            sed -n '2,/^# ====/p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//; s/^===.*/=/'
            exit 0
            ;;
        *) echo "未知参数: $1" >&2; exit 2 ;;
    esac
done

# ---------- 依赖 ----------
command -v jq >/dev/null 2>&1 || { echo "[FAIL] 缺少依赖: jq" >&2; exit 2; }
[[ -f "$STRUCT_FILE" ]] || { echo "[FAIL] 找不到 $STRUCT_FILE" >&2; exit 2; }
jq empty "$STRUCT_FILE" 2>/dev/null || { echo "[FAIL] $STRUCT_FILE 不是合法 JSON" >&2; exit 2; }

# ---------- 收集数据 ----------
# 把整个 struct 压平成一个 JSON 描述数组（一次 jq 调用）：
#   [{name, module, imports[], exports[], has_todos:bool}, ...]
# $m 这里用 . as $m 显式捕获，避免 (.modules // [])[] | (...) 的混淆
FLAT_JSON=$(jq -c '
    [
        (.modules // [])[]
        | (.components // [])[] as $c
        | (. as $m | {
            name:       $c.name,
            module:     $m.name,
            imports:    ($c.imports    // []),
            exports:    ($c.exports    // []),
            has_todos:  ((($c.todos // []) | length) > 0),
            opt:        ($c.optional // false)
        })
    ]
' "$STRUCT_FILE")

# 全部组件名字（一行一个）
ALL_NAMES=$(jq -r '.[].name' <<<"$FLAT_JSON")
TOTAL=$(jq 'length' <<<"$FLAT_JSON")

# ---------- finding 累加器 ----------
declare -a FINDINGS=()

add_finding() {
    local severity="$1" type="$2" component="$3" message="$4"
    local entry
    entry=$(jq -c -n \
        --arg severity "$severity" \
        --arg type     "$type" \
        --arg comp     "$component" \
        --arg message  "$message" \
        '{severity:$severity, type:$type, component:$comp, message:$message}')
    FINDINGS+=("$entry")
}

# ---------- pre-compute importer -> list ----------
# 行格式: "module/CompName|import_csv"
flat_importers=$(jq -r '.[] | "\(.module)/\(.name)|\(.imports // [] | join(","))"' <<<"$FLAT_JSON")

# 检查一个名字在 ALL_NAMES 中是否存在
name_exists() {
    local n="$1"
    printf '%s\n' "$ALL_NAMES" | grep -Fxq -- "$n"
}

# ---------- 1. missing import targets ----------
while IFS='|' read -r who imports_csv; do
    [[ -z "$who" ]] && continue
    [[ -z "$imports_csv" ]] && continue
    IFS=',' read -ra deps <<<"$imports_csv"
    for d in "${deps[@]}"; do
        [[ -z "$d" ]] && continue
        if ! name_exists "$d"; then
            add_finding "error" "missing_target" "$who" "imports '$d' but no component with that name exists"
        fi
    done
done <<<"$flat_importers"

# ---------- 2. import target has empty exports ----------
while IFS='|' read -r who imports_csv; do
    [[ -z "$who" ]] && continue
    [[ -z "$imports_csv" ]] && continue
    IFS=',' read -ra deps <<<"$imports_csv"
    for d in "${deps[@]}"; do
        [[ -z "$d" ]] && continue
        # 找 target 的 exports（如果存在）
        target_exports=$(jq -r --arg n "$d" '[.[] | select(.name == $n) | .exports | join(",")][0] // ""' <<<"$FLAT_JSON")
        if [[ -z "$target_exports" ]]; then
            # 仅当 d 存在但 exports 为空时才算 warning（缺失由 §1 处理）
            if name_exists "$d"; then
                add_finding "warning" "empty_exports" "$who" "imports '$d' but '$d' declares no exports"
            fi
        fi
    done
done <<<"$flat_importers"

# ---------- 3. circular import chains ----------
# 构建有向图 A -> B 表示 "A imports B"
declare -A ADJ
while IFS='|' read -r who imports_csv; do
    [[ -z "$who" ]] && continue
    name=$(echo "$who" | awk -F'/' '{print $2}')
    deps=""
    if [[ -n "$imports_csv" ]]; then
        IFS=',' read -ra arr <<<"$imports_csv"
        for d in "${arr[@]}"; do
            [[ -z "$d" ]] && continue
            deps+="$d "
        done
    fi
    ADJ[$name]="$deps"
done <<<"$flat_importers"

# DFS 检测环。
# 用一个临时文件保存 on_stack 标记，因为 bash 函数不继承调用方的
# 关联数组。简单做法：把当前 stack 编码成字符串 "||A||B||C||" 传下去，
# 检测一个名字是否在栈里就看 "||NAME||" 是否出现。
detect_cycle() {
    local node="$1" start="$2" stack="$3"
    # 防止重新回到 stack 里已有的节点（DFS 安全）
    case "$stack" in
        *"||$node||"*) return ;;
    esac
    local neighbors="${ADJ[$node]:-}"
    for nb in $neighbors; do
        [[ -z "$nb" ]] && continue
        local new_stack="${stack}${node}||"
        if [[ "$nb" == "$start" ]]; then
            # 找到从 start 回到 start 的环
            # $new_stack 形如 "||start||X||Y||" 表示 start -> X -> Y
            # 我们要展示: start -> X -> Y -> start
            local middle
            middle=$(echo "$new_stack" | sed -e 's/^||//; s/||$//' -e 's/||/ -> /g')
            local cycle_str="$start -> $middle -> $start"
            # 规范化 key：环里的节点去重后排序
            local key
            key=$(echo "$new_stack" | tr '|' '\n' | sed '/^$/d' | sort -u | paste -sd',')
            if [[ -z "${REPORTED_CYCLES[$key]:-}" ]]; then
                REPORTED_CYCLES[$key]=1
                add_finding "error" "circular" "$start" "circular import chain: $cycle_str"
            fi
            return
        fi
        # 防 DFS 爆栈：单次起点最多跳 64 层
        local depth
        depth=$(echo "$new_stack" | tr '|' '\n' | grep -c '.')
        [[ $depth -gt 64 ]] && continue
        detect_cycle "$nb" "$start" "$new_stack"
    done
}

declare -A REPORTED_CYCLES=()
for n in $ALL_NAMES; do
    [[ -z "$n" ]] && continue
    detect_cycle "$n" "$n" ""
done

# ---------- 4. suspicious stubs ----------
# 规则: component 是别人 imports 的目标，但自身没有 exports/imports/todos
#       -> 可能是占位/stub
for name in $ALL_NAMES; do
    [[ -z "$name" ]] && continue
    rec=$(jq -c --arg n "$name" '[.[] | select(.name == $n)][0]' <<<"$FLAT_JSON")
    [[ -z "$rec" || "$rec" == "null" ]] && continue
    imp_count=$(jq '(.imports // []) | length' <<<"$rec")
    exp_count=$(jq '(.exports // []) | length' <<<"$rec")
    has_todos=$(jq '.has_todos // false' <<<"$rec")
    importers=$(jq -r --arg n "$name" '[.[] | select((.imports // []) | index($n)) | .name] | join(",")' <<<"$FLAT_JSON")
    if [[ -z "$importers" ]]; then continue; fi
    if [[ "$exp_count" == "0" && "$imp_count" == "0" && "$has_todos" == "false" ]]; then
        add_finding "warning" "missing_imports" "$name" "depended on by: $importers — has no exports, imports, or todos (possible stub)"
    fi
done

# ---------- 总结计数 ----------
ERRORS=0
WARNINGS=0
for f in "${FINDINGS[@]}"; do
    sev=$(jq -r '.severity' <<<"$f")
    if [[ "$sev" == "error" ]]; then
        ERRORS=$((ERRORS + 1))
    else
        WARNINGS=$((WARNINGS + 1))
    fi
done

# ---------- 输出 ----------
if [[ $JSON_OUT -eq 1 ]]; then
    findings_json="[]"
    if [[ ${#FINDINGS[@]} -gt 0 ]]; then
        findings_json=$(printf '%s\n' "${FINDINGS[@]}" | jq -s '.')
    fi
    jq -n \
        --arg schema_version "1.0" \
        --arg struct "$STRUCT_FILE" \
        --argjson total_components "$TOTAL" \
        --argjson errors "$ERRORS" \
        --argjson warnings "$WARNINGS" \
        --argjson findings "$findings_json" \
        '{
            schema_version: $schema_version,
            struct: $struct,
            total_components: $total_components,
            errors: $errors,
            warnings: $warnings,
            findings: $findings
        }'
    [[ $ERRORS -gt 0 ]] && exit 1 || exit 0
fi

# human 模式
echo "============================================================"
echo " check_imports — schema-aware cross-component import check"
echo " struct: $STRUCT_FILE"
echo " components: $TOTAL"
echo "============================================================"
echo ""

missing_count=0; circular_count=0; empty_exp_count=0; susp_count=0
for f in "${FINDINGS[@]}"; do
    t=$(jq -r '.type' <<<"$f")
    case "$t" in
        missing_target)  missing_count=$((missing_count + 1)) ;;
        circular)        circular_count=$((circular_count + 1)) ;;
        empty_exports)   empty_exp_count=$((empty_exp_count + 1)) ;;
        missing_imports) susp_count=$((susp_count + 1)) ;;
    esac
done

printf '  [INFO] missing_targets    : %d\n' "$missing_count"
printf '  [INFO] circular_chains    : %d\n' "$circular_count"
printf '  [INFO] empty_exports      : %d\n' "$empty_exp_count"
printf '  [INFO] suspicious_stubs   : %d\n' "$susp_count"
echo ""

if [[ ${#FINDINGS[@]} -eq 0 ]]; then
    status_ok "no issues found across $TOTAL components"
else
    for f in "${FINDINGS[@]}"; do
        sev=$(jq -r '.severity' <<<"$f")
        type=$(jq -r '.type'        <<<"$f")
        comp=$(jq -r '.component'   <<<"$f")
        msg=$(jq -r '.message'     <<<"$f")
        if [[ "$sev" == "error" ]]; then
            status_fail "[$type] $comp: $msg"
        else
            status_warn "[$type] $comp: $msg"
        fi
    done
fi

echo ""
echo "============================================================"
echo " check_imports summary: errors=$ERRORS warnings=$WARNINGS"
echo "============================================================"

if [[ $ERRORS -gt 0 ]]; then
    echo ""
    echo "[FAIL] schema import violations detected"
    echo "修复方法:"
    echo "  - missing_target   : add the missing component to struct.json, or fix imports to reference an existing one"
    echo "  - circular         : remove one side of the cycle (use a downstream import or refactor)"
    exit 1
fi
[[ $WARNINGS -gt 0 ]] && echo "" && status_warn "$WARNINGS warning(s) — review before commit"
status_ok "all imports resolve to real components"
exit 0
