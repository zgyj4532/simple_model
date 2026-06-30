#!/usr/bin/env bash
# generators/_lib.sh — 共享 bash 助手库
# 用法: source "$(dirname "${BASH_SOURCE[0]}")/_lib.sh"
#
# 提供:
#   自启动: bootstrap_env (让单个 .sh 也能直接跑)
#   命名转换: to_snake / to_screaming / to_kebab / to_pascal
#   计数/查找: module_count / component_count / module_of
#   迭代器: iter_modules / iter_components
#   数据访问: read_component / read_module
#   工具: module_todo_json / emit_dev_order / compute_waves

# ---------- 自启动 (Bug #10 fix: 单个 .sh 也能跑) ----------
# 当用户直接执行 `bash generators/python.sh` 而不通过 bootstrap.sh 时，
# 需要的 env vars (OUTPUT_DIR, STRUCT_FILE, SERVICE_ORDER, DEV_ORDER) 全没设。
# 这个函数用 cwd 自动推导默认值，让单个 .sh 也能产出文件。
bootstrap_env() {
    # 1. STRUCT_FILE — 当前目录或父目录找
    : "${STRUCT_FILE:=}"
    if [[ -z "$STRUCT_FILE" ]]; then
        if [[ -f "./struct.json" ]]; then
            STRUCT_FILE="./struct.json"
        elif [[ -f "../struct.json" ]]; then
            STRUCT_FILE="../struct.json"
        else
            echo "[FAIL] 找不到 struct.json（在 ./ 或 ../ 都没有）" >&2
            return 1
        fi
    fi

    # 2. OUTPUT_DIR — 默认 ./generated
    : "${OUTPUT_DIR:=./generated}"

    # 3. SCHEMA_FILE — 默认跟 struct.json 同目录
    : "${SCHEMA_FILE:=${STRUCT_FILE%/*}/struct.schema.json}"
    [[ "$SCHEMA_FILE" == "$STRUCT_FILE" ]] && SCHEMA_FILE="./struct.schema.json"
    [[ -z "${SCHEMA_FILE:-}" || ! -f "$SCHEMA_FILE" ]] && SCHEMA_FILE=""

    # 4. SERVICE_ORDER / DEV_ORDER — 如果空就现算
    : "${SERVICE_ORDER:=}"
    : "${DEV_ORDER:=}"
    : "${TOTAL_TODOS:=0}"
    : "${PLAN_ONLY:=0}"

    if [[ -z "$SERVICE_ORDER" ]] && command -v topo_sort_components >/dev/null 2>&1; then
        SERVICE_ORDER=$(topo_sort_components 2>/dev/null || echo "")
    fi
    if [[ -z "$DEV_ORDER" ]] && command -v topo_sort_todos >/dev/null 2>&1; then
        DEV_ORDER=$(topo_sort_todos 2>/dev/null || echo "")
        [[ -n "$DEV_ORDER" ]] && TOTAL_TODOS=$(echo "$DEV_ORDER" | wc -w)
    fi

    # 5. GENERATORS_DIR — _lib.sh 所在目录
    SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    : "${GENERATORS_DIR:=$SELF_DIR}"

    # 6. Bug #10 fix: 确保 OUTPUT_DIR 存在 (避免单独跑 .sh 时崩)
    mkdir -p "$OUTPUT_DIR"

    export STRUCT_FILE OUTPUT_DIR SCHEMA_FILE SERVICE_ORDER DEV_ORDER TOTAL_TODOS PLAN_ONLY GENERATORS_DIR
    return 0
}

# 自动调用一次（被 source 进来后立即生效）
bootstrap_env 2>/dev/null || true

# ---------- 命名转换 (纯 bash + sed，无 python3 依赖) ----------

# PascalCase -> snake_case
# 例: DataLoader -> data_loader; HTTPSConnection -> https_connection; UserAPI -> user_api
to_snake() {
    echo "$1" | sed -E 's/([A-Z])([A-Z][a-z])/\1_\2/g; s/([a-z0-9])([A-Z])/\1_\2/g' | tr '[:upper:]' '[:lower:]'
}

# PascalCase -> SCREAMING_SNAKE_CASE
to_screaming() {
    to_snake "$1" | tr '[:lower:]' '[:upper:]'
}

# PascalCase -> kebab-case
to_kebab() {
    to_snake "$1" | tr '_' '-'
}

# snake_case -> PascalCase
# 例: data_loader -> DataLoader
to_pascal() {
    echo "$1" | sed -E 's/(^|_)([a-z])/\U\2/g'
}

# ---------- 工具函数 ----------

# 把一个 PascalCase 名字安全地转成 Python 标识符（已经在 snake 里处理）
to_python_name() {
    to_snake "$1"
}

# ---------- 计数 ----------

module_count() {
    jq '.modules // [] | length' "$STRUCT_FILE"
}

component_count() {
    local module_idx="$1"
    jq ".modules[$module_idx].components // [] | length" "$STRUCT_FILE"
}

total_component_count() {
    jq '[.modules[].components // [] | length] | add // 0' "$STRUCT_FILE"
}

# ---------- 查找（带缓存）----------

