#!/usr/bin/env bash
# ============================================================================
# bootstrap.sh — 通用项目架构 → AI 上下文 / 代码骨架 / 可视化
#
# 零外部依赖: bash >=4, jq（schema 可选用 ajv 校验）
#
# 用法:
#   ./bootstrap.sh                              # 交互式
#   ./bootstrap.sh --target agents              # 仅 AI 上下文
#   ./bootstrap.sh --target python,viz          # Python 代码 + 架构图
#   ./bootstrap.sh --target all                 # 所有生成器
#   ./bootstrap.sh --plan --target queue        # dry-run: 看会生成什么
#   ./bootstrap.sh --include data,model         # 只处理这些 module
#   ./bootstrap.sh --force                      # 强制全量重建（忽略增量缓存）
#   ./bootstrap.sh --from-url <url>             # 远程拉模板（git/https/file）
#   ./bootstrap.sh --validate                   # 硬约束 schema 校验（无生成）
#   ./bootstrap.sh --check-imports              # 检查 struct.json imports 链
#   ./bootstrap.sh --check-impl                 # 检查 generated/ 与 schema 对齐
#   ./bootstrap.sh --check-all                  # 同时跑 --check-imports + --check-impl
#   ./bootstrap.sh --migrate 3.0 3.1            # schema 迁移: 3.0 -> 3.1
#   ./bootstrap.sh --migrate 3.0 3.1 --dry-run  # 预览迁移结果不写盘
#   ./bootstrap.sh --validate                   # 硬约束 schema 校验
# ============================================================================

set -euo pipefail

# ---------- 默认值 ----------
STRUCT_FILE="./struct.json"
SCHEMA_FILE="./struct.schema.json"
OUTPUT_DIR="./generated"
TARGETS=""
SKIP_TODO=0
SKIP_VALIDATE=0
PLAN_ONLY=0
INCLUDE_MODULES=""
EXCLUDE_MODULES=""
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GENERATORS_DIR="${SCRIPT_DIR}/generators"

# init 子命令专用变量（被 --init / --template / --from / --from-url 触发）
INIT_CMD=0
INIT_TEMPLATE=""
INIT_FROM=""
INIT_FROM_URL=""

# migrate 子命令专用变量（被 --migrate <from> <to> 触发）
MIGRATE_CMD=0
MIGRATE_FROM=""
MIGRATE_TO=""
# chimeric 子命令专用变量（被 --chimeric <sub> 触发）
CHIMERIC_CMD=0
CHIMERIC_STATUS=0
CHIMERIC_SUB=""
CHIMERIC_VERIFY_ARGS=()
MIGRATE_OUTPUT=""
MIGRATE_DRY_RUN=0

# orchestrate 子命令专用变量（被 --orchestrate <sub> 触发；Wave 5 demo 集成）
ORCHESTRATE_CMD=0
ORCHESTRATE_SUB=""
ORCHESTRATE_ARGS=()

# AI / viz 类生成器（不需要被 -t 解析成代码语言）
AI_TARGETS=(agents context queue viz claude)

# ---------- 帮助 ----------
usage() {
    sed -n '2,/^# ====/p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//; s/^===.*/=/'
    exit "${1:-0}"
}

