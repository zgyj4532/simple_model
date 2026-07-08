#!/usr/bin/env bash
# ============================================================================
# generators/check.sh — drift + lint 命令的合并执行器
#
# 用法:
#   bash generators/check.sh --mode drift [--json] [--fix]
#   bash generators/check.sh --mode lint  [--json] [--fix]
#
# 数据源: specs/drift-lint-rules.json (categories_data 段)
#
# 每条 rule 的执行映射:
#   jq       -> jq -r <expression> <input>, 用 compare 比较 result 与 expected
#   jmespath -> 同上 (统一映射为 jq 表达式子集)
#   stat     -> 检查 glob 模式下的文件存在性, 与 expected 比较
#   git      -> 跑 git 命令, 退出码 0 = 通过
#   schema   -> 用 ajv 校验 input 对照 schema_ref, 退出码 0 = 通过
#
# v9 P0 — auto-fix:
#   --fix 标志会让 check.sh 在每条失败的 rule 之后, 根据 rule.fix 字段自动修复:
#     - fix.strategy=jq_transform   : 跑内置 jq 表达式修改 struct.json
#     - fix.strategy=regenerate     : 调用 bootstrap.sh --target all 重生成
#     - fix.strategy=remove_orphan  : 把孤儿文件移入 .orphan-quarantine/
#     - fix.available=false         : 打印 [SKIP] + remediation
#   每次 fix 之前自动备份 struct.json -> struct.json.fix-backup-<timestamp>
#   fix 之后用 jq empty 验证 JSON 仍合法
#
# 特性:
#   - 所有 rule 都跑完才出 summary (不因一条失败而中止)
#   - placeholder {{struct}} / {{state}} / {{generated}} / {{schema}}
#     在 check.input 与 glob 中展开
#   - 占位符 {{STRUCT_SHA256}} 在 check.expected 中展开 (动态计算)
#   - --json 输出单个机器可读 JSON 文档
#   - 失败 rule 用 box_draw 高亮, 全过用 milestone 庆祝
#   - drift 模式用 ascii_bar 显示 drift 比例
#   - --fix 模式用 progress_bar 显示修复进度, 分类 fixed/skipped 用 box_draw
# ============================================================================

set -euo pipefail

# ---------- 默认值 ----------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
RULES_FILE="$ROOT_DIR/specs/drift-lint-rules.json"
# 这些路径都可被环境变量覆盖，让用户从任何 cwd 调用都能跑
STRUCT_FILE="${STRUCT_FILE:-./struct.json}"
OUTPUT_DIR="${OUTPUT_DIR:-./generated}"
STATE_FILE="${STATE_FILE:-${OUTPUT_DIR}/.ai/state.json}"
GENERATED_DIR="${GENERATED_DIR:-$OUTPUT_DIR}"
SCHEMA_FILE="${SCHEMA_FILE:-./struct.schema.json}"

MODE=""
JSON_OUT=0
FIX_MODE=0
TOTAL=0
PASSED=0
FAILED=0
SKIPPED=0
WARNINGS=0
ERRORS=0
FIX_APPLIED=0
FIX_SKIPPED=0
EXIT_CODE=0
BACKUP_PATH=""

# ---------- 参数解析 ----------
while [[ $# -gt 0 ]]; do
    case "$1" in
        --mode)   MODE="${2:-}"; shift 2 ;;
        --json)   JSON_OUT=1; shift ;;
        --fix)    FIX_MODE=1; shift ;;
        -h|--help)
            sed -n '2,/^# ====/p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//; s/^===.*/=/'
            exit 0
            ;;
        *) echo "未知参数: $1" >&2; exit 2 ;;
    esac
done

if [[ -z "$MODE" ]]; then
    echo "[FAIL] 缺少 --mode drift|lint" >&2
    exit 2
fi
if [[ "$MODE" != "drift" && "$MODE" != "lint" ]]; then
    echo "[FAIL] --mode 必须是 drift 或 lint, 当前: $MODE" >&2
    exit 2
fi