declare -A _LIB_MODULE_OF_CACHE=()

# module_of <component_name> -> module name (空字符串表示找不到)
module_of() {
    local comp="$1"
    if [[ -n "${_LIB_MODULE_OF_CACHE[$comp]:-}" ]]; then
        echo "${_LIB_MODULE_OF_CACHE[$comp]}"
        return
    fi
    local m
    m=$(jq -r --arg c "$comp" '
        [.modules[] | select(.components[].name == $c) | .name][0] // empty
    ' "$STRUCT_FILE")
    _LIB_MODULE_OF_CACHE[$comp]="$m"
    echo "$m"
}

# ---------- 迭代器 ----------

# iter_modules: 输出每个 module 的 idx \t name \t description
iter_modules() {
    jq -r '.modules // [] | to_entries[] | "\(.key)\t\(.value.name)\t\(.value.description)"' "$STRUCT_FILE"
}

# iter_components <module_idx>: 输出每个 component 的 idx \t name \t description
iter_components() {
    local mi="$1"
    jq -r ".modules[$mi].components // [] | to_entries[] | \"\(.key)\t\(.value.name)\t\(.value.description)\"" "$STRUCT_FILE"
}

# ---------- 数据访问（单次 jq 调用返回所有字段）----------

# 输出 JSON: {name, description, exports, imports, optional, language, todos[]}
read_component() {
    local module_idx="$1" comp_idx="$2"
    jq -c ".modules[$module_idx].components[$comp_idx]" "$STRUCT_FILE"
}

# 输出 JSON: {name, description, language, components_count, todos_count}
read_module() {
    local module_idx="$1"
    jq -c ".modules[$module_idx] | {
        name, description, language: (.language // \"any\"),
        components_count: (.components | length),
        todos_count: ([.components[].todos // [] | length] | add // 0)
    }" "$STRUCT_FILE"
}

# ---------- 工具 ----------

# 模块级 todo.json
module_todo_json() {
    local module_idx="$1" out_file="$2"
    jq "{module: .modules[$module_idx].name, description: .modules[$module_idx].description, todos: [.modules[$module_idx].components[] | . as \$c | .todos[]? | . + {component: \$c.name, module: .modules[$module_idx].name}]}" "$STRUCT_FILE" \
        > "$out_file"
}

# 检查 module 的 language 是否匹配目标语言
# language_match <module_json> <target_lang>
# 匹配规则: target=any 永远匹配; module.language=any 匹配所有; 否则需要相等
language_match() {
    local module_json="$1" target="$2"
    local mlang
    mlang=$(echo "$module_json" | jq -r '.language // "any"')
    [[ "$target" == "any" ]] && return 0
    [[ "$mlang" == "any" || "$mlang" == "$target" ]] && return 0
    return 1
}

# 进度输出
say() { echo "  $*"; }

# ---------- CLI 动画（不依赖 emoji，纯 ASCII）----------

# 状态标签（替代 emoji）
status_ok()   { printf '  [OK]   %s\n' "$*"; }
status_fail() { printf '  [FAIL] %s\n' "$*" >&2; }
status_warn() { printf '  [WARN] %s\n' "$*" >&2; }
status_info() { printf '  [INFO] %s\n' "$*"; }

# Spinner: 在后台命令运行期间显示旋转指针
# 用法: spin_start "描述"; (long_cmd) & cmd_pid=$!; spin_stop $cmd_pid
# 设置 NO_SPIN=1 可完全禁用 spinner 输出（机器输出场景）
SPIN_PID=""
spin_chars='|/-\'
spin_idx=0
spin_start() {
    [[ "${NO_SPIN:-0}" == "1" ]] && { SPIN_PID=""; spin_label="$*"; return; }
    spin_label="$*"
    spin_idx=0
    # 后台 spin 协程
    (
        while true; do
            printf '\r  [%c] %s' "${spin_chars:spin_idx++%4:1}" "$spin_label"
            sleep 0.1
        done
    ) &
    SPIN_PID=$!
}
spin_stop() {
    local exit_code="${1:-0}"
    if [[ -n "$SPIN_PID" ]]; then
        # disown 防止 wait 阻塞; 用 pkill -P 杀 spin_start fork 的子进程
        disown "$SPIN_PID" 2>/dev/null || true
        # 杀 spin subshell 自身 (它 fork 了 printf + sleep)
        pkill -KILL -P "$SPIN_PID" 2>/dev/null || true
        kill -KILL "$SPIN_PID" 2>/dev/null || true
        wait "$SPIN_PID" 2>/dev/null || true
    fi
    [[ "${NO_SPIN:-0}" == "1" ]] && { SPIN_PID=""; return; }
    printf '\r'
    if [[ $exit_code -eq 0 ]]; then
        printf '  [OK]   %s\n' "$spin_label"
    else
        printf '  [FAIL] %s (exit=%d)\n' "$spin_label" "$exit_code"
    fi
    SPIN_PID=""
}

# 用法: run_with_spin "描述" command arg1 arg2 ...
run_with_spin() {
    local desc="$1"; shift
    spin_start "$desc"
    "$@"
    local rc=$?
    spin_stop $rc
    return $rc
}

# 进度条
# 用法: progress_bar <current> <total> [label]
progress_bar() {
    # 容错：参数必须是数字，否则直接返回
    local cur="$1" total="$2" label="${3:-}"
    if ! [[ "$cur" =~ ^[0-9]+$ ]] || ! [[ "$total" =~ ^[0-9]+$ ]]; then
        printf '\r  [%d/%d] %s' "${cur:-0}" "${total:-0}" "$label"
        return 0
    fi
    [[ $total -le 0 ]] && total=1
    local width=40
    local pct=$(( cur * 100 / total ))
    local filled=$(( cur * width / total ))
    local empty=$(( width - filled ))
    [[ $filled -lt 0 ]] && filled=0
    [[ $filled -gt $width ]] && filled=$width
    [[ $empty -lt 0 ]] && empty=0
    [[ $empty -gt $width ]] && empty=$width
    local bar=""
    local i=0
    while [[ $i -lt $filled ]]; do
        bar+="#"
        i=$((i+1))
    done
    i=0
    while [[ $i -lt $empty ]]; do
        bar+="."
        i=$((i+1))
    done
    printf '\r  [%s] %3d%% (%d/%d) %s' "$bar" "$pct" "$cur" "$total" "$label"
    [[ $cur -eq $total ]] && printf '\n'
    return 0
}

# 创建文件并打印路径
emit() {
    local path="$1"
    mkdir -p "$(dirname "$path")"
    cat > "$path"
    echo "  [OK] ${path#$OUTPUT_DIR/}"
}

# ---------- 拓扑排序（暴露给 generator）----------

# topo_sort_components: 输出空格分隔的 component 拓扑序
topo_sort_components() {
    local TMP_GRAPH
    TMP_GRAPH=$(mktemp)
    jq -r '
        (.modules // []) | .[] | (.components // []) | .[]? |
        "\(.name)\t\((.imports // .depends_on // []) | join(","))"
    ' "$STRUCT_FILE" > "$TMP_GRAPH"

    declare -A indeg deps_of
    local -a ALL_NODES
    while IFS=$'\t' read -r name imports_csv; do
        [[ -z "$name" ]] && continue
        ALL_NODES+=("$name")
        deps_of[$name]="$imports_csv"
        indeg[$name]=0
    done < "$TMP_GRAPH"

    for n in "${ALL_NODES[@]}"; do
        IFS=',' read -ra ds <<< "${deps_of[$n]}"
        for d in "${ds[@]}"; do
            [[ -n "$d" ]] && ((indeg[$d]++))
        done
    done

    local queue=()
    for n in "${ALL_NODES[@]}"; do
        [[ ${indeg[$n]} -eq 0 ]] && queue+=("$n")
    done

    local order=""
    while [[ ${#queue[@]} -gt 0 ]]; do
        queue=($(printf '%s\n' "${queue[@]}" | sort))
        local n="${queue[0]}"; queue=("${queue[@]:1}")
        order+="$n "
        for m in "${ALL_NODES[@]}"; do
            IFS=',' read -ra ds <<< "${deps_of[$m]}"
            for d in "${ds[@]}"; do
                if [[ "$d" == "$n" ]]; then
                    ((indeg[$m]--))
                    [[ ${indeg[$m]} -eq 0 ]] && queue+=("$m")
                    break
                fi
            done
        done
    done

    rm -f "$TMP_GRAPH"
    echo "$order"
}

# topo_sort_todos: 输出空格分隔的 todo id 拓扑序
topo_sort_todos() {
    local TMP_TODOS
    TMP_TODOS=$(mktemp)
    jq -r '
        (.modules // []) | .[] | (.components // []) | .[] | (.todos // []) | .[]? |
        [
            .id, (.blocks // [] | join(","))
        ] | @tsv
    ' "$STRUCT_FILE" > "$TMP_TODOS"

    declare -A todo_blocks
    declare -A blocked_by
    local -a ALL_IDS
    while IFS=$'\t' read -r id blocks_csv; do
        [[ -z "$id" ]] && continue
        ALL_IDS+=("$id")
        todo_blocks[$id]="$blocks_csv"
        blocked_by[$id]=""
    done < "$TMP_TODOS"

    for id in "${ALL_IDS[@]}"; do
        IFS=',' read -ra bs <<< "${todo_blocks[$id]}"
        for b in "${bs[@]}"; do
            [[ -n "$b" ]] && blocked_by[$b]="${blocked_by[$b]:+${blocked_by[$b]} }$id"
        done
    done

    declare -A todo_indeg
    local queue=()
    for id in "${ALL_IDS[@]}"; do
        local n
        n=$(echo "${blocked_by[$id]}" | wc -w)
        todo_indeg[$id]=$n
        [[ $n -eq 0 ]] && queue+=("$id")
    done

    local order=""
    while [[ ${#queue[@]} -gt 0 ]]; do
        queue=($(printf '%s\n' "${queue[@]}" | sort))
        local id="${queue[0]}"; queue=("${queue[@]:1}")
        order+="$id "
        IFS=',' read -ra bs <<< "${todo_blocks[$id]}"
        for b in "${bs[@]}"; do
            [[ -n "$b" ]] && {
                ((todo_indeg[$b]--))
                [[ ${todo_indeg[$b]} -eq 0 ]] && queue+=("$b")
            }
        done
    done

    rm -f "$TMP_TODOS"
    echo "$order"
}

# compute_waves: 把 todo 拓扑序切成"并行波"
# 输出: TSV: wave_num \t todo_id
# 算法: 对每个 todo 算最大阻塞深度 = max(depth[blocker])+1; 同 depth 的 todo 在同一 wave
compute_waves() {
    local order="$1"
    declare -A depth

    for tid in $order; do
        depth[$tid]=1
    done

    # 因为 order 已经是拓扑序, 一次遍历即可算出每个 todo 的"完成 wave 号"
    # wave 1 = 没有 blocker 的 todo（立即可做）
    for tid in $order; do
        local max_blocker_depth=0
        local blocks_csv
        blocks_csv=$(jq -r --arg id "$tid" '
            [(.modules // []) | .[] | (.components // []) | .[] | (.todos // []) | .[]? | select(.id == $id) | (.blocks // [])[]] | join(",")
        ' "$STRUCT_FILE")
        IFS=',' read -ra bs <<< "$blocks_csv"
        for b in "${bs[@]}"; do
            [[ -z "$b" ]] && continue
            local bd=${depth[$b]:-1}
            [[ $bd -gt $max_blocker_depth ]] && max_blocker_depth=$bd
        done
        depth[$tid]=$((max_blocker_depth + 1))
    done

    for tid in $order; do
        printf '%d\t%s\n' "${depth[$tid]}" "$tid"
    done
}

# ---------- v8 P0: 增强 CLI 动画库 ----------
# 6 个新原语：typing_text / box_draw / milestone / token_counter / ascii_bar / tree_node

# 1. typing_text "msg" [speed] — 打字机效果（逐字输出）
typing_text() {
    local msg="$1" speed="${2:-0.015}"
    local i
    for ((i=0; i<${#msg}; i++)); do
        printf '%s' "${msg:$i:1}"
        sleep "$speed"
    done
    printf '\n'
}

# 2. box_draw "title" "body..." [width]
# 输出带框线的内容：
#   ┌── title ─────────────────┐
#   │ body...                   │
#   └───────────────────────────┘
box_draw() {
    local title="$1" body="$2" width="${3:-60}"
    local title_bar="── $title "
    local pad=$((width - ${#title_bar} - 1))
    [[ $pad -lt 0 ]] && pad=0
    printf '  ┌%s%*s┐\n' "$title_bar" "$pad" ""
    # 把 body 按 width-4 宽度折行
    while IFS= read -r line; do
        printf '  │ %-*s │\n' "$((width-4))" "$line"
    done <<< "$(echo "$body" | fold -w $((width-4)) 2>/dev/null || echo "$body")"
    printf '  └%*s┘\n' "$width" ""
}

# 3. milestone "msg" — 大型里程碑庆祝（多行 box + 闪烁效果）
milestone() {
    local msg="$*"
    local width=50
    local pad=$((width - ${#msg} - 4))
    [[ $pad -lt 0 ]] && pad=0
    echo ""
    echo "  +++ +++ +++ +++ +++ +++ +++ +++ +++ +++"
    echo "  +                                                   +"
    printf '  +   %s%*s   +\n' "$msg" "$pad" ""
    echo "  +                                                   +"
    echo "  +++ +++ +++ +++ +++ +++ +++ +++ +++ +++"
    echo ""
}

# 4. token_counter <count> [label] — 显示 token 节省估算
# 输出:  [TOKEN]   ~1,234 tokens  (~99% saved vs full read)
token_counter() {
    local count="$1" label="${2:-estimated context size}"
    local formatted
    formatted=$(printf "%'d" "$count" 2>/dev/null || echo "$count")
    printf '  [TOK]   %s tokens (%s)\n' "$formatted" "$label"
}

# 5. ascii_bar <pct> [width] — 单行 ASCII 进度条（颜色用 ANSI 但可关）
ascii_bar() {
    local pct=$1 width="${2:-30}"
    local filled=$((pct * width / 100))
    local empty=$((width - filled))
    local bar="" i
    for ((i=0; i<filled; i++)); do bar+='█'; done
    for ((i=0; i<empty; i++)); do bar+='░'; done
    printf '  %s %3d%%\n' "$bar" "$pct"
}

# 6. tree_node "label" [depth] — 树状缩进
tree_node() {
    local label="$1" depth="${2:-0}"
    local prefix=""
    local i
    for ((i=0; i<depth; i++)); do prefix+='│   '; done
    printf '  %s├─ %s\n' "$prefix" "$label"
}

# ---------- v9 P0: 更精美的 CLI 动画库 v2 ----------
# 10 个新原语：loading_dots / pulse_bar / rainbow_text / count_down /
#              wave_anim / section_banner / compare_bar / fireworks /
#              step / header_line
# 零 emoji、零 Python、零外部命令；全部在 set -euo pipefail 下安全。

# 1. loading_dots "msg" [seconds]
# 逐字追加 "."、".."、"..."、"...." 循环，类似 youtube 加载指示器。
# 用法:
#   loading_dots "Fetching data" 2    # 跑 2 秒后自动结束并清除行
loading_dots() {
    local msg="$1" seconds="${2:-1.5}"
    # 支持 1.5 这种小数输入：取整数部分作为循环秒数
    local secs=${seconds%.*}
    local end=$((SECONDS + secs))
    local i=0
    while [[ $SECONDS -lt $end ]]; do
        # i%4 得到 0/1/2/3，对应 0/1/2/3 个点
        local dots=""
        local d
        for ((d=0; d<i%4; d++)); do dots+="."; done
        printf '\r  [LOAD] %s%s' "$msg" "$dots"
        i=$((i+1))
        sleep 0.3
    done
    printf '\r'
}

# 2. pulse_bar [width]
# 宽度固定 30（可用第一个参数覆盖），从 0% 到 100% 再回到 0% 来回脉动一次。
# 适合展示"正在思考" / "正在准备"的状态。
# 用法:
#   pulse_bar                # 默认宽度 30
#   pulse_bar 50             # 宽度 50
pulse_bar() {
    local width="${1:-30}"
    local pct filled empty bar i
    for pct in 0 10 20 30 40 50 60 70 80 90 100 90 80 70 60 50 40 30 20 10; do
        filled=$((pct * width / 100))
        empty=$((width - filled))
        bar=""
        for ((i=0; i<filled; i++)); do bar+='█'; done
        for ((i=0; i<empty; i++)); do bar+='░'; done
        printf '\r  [PULSE] %s %3d%%' "$bar" "$pct"
        sleep 0.05
    done
    printf '\n'
}

# 3. rainbow_text "msg" [speed]
# 逐字输出，每个字符用一个 ASCII 装饰符包裹（左 + 右）。
# 装饰符循环使用：[#] [+] [=] [~] [^]
# 用法:
#   rainbow_text "Hello, World!"         # 默认 0.02s/字
#   rainbow_text "Faster" 0.005          # 更快
rainbow_text() {
    local msg="$1" speed="${2:-0.02}"
    local -a decor=('[#]' '[+]' '[=]' '[~]' '[^]')
    local i=0
    local ch
    # 逐字符读取；IFS= 防止空格被吞，-r 防止反斜杠转义，-n1 一次一字
    while IFS= read -r -n1 ch; do
        [[ -z "$ch" ]] && break
        printf '%s%s%s' "${decor[$((i % 5))]}" "$ch" "${decor[$((i % 5))]}"
        i=$((i+1))
        sleep "$speed"
    done <<< "$msg"
    printf '\n'
}

# 4. count_down "msg" [from_seconds]
# 倒计时显示 `T-3 ... T-2 ... T-1 ... GO!`。
# 用法:
#   count_down "Launching"        # 默认 3 秒
#   count_down "Boot" 5           # 5 秒
count_down() {
    local msg="$1" from="${2:-3}"
    local i=$from
    while [[ $i -gt 0 ]]; do
        printf '\r  [T-%d] %s' "$i" "$msg"
        sleep 1
        i=$((i-1))
    done
    printf '\r  [GO!]   %s\n' "$msg"
}

# 5. wave_anim "msg" [cycles]
# 绘制类似海浪的 ASCII 动画：`~^~^~^~^`、`^^^^^^^^^^`、`~~~~~~~~~~`。
# 用法:
#   wave_anim "Loading tides"      # 默认 3 轮
#   wave_anim "Surfing" 5          # 5 轮
wave_anim() {
    local msg="$1" cycles="${2:-3}"
    local -a waves=(
        '~^~^~^~^~^~^~'
        '~~^^~~^^~~^^'
        '^~^~^~^~^~^~'
        '~~~~~~~~~~~~'
    )
    local c w
    for ((c=0; c<cycles; c++)); do
        for w in "${waves[@]}"; do
            printf '\r  [WAVE] %s  %s' "$w" "$msg"
            sleep 0.1
        done
    done
    printf '\n'
}

# 6. section_banner "title" [width]
# 用 ASCII 字符画大标题：上框 / 标题 / 下框。
# 用法:
#   section_banner "Phase 1: Setup"        # 默认宽度 60
#   section_banner "Results" 40            # 宽度 40
section_banner() {
    local title="$1" width="${2:-60}"
    [[ $width -lt 10 ]] && width=10
    local inner=$((width - 2))           # 上下框 +--+ 内部宽度
    local title_padded=" $title "
    local pad=$((inner - ${#title_padded}))
    [[ $pad -lt 0 ]] && pad=0
    local dash=""
    local i
    for ((i=0; i<inner; i++)); do dash+='-'; done
    printf '\n'
    printf '  +%s+\n' "$dash"
    printf '  |%s%*s|\n' "$title_padded" "$pad" ""
    printf '  +%s+\n' "$dash"
    printf '\n'
}

# 7. compare_bar "current" "target" [label]
# 对比两个数值，画出差异条 + 数字比例。
# 用法:
#   compare_bar 75 100 "Tasks done"
#   compare_bar 5 8
compare_bar() {
    local cur="$1" target="$2" label="${3:-}"
    local pct=0 width=30 filled empty i
    if [[ $target -gt 0 ]]; then
        pct=$((cur * 100 / target))
    fi
    [[ $pct -gt 100 ]] && pct=100
    [[ $pct -lt 0 ]] && pct=0
    filled=$((pct * width / 100))
    empty=$((width - filled))
    [[ -n "$label" ]] && printf '  %s\n' "$label"
    printf '  current: '
    for ((i=0; i<filled; i++)); do printf '█'; done
    for ((i=0; i<empty; i++)); do printf '░'; done
    printf ' %d/%d (%d%%)\n' "$cur" "$target" "$pct"
}

# 8. fireworks "msg"
# 完成时的庆祝动画：在屏幕上随机喷 ASCII 字符。
# 用法:
#   fireworks "Mission accomplished!"
fireworks() {
    local msg="$1"
    local -a chars=('*' '+' '.' 'o' 'O' '0' '#' '@' '~' '^' '%' '&')
    local i j line idx
    for ((i=0; i<20; i++)); do
        line=""
        for ((j=0; j<40; j++)); do
            idx=$((RANDOM % ${#chars[@]}))
            line+="${chars[$idx]}"
        done
        printf '\r  %s' "$line"
        sleep 0.05
    done
    printf '\n  *** %s ***\n\n' "$msg"
}

# 9. step "msg" [total_steps] [current_step]
# 模拟"步骤 1/5" 风格的展示。current_step 默认 = 1，每次调用递增。
# 全局变量 _LIB_STEP_COUNTER 持有当前 step。
# 用法:
#   step "Connecting to DB" 5          # 第 1/5 步
#   step "Fetching rows" 5             # 第 2/5 步
#   ...
step() {
    local msg="$1" total="${2:-1}" current="${3:-}"
    if [[ -z "$current" ]]; then
        _LIB_STEP_COUNTER=$(( ${_LIB_STEP_COUNTER:-0} + 1 ))
        current="$_LIB_STEP_COUNTER"
    fi
    printf '  [STEP %s/%s] %s\n' "$current" "$total" "$msg"
}

# 10. header_line [char] [width]
# 画分隔线（默认 '-' × 60）。可在两个章节之间做视觉分割。
# 用法:
#   header_line              # 默认 '-' × 60
#   header_line '='          # '=' × 60
#   header_line '#' 80       # '#' × 80
header_line() {
    local ch="${1:--}" width="${2:-60}"
    [[ -z "$ch" ]] && ch='-'
    local i line=""
    for ((i=0; i<width; i++)); do line+="$ch"; done
    printf '  %s\n' "$line"
}

# ---------- v9 P1: 增量构建助手 ----------
# 基于 SHA-256 + .deps 缓存文件的增量构建原语。
# generator 在每个文件生成前调用 should_regenerate；生成后调用 mark_generated。
# 文件不存在或 source hash 变化时返回 0（需生成）；返回 1 表示可以 SKIP。

# file_hash <path>
# 输出文件的 SHA-256 hash；如果文件不存在返回空字符串。
file_hash() {
    local f="$1"
    [[ -f "$f" ]] || { echo ""; return 0; }
    sha256sum "$f" 2>/dev/null | awk '{print $1}'
}

# should_regenerate <output_path> <source_files...>
# 返回 0 = 需要重新生成；返回 1 = 可以跳过
# 判定逻辑:
#   1. output 不存在              -> regenerate
#   2. ${output}.deps 不存在       -> regenerate
#   3. 当前 sources hash 与缓存不一致 -> regenerate
#   4. FORCE_REGEN=1               -> regenerate
should_regenerate() {
    local output="$1"; shift
    # 全量重建标记
    [[ "${FORCE_REGEN:-0}" == "1" ]] && return 0
    # output 必须存在
    [[ ! -f "$output" ]] && return 0
    # deps 缓存必须存在
    [[ ! -f "${output}.deps" ]] && return 0
    # 计算当前 sources 的合并 hash 字符串
    local sources_combined=""
    local src h
    for src in "$@"; do
        h=$(file_hash "$src")
        sources_combined+="$src:$h;"
    done
    # 加入 output 自身的 hash（保证 output 被手动改过后能重新生成）
    sources_combined+="output:$(file_hash "$output");"
    # 与缓存对比（deps 文件可能有末尾换行，用 printf %s 去掉）
    local cached
    cached=$(deps_content "$output")
    [[ "$cached" != "$sources_combined" ]] && return 0
    return 1
}

# mark_generated <output_path> <source_files...>
# 把 sources 的合并 hash 写入 ${output}.deps 供下次比对。
mark_generated() {
    local output="$1"; shift
    local combined="" src h
    for src in "$@"; do
        h=$(file_hash "$src")
        combined+="$src:$h;"
    done
    combined+="output:$(file_hash "$output");"
    # 用 heredoc 写入避免 echo 的特殊字符问题
    printf '%s\n' "$combined" > "${output}.deps"
}

# deps_content <output_path>
# 输出 ${output}.deps 的逻辑内容（去掉末尾换行），用于比对。
# 当 deps 文件不存在时返回空字符串。
deps_content() {
    local deps="${1}.deps"
    [[ -f "$deps" ]] || { echo ""; return 0; }
    # 用 cat 读内容，sed 去掉末尾换行
    sed '$ { s/[[:space:]]*$//; }' "$deps"
}

# 状态输出包装
status_skip() { printf '  [SKIP] %s\n' "$*"; }
# ---------- v11: 10 rock-solid ASCII animations ----------
# 设计原则 (适合任何终端 — xterm / Ghostty / WezTerm / iTerm / VSCode):
#   1. **只用单行覆盖 (\r)** 或 **纯滚动 (\n)** — 不再用相对光标移动
#   2. **每帧结束必有 \033[0m 复位颜色**
#   3. **绝不 \033[2J 清屏** — 永远不要再用
#   4. **绝对定位只用于单行内** (\033[0G 等价 \r)
#   5. NO_ANIM=1 或 TERM=dumb 或非 TTY → 输出占位文字，无 ANSI 噪声

# _anim_safe — 决定是否跑动画
# 返回 0 = 可以跑；非 0 = 跳过（动画函数自己处理占位文字）
_anim_safe() {
    [[ -n "${NO_ANIM:-}" ]] && return 1
    [[ ! -t 1 ]] && return 1
    [[ "${TERM:-}" == "dumb" ]] && return 1
    return 0
}

# 1. matrix_rain — 单行滚动数字雨 (不再尝试 in-place 覆盖)
# 每帧一行，行内有彩色随机字符；多个 cycle 自然滚动
matrix_rain() {
    _anim_safe || { printf '  [MATRIX RAIN]\n'; return 0; }
    local cols="${1:-60}" cycles="${2:-8}"
    local chars='0123456789ABCDEF$#@%&'
    for _ in $(seq 1 "$cycles"); do
        line="  "
        for c in $(seq 1 "$cols"); do
            ch="${chars:$((RANDOM % ${#chars})):1}"
            # 头部高亮（首字符），其余绿色
            if (( c == 1 )); then
                line+=$'\033[1;37m'"$ch"
            elif (( RANDOM % 8 == 0 )); then
                line+=$'\033[1;32m'"$ch"
            else
                line+=$'\033[0;32m'"$ch"
            fi
        done
        printf '%b\033[0m\n' "$line"
        sleep 0.1
    done
}

# 2. fire — 单行火焰 (随机颜色字符)
fire() {
    _anim_safe || { printf '  [FIRE]\n'; return 0; }
    local width="${1:-40}" cycles="${2:-10}"
    local palette=' .:;+xX#@'
    for _ in $(seq 1 "$cycles"); do
        line="  "
        for c in $(seq 1 "$width"); do
            idx=$((RANDOM % ${#palette}))
            ch="${palette:$idx:1}"
            # 随机选色
            r=$((RANDOM % 3))
            if (( r == 0 )); then line+=$'\033[1;31m'"$ch"
            elif (( r == 1 )); then line+=$'\033[1;33m'"$ch"
            else line+=$'\033[0;33m'"$ch"
            fi
        done
        printf '%b\033[0m\n' "$line"
        sleep 0.15
    done
}

# 3. lightning — 单行整行反色闪烁
lightning() {
    _anim_safe || { printf '  [LIGHTNING]\n'; return 0; }
    local flashes="${1:-5}"
    local cols=$(tput cols 2>/dev/null || echo 80)
    local blank
    blank=$(printf '%*s' "$cols" "")
    for _ in $(seq 1 "$flashes"); do
        printf '\r\033[7m  *** LIGHTNING ***\033[0m\033[K'  # 反色 + 清行
        sleep 0.08
        printf '\r%s\033[K' "$blank"
        sleep 0.3
    done
    printf '\r%s\033[0m\n' "$blank"
}

# 4. scanline — 单行进度条 (用 \r 覆盖，每 cycle 结束换行)
scanline() {
    _anim_safe || { printf '  [SCAN]\n'; return 0; }
    local text="${1:-Scanning}" width="${2:-50}" cycles="${3:-2}"
    for _ in $(seq 1 "$cycles"); do
        for i in $(seq 0 "$width"); do
            line="  "
            for j in $(seq 1 "$width"); do
                if (( j == i )); then line+=$'\033[1;32m#'
                elif (( j == i - 1 || j == i + 1 )); then line+=$'\033[0;32m='
                else line+=" "; fi
            done
            printf '\r%s\033[0m %s' "$line" "$text"
            sleep 0.02
        done
        printf '\n'
    done
    printf '\033[0m'
}

# 5. glitch — 单行抖动
glitch() {
    _anim_safe || { printf '  [GLITCH]\n'; return 0; }
    local text="${1:-GLITCH}" cycles="${2:-8}"
    local chars='!@#$%^&*<>?/\\|'
    for _ in $(seq 1 "$cycles"); do
        out="  "
        for ((i=0; i<${#text}; i++)); do
            if (( RANDOM % 4 == 0 )); then
                idx=$((RANDOM % ${#chars}))
                out+=$'\033[1;35m'"${chars:$idx:1}"$'\033[0m'
            else
                out+=$'\033[0;31m'"${text:$i:1}"$'\033[0m'
            fi
        done
        printf '\r%s' "$out"
        sleep 0.08
    done
    printf '\r  \033[1;32m%s\033[0m\n' "$text"
}

# 6. holo — 单行字样 (5 个变体滚动, 每行一种色调)
# 不用 in-place 覆盖，而是让多行自然滚动
holo() {
    _anim_safe || { printf '  [HOLO]\n'; return 0; }
    local text="${1:-SIMPLE_MODEL}" width="${2:-40}"
    local colors=('1;31' '1;33' '1;32' '1;36' '1;35')
    # 中心位置
    local pad=$(( (width - ${#text}) / 2 ))
    [[ $pad -lt 0 ]] && pad=0
    local prefix
    prefix=$(printf '%*s' "$pad" "")
    # 每个 color 一行
    for color in "${colors[@]}"; do
        printf '%s  \033[%sm%s\033[0m\n' "$prefix" "$color" "$text"
        sleep 0.2
    done
}

# 7. aurora — 单行波浪 (彩色 ~)
aurora() {
    _anim_safe || { printf '  [AURORA]\n'; return 0; }
    local cols="${1:-50}" cycles="${2:-8}"
    local colors=('1;35' '1;36' '1;32' '1;33' '1;34')
    for _ in $(seq 1 "$cycles"); do
        line="  "
        for c in $(seq 1 "$cols"); do
            idx=$((RANDOM % ${#colors[@]}))
            line+=$'\033['"${colors[$idx]}"$'m~'
        done
        printf '%b\033[0m\n' "$line"
        sleep 0.12
    done
}

# 8. snowflake — 单行雪花
snowflake() {
    _anim_safe || { printf '  [SNOWFLAKE]\n'; return 0; }
    local cols="${1:-50}" cycles="${2:-8}"
    local flakes='*+.~'
    for _ in $(seq 1 "$cycles"); do
        line="  "
        for c in $(seq 1 "$cols"); do
            if (( RANDOM % 7 == 0 )); then
                idx=$((RANDOM % ${#flakes}))
                line+=$'\033[1;37m'"${flakes:$idx:1}"$'\033[0m'
            else line+=" "; fi
        done
        printf '%s\n' "$line"
        sleep 0.12
    done
}

# 9. typewriter_fast — 单行打字机
typewriter_fast() {
    _anim_safe || { printf '%s\n' "$1"; return 0; }
    local text="$1" delay="${2:-0.01}"
    for ((i=0; i<${#text}; i++)); do
        printf '%s' "${text:$i:1}"
        sleep "$delay"
    done
    echo ""
}

# 10. rainbow_progress — 单行彩色进度条 (Bug fix: 末尾复位)
rainbow_progress() {
    _anim_safe || { printf '  %s [done]\n' "$1"; return 0; }
    local label="${1:-Working}" width="${2:-40}"
    local colors=('1;31' '1;33' '1;32' '1;36' '1;34' '1;35')
    for pct in 0 10 20 30 40 50 60 70 80 90 100; do
        filled=$(( pct * width / 100 ))
        printf '\r  %s [' "$label"
        for i in $(seq 0 $((filled - 1))); do
            color_idx=$((i % ${#colors[@]}))
            printf '\033[%sm#\033[0m' "${colors[$color_idx]}"
        done
        printf '\033[0;37m'
        for i in $(seq $filled $((width - 1))); do printf ' '; done
        printf '\033[0m] %3d%%' "$pct"
        sleep 0.04
    done
    printf '\033[0m\n'
}

# 11. loading_bars — 多条进度条 (单行，用 \r 覆盖，分号隔开)
loading_bars() {
    _anim_safe || { printf '  [LOADING]\n'; return 0; }
    local n="${1:-5}" width="${2:-15}" duration="${3:-2}"
    declare -a pcts
    for i in $(seq 0 $((n - 1))); do pcts[$i]=0; done
    end=$((SECONDS + duration))
    while (( SECONDS < end )); do
        printf '\r'
        for i in $(seq 0 $((n - 1))); do
            pcts[$i]=$(( (pcts[$i] + RANDOM % 15 + 5) % 110 ))
            [[ ${pcts[$i]} -gt 100 ]] && pcts[$i]=100
            filled=$(( pcts[$i] * width / 100 ))
            empty=$((width - filled))
            bar=$(printf '█%.0s' $(seq 1 $filled 2>/dev/null))$(printf '░%.0s' $(seq 1 $empty 2>/dev/null))
            printf '\033[1;36mT%d\033[0m[\033[1;32m%s\033[0m]' "$((i+1))" "$bar"
        done
        printf '\033[0m'
        sleep 0.15
    done
    printf '\n'
}

# 12. hologram_intro — 综合 4 个单行动画 (扫描 + 全息 + 打字 + 进度条)
hologram_intro() {
    local title="${1:-SIMPLE_MODEL}" subtitle="${2:-AI-Native Project Orchestrator}"
    scanline "INITIALIZING..." 40 1
    echo ""
    holo "$title" 50
    echo ""
    typewriter_fast "  $subtitle" 0.02
    rainbow_progress "BOOT" 50
}

# 模板系统由 generators/_templates.sh 提供 (Agent 1 创建)