# ---------- 参数解析 ----------
while [[ $# -gt 0 ]]; do
    case "$1" in
        -s|--struct)    STRUCT_FILE="$2"; shift 2 ;;
        -S|--schema)    SCHEMA_FILE="$2"; shift 2 ;;
        -o|--output)    OUTPUT_DIR="$2"; shift 2 ;;
        -t|--target)    TARGETS="$2"; shift 2 ;;
        --include)      INCLUDE_MODULES="$2"; shift 2 ;;
        --exclude)      EXCLUDE_MODULES="$2"; shift 2 ;;
        --no-todo)      SKIP_TODO=1; shift ;;
        --no-validate)  SKIP_VALIDATE=1; shift ;;
        --force)        FORCE_REGEN=1; export FORCE_REGEN=1; shift ;;
        --drift)        DRIFT_CMD=1; shift ;;
        --lint)         LINT_CMD=1; shift ;;
        --fix)          FIX_MODE=1; shift ;;
        --explain)      EXPLAIN_COMP="$2"; shift 2 ;;
        --explain-json) EXPLAIN_COMP="$2"; EXPLAIN_JSON=1; shift 2 ;;
        --json)         JSON_OUT=1; shift ;;
        --plan)         PLAN_ONLY=1; shift ;;
        --init)         INIT_CMD=1; shift ;;
        --template)     INIT_TEMPLATE="$2"; shift 2 ;;
        --from)         INIT_FROM="$2"; shift 2 ;;
        --from-url)     INIT_FROM_URL="$2"; shift 2 ;;
        --status)       STATUS_CMD=1; shift ;;
        --next)         NEXT_CMD=1; shift ;;
        --claim)        CLAIM_ID="$2"; shift 2 ;;
        --complete)     COMPLETE_ID="$2"; shift 2 ;;
        --reset)        RESET_ID="$2"; shift 2 ;;
        --validate)     VALIDATE_CMD=1; shift ;;
        --check-imports) CHECK_IMPORTS_CMD=1; shift ;;
        --check-impl)    CHECK_IMPL_CMD=1; shift ;;
        --check-all)     CHECK_IMPORTS_CMD=1; CHECK_IMPL_CMD=1; shift ;;
        --migrate)      MIGRATE_CMD=1; MIGRATE_FROM="$2"; MIGRATE_TO="$3"; shift 3 ;;
        --migrate-output) MIGRATE_OUTPUT="$2"; shift 2 ;;
        --migrate-dry-run) MIGRATE_DRY_RUN=1; shift ;;
        --dry-run)      MIGRATE_DRY_RUN=1; shift ;;
        --chimeric)        CHIMERIC_CMD=1; CHIMERIC_SUB="${2:-status}"; shift 2
                          # 把 --chimeric <sub> 之后的剩余参数原样捕获，转发给子命令
                          CHIMERIC_VERIFY_ARGS=("$@"); shift $# ;;
        --chimeric-status) CHIMERIC_STATUS=1; shift ;;
        --orchestrate)     ORCHESTRATE_CMD=1; ORCHESTRATE_SUB="${2:-demo}"; shift 2
                          # 把 --orchestrate <sub> 之后的剩余参数原样捕获，转发给子命令
                          ORCHESTRATE_ARGS=("$@"); shift $# ;;
        -h|--help)      usage 0 ;;
        *)              echo "未知参数: $1" >&2; usage 1 ;;
    esac
done

# ---------- Agent 2: init command ----------
if [[ "${INIT_CMD:-0}" == "1" || -n "${INIT_TEMPLATE:-}" || -n "${INIT_FROM:-}" || -n "${INIT_FROM_URL:-}" ]]; then
    args=()
    [[ -n "${INIT_TEMPLATE:-}" ]] && args+=(--template "$INIT_TEMPLATE")
    [[ -n "${INIT_FROM:-}" ]] && args+=(--from "$INIT_FROM")
    [[ -n "${INIT_FROM_URL:-}" ]] && args+=(--from-url "$INIT_FROM_URL")
    [[ -n "${OUTPUT_DIR:-}" ]] && args+=(--output "$OUTPUT_DIR")
    bash "$GENERATORS_DIR/init.sh" "${args[@]}"
    exit 0
fi

# === Agent 3: drift + lint commands ===
if [[ "${DRIFT_CMD:-0}" == "1" ]]; then
    FIX_FLAG=""
    [[ "${FIX_MODE:-0}" == "1" ]] && FIX_FLAG="--fix"
    if [[ "${JSON_OUT:-0}" == "1" ]]; then
        bash "$GENERATORS_DIR/check.sh" --mode drift --json $FIX_FLAG
    else
        bash "$GENERATORS_DIR/check.sh" --mode drift $FIX_FLAG
    fi
    exit 0
fi
if [[ "${LINT_CMD:-0}" == "1" ]]; then
    FIX_FLAG=""
    [[ "${FIX_MODE:-0}" == "1" ]] && FIX_FLAG="--fix"
    if [[ "${JSON_OUT:-0}" == "1" ]]; then
        bash "$GENERATORS_DIR/check.sh" --mode lint --json $FIX_FLAG
    else
        bash "$GENERATORS_DIR/check.sh" --mode lint $FIX_FLAG
    fi
    exit 0