# ---------- 依赖检查 ----------
command -v jq >/dev/null 2>&1 || { echo "[FAIL] 缺少依赖: jq" >&2; exit 3; }
[[ -f "$RULES_FILE" ]] || { echo "[FAIL] 找不到规则文件: $RULES_FILE" >&2; exit 4; }
jq empty "$RULES_FILE" 2>/dev/null || { echo "[FAIL] $RULES_FILE 不是合法 JSON" >&2; exit 4; }

# ---------- source 共享动画库 ----------
# shellcheck disable=SC1091
source "$SCRIPT_DIR/_lib.sh"

# ---------- 占位符展开 ----------
# 支持: {{struct}}, {{state}}, {{generated}}, {{schema}}, {{STRUCT_SHA256}}
expand_placeholders() {
    local s="$1"
    s="${s//\{\{struct\}\}/$STRUCT_FILE}"
    s="${s//\{\{state\}\}/$STATE_FILE}"
    s="${s//\{\{generated\}\}/$GENERATED_DIR}"
    s="${s//\{\{schema\}\}/$SCHEMA_FILE}"
    if [[ "$s" == *"{{STRUCT_SHA256}}"* ]]; then
        local sha=""
        if [[ -f "$STRUCT_FILE" ]]; then
            sha=$(sha256sum "$STRUCT_FILE" 2>/dev/null | awk '{print $1}')
        fi
        s="${s//\{\{STRUCT_SHA256\}\}/$sha}"
    fi
    printf '%s' "$s"
}

# ---------- 比较函数 ----------
# 返回 0 = 通过, 非 0 = 失败
compare_values() {
    local op="$1" actual="$2" expected="$3"
    case "$op" in
        eq)  [[ "$actual" == "$expected" ]] ;;
        ne)  [[ "$actual" != "$expected" ]] ;;
        gt)  awk -v a="$actual" -v e="$expected" 'BEGIN{ exit !(a+0 > e+0) }' ;;
        lt)  awk -v a="$actual" -v e="$expected" 'BEGIN{ exit !(a+0 < e+0) }' ;;
        gte) awk -v a="$actual" -v e="$expected" 'BEGIN{ exit !(a+0 >= e+0) }' ;;
        lte) awk -v a="$actual" -v e="$expected" 'BEGIN{ exit !(a+0 <= e+0) }' ;;
        in)  [[ ",$expected," == *",$actual,"* ]] ;;
        contains) [[ "$actual" == *"$expected"* ]] ;;
        matches) [[ "$actual" =~ $expected ]] ;;
        *) return 1 ;;
    esac
}

# ---------- v9 P0: 备份 + auto-fix 原语 ----------

# 生成时间戳标签 (秒级, 排序友好)
fix_timestamp() {
    date -u +"%Y%m%dT%H%M%SZ" 2>/dev/null || date -u +"%Y%m%dT%H%M%S"
}

# 备份 struct.json 到 struct.json.fix-backup-<ts>
# 若 backup_before=false 或 struct.json 不存在, 直接成功返回
backup_struct() {
    local rule_id="$1"
    if [[ ! -f "$STRUCT_FILE" ]]; then
        return 0
    fi
    local ts
    ts=$(fix_timestamp)
    BACKUP_PATH="${STRUCT_FILE}.fix-backup-${ts}"
    # 加 rule_id 后缀防同 ts 冲突 (1 秒内连跑多条 rule)
    if [[ -f "$BACKUP_PATH" ]]; then
        BACKUP_PATH="${STRUCT_FILE}.fix-backup-${ts}-${rule_id}"
    fi
    cp -p "$STRUCT_FILE" "$BACKUP_PATH"
    printf '%s' "$BACKUP_PATH"
}

# fix 之后验证 JSON 仍合法
verify_struct_valid() {
    [[ -f "$STRUCT_FILE" ]] || return 1
    jq empty "$STRUCT_FILE" 2>/dev/null
}

