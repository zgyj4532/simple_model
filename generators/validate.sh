#!/usr/bin/env bash
# generators/validate.sh — 硬约束 schema 校验
#
# 校验范围:
#   1. struct.json  ↔ struct.schema.json  (顶层 required + 类型)
#   2. .ai/dev_queue.json  ↔ specs/lifecycle.json
#   3. .ai/context.json    ↔ specs/context-bundle.json
#   4. .bootstrap/state.json ↔ specs/state.json
#   5. generated/ 里每个 .json 都过 jq empty (parse check)
#
# 用法: bash generators/validate.sh   (被 bootstrap.sh --validate 调用)
#       也可作为 pre-commit hook 的子步骤
#
# 退出码: 0 = 全部通过; 1 = 有 error; 2 = 环境错误
set -euo pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SELF_DIR/_lib.sh"

# 默认值：可被环境变量覆盖
STRUCT_FILE="${STRUCT_FILE:-./struct.json}"
SCHEMA_FILE="${SCHEMA_FILE:-./struct.schema.json}"
OUTPUT_DIR="${OUTPUT_DIR:-./generated}"
SPECS_DIR="${SPECS_DIR:-./specs}"

TOTAL=0
PASSED=0
FAILED=0
SKIPPED=0
declare -a ERRORS=()

# 检查一个文件: 必须存在 + 必须 jq empty + 必须满足 schema 里的 required
check_required() {
    local label="$1" file="$2" schema="$3"
    TOTAL=$((TOTAL + 1))
    if [[ ! -f "$file" ]]; then
        echo "  [SKIP] $label ($file 不存在 — 跑 'bootstrap.sh --target all' 先生成)"
        SKIPPED=$((SKIPPED + 1))
        return 0
    fi
    if ! jq empty "$file" 2>/dev/null; then
        echo "  [FAIL] $label: 不是合法 JSON"
        FAILED=$((FAILED + 1))
        ERRORS+=("$label: not valid JSON")
        return 0
    fi
    if [[ -z "$schema" || ! -f "$schema" ]]; then
        echo "  [WARN] $label: 没找到 schema 文件 ($schema)，只做了 parse check"
        PASSED=$((PASSED + 1))
        return 0
    fi
    # 提取 schema 顶层 required 字段，验证 data 都有
    local missing
    missing=$(jq -r --slurpfile s "$schema" --slurpfile d "$file" '
        ($s[0].required // []) as $req |
        $req | map(select(($d[0] | has(.)) | not)) | join(", ")
    ' 2>/dev/null)
    if [[ -n "$missing" ]]; then
        echo "  [FAIL] $label: 缺字段: $missing"
        FAILED=$((FAILED + 1))
        ERRORS+=("$label: missing: $missing")
    else
        echo "  [OK]   $label"
        PASSED=$((PASSED + 1))
    fi
}

# ---------- 启动 ----------
echo "============================================================"
echo " bootstrap validate — hard schema constraints"
echo " struct : $STRUCT_FILE"
echo " schema : $SCHEMA_FILE"
echo " specs  : $SPECS_DIR"
echo " output : $OUTPUT_DIR"
echo "============================================================"
echo ""

# ---------- 1. struct.json 必填字段 ----------
echo "[1/3] struct.json — top-level required fields"
check_required "struct.json::schema_version" "$STRUCT_FILE" "$SCHEMA_FILE"
check_required "struct.json::modules"      "$STRUCT_FILE" "$SCHEMA_FILE"

# 模块/组件名格式校验（PascalCase + 全小写 + snake_case）
if [[ -f "$STRUCT_FILE" ]]; then
    TOTAL=$((TOTAL + 1))
    bad=$(jq -r '
        # 把所有 module + component 拍平成一个数组
        [
            ((.modules // [])[] | {kind: "module", name: .name, module: "<root>"}),
            ((.modules // [])[] as $m | (.components // [])[] | {kind: "component", name: .name, module: $m.name})
        ] |
        # 缺 name 或 name 不合法的都视为非法
        map(select((.name | type) != "string" or (.name | test("^[A-Za-z][A-Za-z0-9_]*$") | not))) |
        map("  - \(.kind) \(.module // "<orphan>")/\(.name // "<missing>")")
        | .[]
    ' "$STRUCT_FILE" 2>/dev/null || true)
    if [[ -n "$bad" ]]; then
        echo "  [FAIL] struct.json: name 格式非法 (要求 ^[A-Za-z][A-Za-z0-9_]*$):"
        echo "$bad"
        FAILED=$((FAILED + 1))
        ERRORS+=("struct.json has names with illegal characters or missing names")
    else
        echo "  [OK]   struct.json: 全部 module/component 名字合规"
        PASSED=$((PASSED + 1))
    fi
fi

# ---------- 2. AI 运行时产物 ----------
echo ""
echo "[2/3] AI runtime artifacts"
check_required ".ai/dev_queue.json"  "$OUTPUT_DIR/.ai/dev_queue.json"  "$SPECS_DIR/lifecycle.json"
check_required ".ai/context.json"    "$OUTPUT_DIR/.ai/context.json"    "$SPECS_DIR/context-bundle.json"
check_required ".ai/state.json"      "$OUTPUT_DIR/.ai/state.json"      "$SPECS_DIR/state.json"
check_required ".bootstrap/state.json" "$OUTPUT_DIR/.bootstrap/state.json" "$SPECS_DIR/state.json"

# ---------- 3. generated/ 里所有 .json parse check ----------
echo ""
echo "[3/3] generated/ — every .json must parse"
if [[ -d "$OUTPUT_DIR" ]]; then
    while IFS= read -r f; do
        [[ -z "$f" ]] && continue
        TOTAL=$((TOTAL + 1))
        if jq empty "$f" 2>/dev/null; then
            echo "  [OK]   ${f#$PWD/}"
            PASSED=$((PASSED + 1))
        else
            echo "  [FAIL] ${f#$PWD/}: 不是合法 JSON"
            FAILED=$((FAILED + 1))
            ERRORS+=("$f: not valid JSON")
        fi
    done < <(find "$OUTPUT_DIR" -type f -name '*.json' 2>/dev/null)
else
    echo "  [SKIP] $OUTPUT_DIR 不存在"
fi

# ---------- 总结 ----------
echo ""
echo "============================================================"
echo " validate summary: total=$TOTAL passed=$PASSED failed=$FAILED skipped=$SKIPPED"
echo "============================================================"

if [[ $FAILED -gt 0 ]]; then
    echo ""
    echo "[FAIL] 有 $FAILED 个 schema 违规:"
    for e in "${ERRORS[@]}"; do
        echo "  - $e"
    done
    echo ""
    echo "修复方法："
    echo "  1. 如果是 struct.json 的字段不在 schema 里 → 改 struct.json 或扩 struct.schema.json"
    echo "  2. 如果是 generated/ 里 .json 不合法 → 检查生成器或重新跑 'bootstrap.sh --target all'"
    echo "  3. 如果是 .ai/*.json → 重新跑 'bootstrap.sh --target all'"
    exit 1
fi

echo "[OK] 全部 schema 校验通过"
exit 0