fi
# === Agent 1 (v9 P0): --fix alone: 默认跑 lint --fix, 然后 drift --fix ===
if [[ "${FIX_MODE:-0}" == "1" ]]; then
    echo "============================================================"
    echo " bootstrap --fix (auto-repair)"
    echo "============================================================"
    bash "$GENERATORS_DIR/check.sh" --mode lint --fix
    echo ""
    bash "$GENERATORS_DIR/check.sh" --mode drift --fix
    exit 0
fi
# === Agent 1: explain command ===
if [[ -n "${EXPLAIN_COMP:-}" ]]; then
    if [[ "${EXPLAIN_JSON:-0}" == "1" ]]; then
        bash "$GENERATORS_DIR/explain.sh" "$EXPLAIN_COMP" --json
    else
        bash "$GENERATORS_DIR/explain.sh" "$EXPLAIN_COMP"
    fi
    exit 0
fi

# === Agent 4: AI agent commands ===
# 把正确的路径传给 agent.sh：dev_queue.json 和 state.json 都写在 $OUTPUT_DIR 下
export DEV_QUEUE_FILE="${OUTPUT_DIR}/.ai/dev_queue.json"
export STATE_FILE="${OUTPUT_DIR}/.bootstrap/state.json"
if [[ "${STATUS_CMD:-0}" == "1" ]]; then bash "$GENERATORS_DIR/agent.sh" status; exit 0; fi
if [[ "${NEXT_CMD:-0}" == "1" ]]; then
    if [[ "${JSON_OUT:-0}" == "1" ]]; then
        bash "$GENERATORS_DIR/agent.sh" next --json
    else
        bash "$GENERATORS_DIR/agent.sh" next
    fi
    exit 0
fi
if [[ -n "${CLAIM_ID:-}" ]]; then bash "$GENERATORS_DIR/agent.sh" claim "$CLAIM_ID"; exit 0; fi
if [[ -n "${COMPLETE_ID:-}" ]]; then bash "$GENERATORS_DIR/agent.sh" complete "$COMPLETE_ID"; exit 0; fi
if [[ -n "${RESET_ID:-}" ]]; then bash "$GENERATORS_DIR/agent.sh" reset "$RESET_ID"; exit 0; fi

# ---------- Agent 5: validate command (硬约束 schema 校验) ----------
if [[ "${VALIDATE_CMD:-0}" == "1" ]]; then
    bash "$GENERATORS_DIR/validate.sh"
    exit $?
fi

# ---------- Agent 2: schema-aware import + impl checks ----------
if [[ "${CHECK_IMPORTS_CMD:-0}" == "1" ]]; then
    if [[ "${JSON_OUT:-0}" == "1" ]]; then
        bash "$GENERATORS_DIR/check_imports.sh" --json
    else
        bash "$GENERATORS_DIR/check_imports.sh"
    fi
    rc_imports=$?
    # 仅当 --check-imports 单独调用时立即退出
    # 当 --check-all 同时设了两个 flag 时继续跑 impl
    if [[ "${CHECK_IMPL_CMD:-0}" != "1" ]]; then
        exit $rc_imports
    fi
fi
if [[ "${CHECK_IMPL_CMD:-0}" == "1" ]]; then
    if [[ "${JSON_OUT:-0}" == "1" ]]; then
        bash "$GENERATORS_DIR/check_impl.sh" --json
    else
        bash "$GENERATORS_DIR/check_impl.sh"
    fi
    rc_impl=$?
    if [[ "${CHECK_IMPORTS_CMD:-0}" != "1" ]]; then
        exit $rc_impl
    fi
    # --check-all: 把两边的最大退出码作为总退出码
    [[ $rc_impl -gt ${rc_imports:-0} ]] && exit $rc_impl
    exit ${rc_imports:-0}
fi