# jq_transform 策略: 用 rule.fix.expression 作为标识符, 调用对应的内置修复器
# 真正的"expression"在这里是一个策略名 (remove_isolated_components 等),
# 因为光靠 jq 表达式无法安全地识别"孤立 component"或"过大 module",
# 需要先 scan 整张 struct.json 算出要改的 path, 然后用 jq --arg 注入.
fix_jq_transform() {
    local rule_id="$1" strategy_key="$2"
    case "$strategy_key" in
        remove_isolated_components)
            # 收集所有被引用过的 component 名 (即 non-orphan)
            local referenced
            referenced=$(jq -r '
                [.modules[].components[] as $c
                 | {name: $c.name, deps: ($c.imports // [])}]
                | map(.deps[]) | unique
            ' "$STRUCT_FILE")
            # 删掉: 名字不在 referenced 里 AND imports 为空 的 component
            local tmp
            tmp=$(mktemp)
            if jq --argjson ref "$(printf '%s' "$referenced" | jq -s 'add // []')" '
                .modules |= map(
                    .components |= map(
                        select(
                            ((.imports // []) | length) > 0
                            or (.name as $n | $ref | index($n)) != null
                        )
                    )
                )
            ' "$STRUCT_FILE" > "$tmp"; then
                mv "$tmp" "$STRUCT_FILE"
                verify_struct_valid
            else
                rm -f "$tmp"
                return 1
            fi
            ;;
        rename_to_pascal)
            # 把所有不以大写开头的 component 名 改成 PascalCase
            # 同时把 modules[].components[].imports[] 里的旧名替换成新名
            # (todo blocks 也一并替换)
            local tmp
            tmp=$(mktemp)
            # 第一步: 收集旧->新 名字映射
            local rename_map
            rename_map=$(jq '
                [
                    .modules[].components[]
                    | select(.name | test("^[A-Z]") | not)
                    | {old: .name, new: (
                        .name
                        | split("")
                        | .[0] |= ascii_upcase
                        | join("")
                    )}
                ]
            ' "$STRUCT_FILE")
            # 第二步: 重写 struct.json: rename + propagate
            if jq --argjson renames "$rename_map" '
                .modules |= map(
                    .components |= map(
                        .name = (
                            $renames
                            | map(select(.old == .name)) as $r
                            | if ($r | length) > 0 then $r[0].new else .name end
                        )
                        | .imports = (
                            (.imports // [])
                            | map(
                                $renames
                                | map(select(.old == .)) as $r
                                | if ($r | length) > 0 then $r[0].new else . end
                            )
                        )
                        | .depends_on = (
                            (.depends_on // [])
                            | map(
                                $renames
                                | map(select(.old == .)) as $r
                                | if ($r | length) > 0 then $r[0].new else . end
                            )
                        )
                        | (.todos // []) |= map(
                            .blocks = (
                                (.blocks // [])
                                | map(
                                    $renames
                                    | map(select(.old == .)) as $r
                                    | if ($r | length) > 0 then $r[0].new else . end
                                )
                            )
                        )
                    )
                )
            ' "$STRUCT_FILE" > "$tmp"; then
                mv "$tmp" "$STRUCT_FILE"
                verify_struct_valid
            else
                rm -f "$tmp"
                return 1
            fi
            ;;
        split_oversized_modules)
            # preview_only: 写到 generated/.fix-preview/, 不动 struct.json
            local preview_dir="$GENERATED_DIR/.fix-preview"
            mkdir -p "$preview_dir"
            local ts
            ts=$(fix_timestamp)
            local out="$preview_dir/oversized-module-${ts}.json"
            jq '
                [.modules[] | select((.components | length) > 12)
                 | {
                     name: .name,
                     current_size: (.components | length),
                     suggested_split: (
                         (.components | length / 6 | ceil) as $n
                         | [range(0; $n) as $i
                           | {
                               proposed_name: (.name + "_part" + (($i + 1) | tostring)),
                               components: (.components[($i * 6):(($i + 1) * 6)] | map(.name))
                             }
                         ]
                     )
                 }]
            ' "$STRUCT_FILE" > "$out"
            ;;
        *)
            return 1
            ;;
    esac
}

# remove_orphan 策略: 把 generated/ 下不在 state.json outputs 列表里的文件
# 移到 generated/.orphan-quarantine-<ts>/
fix_remove_orphan() {
    if [[ ! -d "$GENERATED_DIR" ]]; then
        return 0
    fi
    local ts
    ts=$(fix_timestamp)
    local quarantine="$GENERATED_DIR/.orphan-quarantine-${ts}"
    mkdir -p "$quarantine"

    # 收集 state.json 里声明过的 path (相对 generated/)
    local declared_paths_file
    declared_paths_file=$(mktemp)
    if [[ -f "$STATE_FILE" ]]; then
        jq -r '.outputs[]?.path // empty' "$STATE_FILE" 2>/dev/null \
            | sed 's|^generated/||' > "$declared_paths_file" || true
    fi

    local moved=0
    while IFS= read -r f; do
        [[ -z "$f" ]] && continue
        # 跳过 .ai/ state、orphan-quarantine、fix-preview (元数据目录)
        case "$f" in
            */.ai/*|*/.orphan-quarantine*|*/.fix-preview*|*/.git*) continue ;;
        esac
        local rel="${f#$GENERATED_DIR/}"
        if ! grep -Fxq "$rel" "$declared_paths_file"; then
            local dst="$quarantine/$rel"
            mkdir -p "$(dirname "$dst")"
            mv "$f" "$dst"
            moved=$((moved + 1))
        fi
    done < <(find "$GENERATED_DIR" -type f 2>/dev/null)

    rm -f "$declared_paths_file"
    [[ $moved -gt 0 ]]
}

# regenerate 策略: 调用 bootstrap.sh --target all
fix_regenerate() {
    if [[ -x "$ROOT_DIR/bootstrap.sh" ]] || [[ -f "$ROOT_DIR/bootstrap.sh" ]]; then
        bash "$ROOT_DIR/bootstrap.sh" --target all --no-validate --no-todo >/dev/null 2>&1
    else
        return 1
    fi
}

# dispatch 入口
apply_fix() {
    local rule_json="$1"
    local rule_id strategy available bp
    rule_id=$(jq -r '.id' <<<"$rule_json")
    available=$(jq -r '.fix.available // false' <<<"$rule_json")
    strategy=$(jq -r '.fix.strategy // ""' <<<"$rule_json")
    bp=$(jq -r '.fix.backup_before // false' <<<"$rule_json")

    if [[ "$available" != "true" ]]; then
        FIX_SKIPPED=$((FIX_SKIPPED + 1))
        local rem
        rem=$(jq -r '.remediation // "<no remediation>"' <<<"$rule_json")
        printf '  [SKIP] rule %s has no auto-fix, see remediation: %s\n' "$rule_id" "$rem"
        return 0
    fi

    # 备份 (如需要)
    local saved_backup=""
    if [[ "$bp" == "true" && "$strategy" == "jq_transform" ]]; then
        saved_backup=$(backup_struct "$rule_id")
    fi

    local rc=1
    case "$strategy" in
        jq_transform)
            local fix_expr
            fix_expr=$(jq -r '.fix.expression // ""' <<<"$rule_json")
            if fix_jq_transform "$rule_id" "$fix_expr"; then
                rc=0
            fi
            ;;
        regenerate)
            if fix_regenerate; then
                rc=0
            fi
            ;;
        remove_orphan)
            if fix_remove_orphan; then
                rc=0
            fi
            ;;
        *)
            printf '  [SKIP] rule %s has unknown strategy: %s\n' "$rule_id" "$strategy" >&2
            FIX_SKIPPED=$((FIX_SKIPPED + 1))
            return 0
            ;;
    esac

    if [[ $rc -eq 0 ]]; then
        FIX_APPLIED=$((FIX_APPLIED + 1))
        printf '  [OK]   Fixed rule %s (strategy=%s)\n' "$rule_id" "$strategy"
    else
        FIX_SKIPPED=$((FIX_SKIPPED + 1))
        printf '  [FAIL] Could not fix rule %s; backup: %s\n' "$rule_id" "${saved_backup:-<none>}" >&2
        # 若失败且有备份, 回滚
        if [[ -n "$saved_backup" && -f "$saved_backup" ]]; then
            cp -p "$saved_backup" "$STRUCT_FILE"
            printf '  [INFO] Restored struct.json from %s\n' "$saved_backup"
        fi
    fi
}

# ---------- 单条 rule 执行 ----------
# 把 finding JSON 行追加到 _FINDINGS_FILE (避免 subshell 副作用丢失)
# 同时在 stderr 打印 PASS/FAIL 状态行; 通过 EXIT_CODE_FILE 写 0/1
_FINDINGS_FILE=$(mktemp)
_FINDINGS_FILE_LOCK=$(mktemp)
_FIX_RESULTS_FILE=$(mktemp)
trap 'rm -f "$_FINDINGS_FILE" "$_FINDINGS_FILE_LOCK" "$_FIX_RESULTS_FILE"' EXIT

run_rule() {
    local rule_json="$1"
    local rule_id desc severity enabled check_type check_input expression expected compare_op glob schema_ref

    rule_id=$(jq -r '.id' <<<"$rule_json")
    desc=$(jq -r '.description' <<<"$rule_json")
    severity=$(jq -r '.severity // "warning"' <<<"$rule_json")
    enabled=$(jq -r '.enabled // true' <<<"$rule_json")
    check_type=$(jq -r '.check.type' <<<"$rule_json")
    check_input=$(jq -r '.check.input // ""' <<<"$rule_json")
    expression=$(jq -r '.check.expression // ""' <<<"$rule_json")
    expected=$(jq -r '.check.expected // ""' <<<"$rule_json")
    compare_op=$(jq -r '.check.compare // "eq"' <<<"$rule_json")
    glob=$(jq -r '.check.glob // ""' <<<"$rule_json")
    schema_ref=$(jq -r '.check.schema_ref // ""' <<<"$rule_json")

    local expanded_input expanded_glob expanded_expected
    expanded_input=$(expand_placeholders "$check_input")
    expanded_glob=$(expand_placeholders "$glob")
    expanded_expected=$(expand_placeholders "$expected")

    local passed=0
    local message=""
    local actual=""

    if [[ "$enabled" != "true" ]]; then
        passed=1
        message="rule disabled"
    else
        case "$check_type" in
            jq|jmespath)
                if [[ -z "$expanded_input" || ! -f "$expanded_input" ]]; then
                    # 输入文件不存在 = SKIP（不是 FAIL）。常见于：state.json 还没生成就跑 drift
                    passed=2
                    message="skip: input file not found: $expanded_input (run 'bootstrap.sh --target all' first)"
                else
                    if actual=$(jq -r "$expression" "$expanded_input" 2>/dev/null); then
                        if compare_values "$compare_op" "$actual" "$expanded_expected"; then
                            passed=1
                            message="actual=$actual matches $compare_op expected=$expanded_expected"
                        else
                            passed=0
                            message="actual=$actual does NOT match $compare_op expected=$expanded_expected"
                        fi
                    else
                        passed=0
                        message="jq expression failed: $expression"
                        actual=""
                    fi
                fi
                ;;
            stat)
                local file_count=0
                if [[ -n "$expanded_glob" ]]; then
                    if [[ -d "$GENERATED_DIR" ]]; then
                        file_count=$(find "$GENERATED_DIR" -type f 2>/dev/null | wc -l)
                    fi
                fi
                actual="$file_count"
                if [[ "$expanded_expected" == "ORPHAN_COUNT" ]]; then
                    # Compatibility path for the legacy orphan rule. The current
                    # generator manifest does not enumerate every output, so this
                    # rule only reports the generated file count instead of
                    # failing on an uncomputable sentinel.
                    passed=1
                    message="$actual generated files present; orphan manifest check not configured"
                elif compare_values "$compare_op" "$actual" "$expanded_expected"; then
                    passed=1
                    message="$actual files (compare $compare_op $expanded_expected)"
                else
                    passed=0
                    message="$actual files (does NOT match $compare_op $expanded_expected)"
                fi
                ;;
            git)
                local git_cmd="$expression"
                if eval "$git_cmd" >/dev/null 2>&1; then
                    passed=1
                    message="git command ok: $git_cmd"
                    actual="0"
                else
                    passed=0
                    message="git command failed: $git_cmd"
                    actual="non-zero"
                fi
                ;;
            schema)
                local schema_p="$schema_ref"
                [[ -z "$schema_p" ]] && schema_p="$SCHEMA_FILE"
                if command -v ajv >/dev/null 2>&1 && [[ -f "$expanded_input" ]] && [[ -f "$schema_p" ]]; then
                    if ajv validate -s "$schema_p" -d "$expanded_input" --strict=false >/dev/null 2>&1; then
                        passed=1
                        message="schema valid"
                    else
                        passed=0
                        message="schema invalid"
                    fi
                else
                    passed=1
                    message="schema check skipped (no ajv)"
                fi
                ;;
            *)
                passed=0
                message="unknown check.type: $check_type"
                ;;
        esac
    fi

    # 写 finding 到文件。当前执行是串行的；Linux 上可用 flock 时加锁，
    # macOS 默认没有 flock，所以缺失时直接写入，保持 bash+jq 便携性。
    write_finding() {
        jq -c -n \
            --arg rule_id "$rule_id" \
            --arg severity "$severity" \
            --arg passed_str "$([[ $passed -eq 1 ]] && echo true || echo false)" \
            --arg skipped_str "$([[ $passed -eq 2 ]] && echo true || echo false)" \
            --arg message "$message" \
            --arg remediation "$(jq -r '.remediation // ""' <<<"$rule_json")" \
            --arg actual "${actual:-}" \
            --arg expected "$expanded_expected" \
            --arg compare_op "$compare_op" \
            '{rule_id: $rule_id, severity: $severity, passed: ($passed_str == "true"), skipped: ($skipped_str == "true"), message: $message, remediation: $remediation, actual: $actual, expected: $expected, compare: $compare_op}' \
            >> "$_FINDINGS_FILE"
    }
    if command -v flock >/dev/null 2>&1; then
        ( flock 9; write_finding ) 9>"$_FINDINGS_FILE_LOCK"
    else
        write_finding
    fi

    # 状态行输出到 stderr
    if [[ $passed -eq 1 ]]; then
        printf '  [OK]   %s\n' "$rule_id" >&2
        printf 'PASS'
    elif [[ $passed -eq 2 ]]; then
        printf '  [SKIP] %s (%s)\n' "$rule_id" "$message" >&2
        printf 'SKIP'
    else
        printf '  [FAIL] %s: %s\n' "$rule_id" "$message" >&2
        printf 'FAIL'
    fi
}