# ---------- Chimeric: --chimeric {init|verify|status|plan} ----------
if [[ "${CHIMERIC_CMD:-0}" == "1" || "${CHIMERIC_STATUS:-0}" == "1" ]]; then
    sub="status"
    [[ "${CHIMERIC_CMD:-0}" == "1" ]] && sub="${CHIMERIC_SUB:-status}"
    # 转发 --chimeric <sub> 之后捕获的原始参数
    chim_args=("${CHIMERIC_VERIFY_ARGS[@]}")
    case "$sub" in
        init)
            peer="${chim_args[0]:-}"
            [[ -z "$peer" ]] && { echo "用法: bootstrap.sh --chimeric init <peer-spec-src>" >&2; exit 64; }
            bash "$GENERATORS_DIR/chimeric_spec.sh" "${chim_args[@]}"
            exit $?
            ;;
        verify)
            bash "$GENERATORS_DIR/chimeric_verify.sh" "${chim_args[@]}"
            exit $?
            ;;
        status)
            bash "$GENERATORS_DIR/chimeric_verify.sh" --status-only "${chim_args[@]}"
            exit $?
            ;;
        plan)
            bash "$GENERATORS_DIR/chimeric_adapter.sh" --plan "${chim_args[@]}"
            exit $?
            ;;
        *)
            echo "未知 --chimeric 子命令: $sub" >&2
            echo "用法: bootstrap.sh --chimeric {init|verify|status|plan}" >&2
            exit 64
            ;;
    esac
fi

# ---------- Agent 4: --migrate (struct.json schema 迁移) ----------
if [[ "${MIGRATE_CMD:-0}" == "1" ]]; then
    migrate_args=(--from "$MIGRATE_FROM" --to "$MIGRATE_TO" --struct "$STRUCT_FILE")
    [[ -n "${MIGRATE_OUTPUT:-}" ]] && migrate_args+=(--output "$MIGRATE_OUTPUT")
    [[ "${MIGRATE_DRY_RUN:-0}" == "1" ]] && migrate_args+=(--dry-run)
    bash "$GENERATORS_DIR/migrate.sh" "${migrate_args[@]}"
    exit $?
fi

# ---------- Wave 5: --orchestrate (Project Intelligence demo dispatch) ----------
# Pure dispatch to examples/dnc-demo/run.sh. Only adds new behavior; does not
# alter any existing target / drift / lint / chimeric dispatch.
if [[ "${ORCHESTRATE_CMD:-0}" == "1" ]]; then
    DEMO_RUN="$SCRIPT_DIR/examples/dnc-demo/run.sh"
    [[ -f "$DEMO_RUN" ]] || { echo "[FAIL] orchestrate demo not found: $DEMO_RUN" >&2; exit 2; }
    case "${ORCHESTRATE_SUB}" in
        demo)
            /opt/homebrew/bin/bash "$DEMO_RUN" "${ORCHESTRATE_ARGS[@]}"
            exit $?
            ;;
        *)
            echo "未知 --orchestrate 子命令: ${ORCHESTRATE_SUB}" >&2
            echo "用法: bootstrap.sh --orchestrate demo [--json|--self-test]" >&2
            exit 64
            ;;
    esac
fi

# ---------- 依赖检查 ----------
# 真正必须的：bash (3.2+) + jq (1.6+)
# 可选但推荐：sha256sum (增量构建) / cargo / ajv (严格校验)
# 明确不要的：python3 (历史包袱，已用纯 bash + sed 重写)
command -v jq >/dev/null 2>&1 || { echo "[FAIL] 缺少依赖: jq (请安装 jq 1.6+)" >&2; exit 1; }
[[ "${BASH_VERSINFO[0]}" -ge 4 ]] || { echo "[FAIL] bash 4.0+ 要求，当前: ${BASH_VERSION}" >&2; exit 1; }
[[ -f "$STRUCT_FILE" ]] || { echo "[FAIL] 找不到 $STRUCT_FILE" >&2; exit 1; }
jq empty "$STRUCT_FILE" 2>/dev/null || { echo "[FAIL] $STRUCT_FILE 不是合法 JSON" >&2; exit 1; }