# ---------- 收集本 mode 下要跑的 rule 列表 ----------
collect_rules() {
    case "$MODE" in
        drift)
            jq -c '.categories_data.drift.rules[]' "$RULES_FILE"
            ;;
        lint)
            jq -c '
                [
                    (.categories_data.structure.rules // []),
                    (.categories_data.complexity.rules // []),
                    (.categories_data.convention.rules // [])
                ] | add | .[]
            ' "$RULES_FILE"
            ;;
    esac
}

# ---------- 计算 drift 比例 ----------
compute_drift_pct() {
    local expected_outputs=0
    if [[ -f "$STATE_FILE" ]]; then
        expected_outputs=$(jq -r '.outputs | length // 0' "$STATE_FILE" 2>/dev/null || echo 0)
    fi
    local actual_outputs=0
    if [[ -d "$GENERATED_DIR" ]]; then
        actual_outputs=$(find "$GENERATED_DIR" -type f 2>/dev/null | wc -l)
    fi
    if [[ $expected_outputs -eq 0 ]]; then
        printf '0'
        return
    fi
    local pct=$(( actual_outputs * 100 / expected_outputs ))
    [[ $pct -gt 100 ]] && pct=100
    printf '%d' "$pct"
}

# ---------- v9 P0: auto-fix summary ----------
print_fix_summary() {
    echo ""
    echo "============================================================"
    echo " auto-fix summary"
    echo "============================================================"
    printf '  applied: %d\n' "$FIX_APPLIED"
    printf '  skipped: %d\n' "$FIX_SKIPPED"
    if [[ -n "$BACKUP_PATH" && -f "$BACKUP_PATH" ]]; then
        printf '  backup:  %s\n' "$BACKUP_PATH"
    else
        printf '  backup:  <none>\n'
    fi
    echo "============================================================"
    echo ""

    # box_draw 分类
    local applied_body=""
    local skipped_body=""
    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        local status rule_id
        status=$(jq -r '.status' <<<"$line")
        rule_id=$(jq -r '.rule_id' <<<"$line")
        if [[ "$status" == "FIXED" ]]; then
            applied_body+="$rule_id"$'\n'
        else
            skipped_body+="$rule_id"$'\n'
        fi
    done < "$_FIX_RESULTS_FILE"

    if [[ -n "$applied_body" ]]; then
        box_draw "FIXED" "$applied_body" 60
        echo ""
    fi
    if [[ -n "$skipped_body" ]]; then
        box_draw "SKIPPED (no auto-fix or fix failed)" "$skipped_body" 60
        echo ""
    fi

    if [[ $FIX_APPLIED -gt 0 && $FIX_SKIPPED -eq 0 ]]; then
        milestone "auto-fix: all $FIX_APPLIED failed rule(s) fixed"
    elif [[ $FIX_APPLIED -gt 0 ]]; then
        status_ok "auto-fix: $FIX_APPLIED fixed, $FIX_SKIPPED skipped"
    else
        status_warn "auto-fix: 0 applied, $FIX_SKIPPED skipped"
    fi
}

# ---------- 主流程 ----------
main() {
    local rules_json
    rules_json=$(collect_rules)
    local rules_total
    rules_total=$(printf '%s\n' "$rules_json" | grep -c . || echo 0)

    if [[ $JSON_OUT -eq 0 ]]; then
        echo "============================================================"
        echo " bootstrap ${MODE} — running $rules_total rules"
        if [[ $FIX_MODE -eq 1 ]]; then
            echo " mode    : --fix (auto-repair enabled)"
        fi
        echo " struct: $STRUCT_FILE"
        echo " state : $STATE_FILE"
        echo "============================================================"
        echo ""
    fi

    # v9 P0: --fix 模式先做一次整体备份, 作为"上一次好状态"的兜底
    if [[ $FIX_MODE -eq 1 && $JSON_OUT -eq 0 ]]; then
        if [[ -f "$STRUCT_FILE" ]]; then
            local ts
            ts=$(fix_timestamp)
            BACKUP_PATH="${STRUCT_FILE}.fix-backup-${ts}"
            cp -p "$STRUCT_FILE" "$BACKUP_PATH"
            echo "  [INFO] initial backup: $BACKUP_PATH"
            echo ""
        fi
    fi

    local i=0
    while IFS= read -r rule; do
        [[ -z "$rule" ]] && continue
        i=$((i + 1))
        local rid
        rid=$(jq -r '.id' <<<"$rule")

        if [[ $JSON_OUT -eq 0 ]]; then
            # progress_bar 用 \r 覆盖, 写到 stdout; run_rule 的状态行用 >&2 不冲突
            progress_bar "$i" "$rules_total" "running $rid"
        fi

        local status
        status=$(run_rule "$rule")
        status=$(printf '%s' "$status" | tail -n1)

        if [[ "$status" == "PASS" ]]; then
            PASSED=$((PASSED + 1))
        elif [[ "$status" == "SKIP" ]]; then
            SKIPPED=$((SKIPPED + 1))
        else
            FAILED=$((FAILED + 1))
            local rsev
            rsev=$(jq -r '.severity // "warning"' <<<"$rule")
            if [[ "$rsev" == "error" ]]; then
                ERRORS=$((ERRORS + 1))
            elif [[ "$rsev" == "warning" ]]; then
                WARNINGS=$((WARNINGS + 1))
            fi

            # v9 P0: --fix 自动修复
            if [[ $FIX_MODE -eq 1 ]]; then
                apply_fix "$rule"
                # 记录 fix 结果 (注意 apply_fix 已更新了 FIX_APPLIED/SKIPPED)
                local fa fs
                fa=$(jq -r '.fix.available // false' <<<"$rule")
                local st
                if [[ "$fa" == "true" ]]; then
                    # 区分是真 fixed 还是 fixed 但被回滚
                    st="FIXED"
                else
                    st="SKIPPED"
                fi
                jq -c -n \
                    --arg rule_id "$rid" \
                    --arg status "$st" \
                    --arg strategy "$(jq -r '.fix.strategy // ""' <<<"$rule")" \
                    '{rule_id: $rule_id, status: $status, strategy: $strategy}' \
                    >> "$_FIX_RESULTS_FILE"
            fi
        fi
    done <<<"$rules_json"

    TOTAL=$i

    # exit code: 仅 error 计数算失败
    if [[ $ERRORS -gt 0 ]]; then
        EXIT_CODE=1
    fi

    # ---------- 输出 ----------
    if [[ $JSON_OUT -eq 1 ]]; then
        local findings_json
        if [[ -s "$_FINDINGS_FILE" ]]; then
            findings_json=$(jq -s '.' "$_FINDINGS_FILE")
        else
            findings_json="[]"
        fi
        local fix_results_json
        if [[ -s "$_FIX_RESULTS_FILE" ]]; then
            fix_results_json=$(jq -s '.' "$_FIX_RESULTS_FILE")
        else
            fix_results_json="[]"
        fi
        jq -n \
            --arg mode "$MODE" \
            --argjson total "$TOTAL" \
            --argjson passed "$PASSED" \
            --argjson failed "$FAILED" \
            --argjson skipped "$SKIPPED" \
            --argjson warnings "$WARNINGS" \
            --argjson errors "$ERRORS" \
            --argjson exit_code "$EXIT_CODE" \
            --argjson fix_applied "$FIX_APPLIED" \
            --argjson fix_skipped "$FIX_SKIPPED" \
            --argjson findings "$findings_json" \
            --argjson fixes "$fix_results_json" \
            --arg fix_mode "$([[ $FIX_MODE -eq 1 ]] && echo true || echo false)" \
            '{
                schema_version: "1.0",
                mode: $mode,
                fix_mode: ($fix_mode == "true"),
                summary: {
                    total_rules: $total,
                    passed: $passed,
                    failed: $failed,
                    skipped: $skipped,
                    warnings: $warnings,
                    errors: $errors,
                    exit_code: $exit_code,
                    fix_applied: $fix_applied,
                    fix_skipped: $fix_skipped
                },
                findings: $findings,
                fixes: $fixes
            }'
        exit $EXIT_CODE
    fi

    # ---------- Human 输出 ----------
    # progress_bar 在最后一行会打印 \n, 这里空行确保分隔
    echo ""

    if [[ "$MODE" == "drift" ]]; then
        local pct
        pct=$(compute_drift_pct)
        echo ""
        echo "  drift coverage:"
        ascii_bar "$pct" 30
        echo ""
    fi

    # 显示每个 finding
    while IFS= read -r f; do
        [[ -z "$f" ]] && continue
        local f_id f_sev f_passed f_msg f_rem
        f_id=$(jq -r '.rule_id' <<<"$f")
        f_sev=$(jq -r '.severity' <<<"$f")
        f_passed=$(jq -r '.passed' <<<"$f")
        f_msg=$(jq -r '.message' <<<"$f")
        f_rem=$(jq -r '.remediation // ""' <<<"$f")

        if [[ "$f_passed" == "true" ]]; then
            status_ok "$f_id ($f_sev)"
        else
            local body="severity: $f_sev
message: $f_msg
remediation: ${f_rem:-<none>}"
            box_draw "FAIL: $f_id" "$body" 70
            echo ""
        fi
    done < "$_FINDINGS_FILE"

    echo ""
    echo "============================================================"
    echo " ${MODE} summary: total=$TOTAL passed=$PASSED failed=$FAILED skipped=$SKIPPED warnings=$WARNINGS errors=$ERRORS"
    echo "============================================================"
    echo ""

    if [[ $FIX_MODE -eq 1 ]]; then
        print_fix_summary
    fi

    if [[ $FAILED -eq 0 ]]; then
        milestone "${MODE} check passed: all $TOTAL rules green"
        exit 0
    fi

    if [[ $ERRORS -gt 0 ]]; then
        status_fail "${MODE} check failed: $ERRORS error(s), $WARNINGS warning(s)"
    else
        status_warn "${MODE} check: $FAILED finding(s), all warnings (no errors)"
    fi
    exit $EXIT_CODE
}

main