# ---------- 校验 ----------
basic_validate() {
    local errs=0
    for field in schema_version modules; do
        if ! jq -e "has(\"$field\")" "$STRUCT_FILE" >/dev/null; then
            echo "[FAIL] 缺少必填字段: $field" >&2; ((errs++))
        fi
    done
    local nm
    nm=$(jq '.modules | length' "$STRUCT_FILE")
    [[ $nm -eq 0 ]] && { echo "[FAIL] modules 数组为空" >&2; ((errs++)); }
    local bad_modules
    bad_modules=$(jq -r '.modules[] | select((.components | length) == 0) | .name' "$STRUCT_FILE")
    if [[ -n "$bad_modules" ]]; then
        echo "[FAIL] 以下 modules 没有 components: $bad_modules" >&2; ((errs++))
    fi
    local dup
    dup=$(jq -r '
        [([.modules[]?.name] + [.modules[]?.components[]?.name])]
        | add | group_by(.) | map(select(length>1)[0]) | .[]
    ' "$STRUCT_FILE")
    if [[ -n "$dup" ]]; then
        echo "[FAIL] module/component 名称重复: $dup" >&2; ((errs++))
    fi
    local all_names
    all_names=$(jq -r '[.modules[] | (.name + " " + (.components[]?.name // ""))] | join(" ")' "$STRUCT_FILE")
    local broken
    broken=$(jq -r --arg all "$all_names" '
        [.modules[].components[] | (.imports // .depends_on // [])[]]
        | unique | .[] | select(. as $n | ($all | split(" ") | index($n)) == null)
    ' "$STRUCT_FILE")
    if [[ -n "$broken" ]]; then
        echo "[FAIL] imports 引用了不存在的组件: $broken" >&2; ((errs++))
    fi
    local all_todo_ids
    all_todo_ids=$(jq -r '[.modules[] | .components[] | .todos[]? | .id] | join(" ")' "$STRUCT_FILE")
    local broken_blocks
    broken_blocks=$(jq -r --arg all "$all_todo_ids" '
        [.modules[].components[].todos[]? | (.blocks // [])[]]
        | unique | .[] | select(. as $n | ($all | split(" ") | index($n)) == null)
    ' "$STRUCT_FILE")
    if [[ -n "$broken_blocks" ]]; then
        echo "[FAIL] blocks 引用了不存在的 todo id: $broken_blocks" >&2; ((errs++))
    fi
    return $errs
}

if [[ $SKIP_VALIDATE -eq 0 ]]; then
    if command -v ajv >/dev/null 2>&1; then
        ajv validate -s "$SCHEMA_FILE" -d "$STRUCT_FILE" --strict=false && echo "[OK] ajv 严格校验通过" || exit 1
    else
        basic_validate && echo "[OK] jq 基础校验通过（无 ajv，建议安装 ajv-cli 做严格校验）" || exit 1
    fi
fi

# ---------- 交互式选择 ----------
choose_targets() {
    local -a available=()
    echo ""
    echo "可用的生成器:"
    local i=1
    # 列出 generators/ 下所有 .sh（除了 _lib.sh）
    while IFS= read -r gen; do
        local lang
        lang=$(basename "$gen" .sh)
        [[ "$lang" == "_lib" ]] && continue
        available+=("$lang")
        printf "  %d) %s\n" "$i" "$lang"
        ((i++))
    done < <(find "$GENERATORS_DIR" -maxdepth 1 -name '*.sh' -type f 2>/dev/null | sort)
    available+=("all")
    printf "  %d) all (全部)\n" "$i"

    echo ""
    echo -n "选择目标 (空格分隔多个编号,直接回车=all): "
    read -r -a choices || true

    if [[ ${#choices[@]} -eq 0 ]]; then
        TARGETS="all"
        return
    fi

    local result=""
    for c in "${choices[@]}"; do
        if [[ "$c" =~ ^[0-9]+$ ]] && [[ $c -ge 1 ]] && [[ $c -le ${#available[@]} ]]; then
            local picked="${available[$((c-1))]}"
            if [[ "$picked" == "all" ]]; then
                result="all"; break
            fi
            [[ -z "$result" ]] && result="$picked" || result="${result},$picked"
        fi
    done
    TARGETS="${result:-all}"
}

if [[ -z "$TARGETS" ]]; then
    if [[ -t 0 ]]; then
        choose_targets
    else
        TARGETS="all"
    fi
fi

# 展开 "all" 为所有可用生成器（排除 subcommand 文件：check / agent / validate / init / check_impl / check_imports / migrate）
if [[ "$TARGETS" == "all" ]]; then
    TARGETS=$(find "$GENERATORS_DIR" -maxdepth 1 -name '*.sh' -type f 2>/dev/null \
              | grep -v _lib.sh \
              | grep -Ev '/(check|agent|validate|init|git_dispatch|git_merge|explain|check_impl|check_imports|migrate)\.sh$' \
              | xargs -I{} basename {} .sh | sort | paste -sd, -)
fi
IFS=',' read -ra TARGET_ARR <<< "$TARGETS"

# ---------- --target chimeric 展开为三个 chimeric 生成器 ----------
for i in "${!TARGET_ARR[@]}"; do
    if [[ "${TARGET_ARR[$i]}" == "chimeric" ]]; then
        TARGET_ARR=("${TARGET_ARR[@]:0:$i}" chimeric_spec chimeric_adapter chimeric_verify "${TARGET_ARR[@]:$((i+1))}")
    fi
done

# ---------- 友好别名映射 ----------
declare -A TARGET_ALIAS=(
    [agents]='agents_md'
    [context]='context_json'
    [queue]='dev_queue'
    [viz]='visualization'
    [docs]='visualization'
)
for i in "${!TARGET_ARR[@]}"; do
    t="${TARGET_ARR[$i]}"
    if [[ -n "${TARGET_ALIAS[$t]:-}" ]]; then
        TARGET_ARR[$i]="${TARGET_ALIAS[$t]}"
    fi
done

echo "============================================================"
echo " bootstrap  struct=$STRUCT_FILE  schema_version=$(jq -r '.schema_version' "$STRUCT_FILE")"
echo " targets: ${TARGET_ARR[*]}"
[[ -n "$INCLUDE_MODULES" ]] && echo " include: $INCLUDE_MODULES"
[[ -n "$EXCLUDE_MODULES" ]] && echo " exclude: $EXCLUDE_MODULES"
[[ $PLAN_ONLY -eq 1 ]] && echo " mode   : PLAN ONLY (no writes)"
echo " output : $OUTPUT_DIR/"
echo "============================================================"

# ---------- 校验生成器存在 ----------
for t in "${TARGET_ARR[@]}"; do
    [[ -f "$GENERATORS_DIR/$t.sh" ]] || {
        echo "[FAIL] 生成器不存在: $GENERATORS_DIR/$t.sh" >&2; exit 1
    }
done

# ---------- Agent 1: explain command ----------
if [[ -n "${EXPLAIN_COMP:-}" ]]; then
    if [[ "${EXPLAIN_JSON:-0}" == "1" ]]; then
        bash "$GENERATORS_DIR/explain.sh" "$EXPLAIN_COMP" --json
    else
        bash "$GENERATORS_DIR/explain.sh" "$EXPLAIN_COMP"
    fi
    exit 0
fi

# ---------- source 共享库 ----------
# shellcheck disable=SC1091
source "$GENERATORS_DIR/_lib.sh"

# ---------- 拓扑序: 服务依赖 ----------
echo ""
echo "[1/3] 计算组件依赖拓扑序..."
SERVICE_ORDER=$(topo_sort_components)
status_ok "components: $(echo $SERVICE_ORDER | wc -w)"

# ---------- 拓扑序: todo blocker DAG ----------
echo "[2/3] 计算 todo blocker 拓扑序 + 并行 waves..."
DEV_ORDER=$(topo_sort_todos)
TOTAL_TODOS=$(echo "$DEV_ORDER" | wc -w)
status_ok "todos: $TOTAL_TODOS"

# ---------- 输出到全局上下文，供生成器使用 ----------
export STRUCT_FILE SCHEMA_FILE OUTPUT_DIR SERVICE_ORDER DEV_ORDER
export SKIP_TODO PLAN_ONLY INCLUDE_MODULES EXCLUDE_MODULES
export GENERATORS_DIR
export TOTAL_TODOS
export FORCE_REGEN

# ---------- Plan 模式 ----------
if [[ $PLAN_ONLY -eq 1 ]]; then
    echo ""
    echo "[3/3] PLAN ONLY — 以下是即将生成的文件（不会写盘）:"
    for t in "${TARGET_ARR[@]}"; do
        echo ""
        echo "▶ $t"
        bash "$GENERATORS_DIR/$t.sh" --plan 2>&1 || true
    done
    exit 0
fi

# ---------- 调度各生成器 ----------
mkdir -p "$OUTPUT_DIR"
echo ""
echo "[3/3] 调度生成器..."
TOTAL_TARGETS=${#TARGET_ARR[@]}
CUR=0
for t in "${TARGET_ARR[@]}"; do
    CUR=$((CUR + 1))
    progress_bar "$CUR" "$TOTAL_TARGETS" "running $t"
    echo ""
    # generator 自己的 stdout 正常打印；spinner 不与它共存
    if bash "$GENERATORS_DIR/$t.sh"; then
        status_ok "$t"
    else
        rc=$?
        status_fail "$t (exit=$rc)"
        exit 1
    fi
done

# ---------- 汇总 ----------
echo ""
echo "============================================================"
status_ok "生成完成"
echo "============================================================"
echo " 输出根目录: $OUTPUT_DIR/"
echo " 组件拓扑序长度: $(echo $SERVICE_ORDER | wc -w)"
echo " todo 拓扑序长度: $TOTAL_TODOS"
[[ -f "$OUTPUT_DIR/AGENTS.md" ]] && {
    echo ""
    echo " [AI] AI 启动入口: cat $OUTPUT_DIR/AGENTS.md"
}
[[ -f "$OUTPUT_DIR/.ai/dev_queue.json" ]] && {
    echo " [AI] 并行任务队列: jq '.waves' $OUTPUT_DIR/.ai/dev_queue.json"
}
[[ -f "$OUTPUT_DIR/docs/ARCHITECTURE.md" ]] && {
    echo " [DOCS] 架构文档: $OUTPUT_DIR/docs/ARCHITECTURE.md"
    [[ -f "$OUTPUT_DIR/docs/architecture.html" ]] && echo " [WEB] 甲方展示页: $OUTPUT_DIR/docs/architecture.html"
}
echo "============================================================"

# ---------- 写 .ai/state.json (drift 检查用) ----------
AI_STATE_DIR="${OUTPUT_DIR}/.ai"
mkdir -p "$AI_STATE_DIR"
STATE_JSON="${AI_STATE_DIR}/state.json"
STRUCT_HASH=$(sha256sum "$STRUCT_FILE" | awk '{print $1}')

# 收集本次生成的产物（相对 $OUTPUT_DIR）
outputs_json="[]"
if [[ -d "$OUTPUT_DIR" ]]; then
    outputs_json=$(cd "$OUTPUT_DIR" && find . -type f \
        ! -path './.ai/state.json' \
        ! -path './.bootstrap/*' \
        -printf '%P\n' 2>/dev/null \
        | jq -R '{path: ("/" + .), size: 0}' \
        | jq -s '.' || echo "[]")
fi

# 写 state.json - 使用临时文件避免 Argument list too long
_targets_tmp=$(mktemp)
_outputs_tmp=$(mktemp)
printf '%s\n' "${TARGET_ARR[@]}" | jq -R . | jq -s . > "$_targets_tmp" 2>/dev/null
echo "$outputs_json" > "$_outputs_tmp"

jq -n \
    --arg schema_version "1.0" \
    --arg at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    --arg struct_hash "$STRUCT_HASH" \
    --arg struct_path "${STRUCT_FILE}" \
    --slurpfile targets "$_targets_tmp" \
    --slurpfile outputs "$_outputs_tmp" \
    '{
        schema_version: $schema_version,
        last_run: {
            at: $at,
            targets: $targets[0],
            exit_code: 0
        },
        struct_hash: $struct_hash,
        sources: {
            struct: {
                path: $struct_path,
                sha256: $struct_hash
            }
        },
        targets: $targets[0],
        outputs: $outputs[0]
    }' > "$STATE_JSON" 2>/dev/null || {
        echo "  [WARN] state.json 写入失败（jq 错误），跳过" >&2
    }

rm -f "$_targets_tmp" "$_outputs_tmp"

echo " [STATE] drift manifest: $STATE_JSON"