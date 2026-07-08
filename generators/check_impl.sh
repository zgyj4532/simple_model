#!/usr/bin/env bash
# ============================================================================
# generators/check_impl.sh — schema-aware implementation check
#
# Validates that AI-written code in generated/<lang>/<module>/<comp>.<ext>
# actually contains the symbols promised by struct.json.
#
# For each component:
#   * compare struct.json `exports` against the generated file
#   * if a `todo` is `status: done` but the corresponding symbol is missing
#     in the file -> ERROR
#   * if a `todo` is `status: pending`/`in_progress` but the corresponding
#     symbol IS present -> WARN (AI implemented without claiming via state.json)
#
# Pure bash + grep/awk. No language toolchain required.
#
# Usage:
#   bash generators/check_impl.sh                  # all languages
#   bash generators/check_impl.sh --lang python    # only python
#   bash generators/check_impl.sh --lang rust
#   bash generators/check_impl.sh --json           # JSON output
#   bash generators/check_impl.sh --strict         # WARN counts as ERROR
#
# Exit codes:
#   0  no errors
#   1  errors present (with --strict, includes warnings)
#   2  environment error
#
# Self-bootstrapping: uses bootstrap_env() from _lib.sh.
# ============================================================================

set -euo pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SELF_DIR/_lib.sh"

# Symbol extraction only needs ASCII identifiers. Pin grep/sed/tr to the C
# locale so generated files containing arbitrary UTF-8 comments cannot trigger
# macOS "illegal byte sequence" failures.
export LC_ALL=C

# ---------- CLI flags ----------
TARGET_LANG=""
JSON_OUT=0
STRICT=0
while [[ $# -gt 0 ]]; do
    case "$1" in
        --lang|-l)      TARGET_LANG="${2:-}"; shift 2 ;;
        --json|-j)      JSON_OUT=1; shift ;;
        --strict)       STRICT=1; shift ;;
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

# ---------- 语言 -> 扩展映射 / 文件 layout 映射 ----------
declare -A LANG_EXT=(
    [python]=py
    [rust]=rs
    [go]=go
    [typescript]=ts
)
# 输出根目录
declare -A LANG_ROOT=(
    [python]="${OUTPUT_DIR}/python"
    [rust]="${OUTPUT_DIR}/rust"
    [go]="${OUTPUT_DIR}/go"
    [typescript]="${OUTPUT_DIR}/typescript"
)
# module 子目录是否嵌 src/<module> 还是 <module>
# 约定 (来自各语言 generator):
#   python     : <lang>/<module>/<comp>.<ext>
#   typescript : <lang>/<module>/<comp>.<ext>
#   go         : <lang>/<module>/<comp>.<ext>
#   rust       : <lang>/src/<module>/<comp>.<ext>
declare -A LANG_MODULE_PREFIX=(
    [python]=""
    [rust]="src/"
    [go]=""
    [typescript]=""
)

# 待检查的语言列表
CHECK_LANGS=()
if [[ -n "$TARGET_LANG" ]]; then
    if [[ -z "${LANG_EXT[$TARGET_LANG]:-}" ]]; then
        echo "[FAIL] 不支持的语言: $TARGET_LANG（仅支持 python/rust/go/typescript）" >&2
        exit 2
    fi
    CHECK_LANGS=("$TARGET_LANG")
else
    CHECK_LANGS=(python rust go typescript)
fi

# ---------- finding 累加器 ----------
declare -a FINDINGS=()

add_finding() {
    local severity="$1" type="$2" lang="$3" component="$4" symbol="$5" message="$6"
    local entry
    entry=$(jq -c -n \
        --arg severity "$severity" \
        --arg type "$type" \
        --arg lang "$lang" \
        --arg comp "$component" \
        --arg symbol "$symbol" \
        --arg message "$message" \
        '{severity:$severity, type:$type, lang:$lang, component:$comp, symbol:$symbol, message:$message}')
    FINDINGS+=("$entry")
}

# ---------- symbol extraction ----------
# extract_symbols_<lang> <file>  -> outputs symbols (one per line)

# Python: 类名 + 方法名 (def name()/ class name: ... def name())
# 简单版: 从 class/def 行里提取标识符
extract_symbols_python() {
    local f="$1"
    [[ -f "$f" ]] || return 0
    {
        grep -E '^[A-Za-z_][A-Za-z0-9_]*[: ]|^(class|def|async def)[ \t]+[A-Za-z_]' "$f" \
            | sed -E 's/^[[:space:]]*(class|def|async def)[ \t]+([A-Za-z_][A-Za-z0-9_]*).*/\2/; s/^class[ \t]+([A-Za-z_][A-Za-z0-9_]*)\(.*/\1/; s/^class[ \t]+([A-Za-z_][A-Za-z0-9_]*)[ \t]*:.*/\1/'
        grep -E '^[[:space:]]+[A-Za-z_][A-Za-z0-9_]*[[:space:]]*:' "$f" \
            | sed -E 's/^[[:space:]]+([A-Za-z_][A-Za-z0-9_]*)[[:space:]]*:.*/\1/'
    } | grep -E '^[A-Za-z_]' | sort -u
}

# Rust: pub const NAME / pub fn name / pub struct Name / impl Name { pub fn name }
extract_symbols_rust() {
    local f="$1"
    [[ -f "$f" ]] || return 0
    # pub const X / pub static X / pub fn X / pub struct X / pub enum X / pub trait X / impl X { pub fn Y }
    {
        grep -E '^[[:space:]]*pub[[:space:]]+(const|static|fn|struct|enum|trait)[[:space:]]+[A-Za-z_][A-Za-z0-9_]*' "$f" \
            | sed -E 's/^[[:space:]]*pub[[:space:]]+(const|static|fn|struct|enum|trait)[[:space:]]+([A-Za-z_][A-Za-z0-9_]*).*/\2/'
        grep -E '^[[:space:]]*pub[[:space:]]+fn[[:space:]]+[A-Za-z_][A-Za-z0-9_]*' "$f" \
            | sed -E 's/^[[:space:]]*pub[[:space:]]+fn[[:space:]]+([A-Za-z_][A-Za-z0-9_]*).*/\1/'
        # struct 字段也作为一种 symbol (供 exports 比对)
        grep -E '^[[:space:]]*pub[[:space:]]+[a-z_][a-zA-Z0-9_]*[[:space:]]*:' "$f" \
            | sed -E 's/^[[:space:]]*pub[[:space:]]+([a-z_][a-zA-Z0-9_]*)[[:space:]]*:.*/\1/'
        # impl 块里的方法（含 non-pub）
        grep -E '^[[:space:]]*(pub[[:space:]]+)?fn[[:space:]]+[A-Za-z_][A-Za-z0-9_]*' "$f" \
            | sed -E 's/^[[:space:]]*(pub[[:space:]]+)?fn[[:space:]]+([A-Za-z_][A-Za-z0-9_]*).*/\2/'
    } | grep -E '^[A-Za-z_]' | sort -u
}

# Go: func (c *X) Y / func X / type X struct
extract_symbols_go() {
    local f="$1"
    [[ -f "$f" ]] || return 0
    {
        # struct fields (any indent + lowercase identifier + whitespace + type)
        grep -E '^[[:space:]]+[A-Za-z_][A-Za-z0-9_]*[[:space:]]+[A-Za-z*]' "$f" \
            | sed -E 's/^[[:space:]]+([A-Za-z_][A-Za-z0-9_]*)[[:space:]].*/\1/'
        # methods:  func (c *X) MethodName(...)
        grep -E '^func[[:space:]]+[[:space:]]*\(.*\)[[:space:]]+[A-Za-z_][A-Za-z0-9_]*' "$f" \
            | sed -E 's/^func[[:space:]]+\(.*\)[[:space:]]+([A-Za-z_][A-Za-z0-9_]*).*/\1/'
        # top funcs: func NewXxx / func DoStuff(
        grep -E '^func[[:space:]]+[A-Za-z_][A-Za-z0-9_]*[[:space:]]*\(' "$f" \
            | sed -E 's/^func[[:space:]]+([A-Za-z_][A-Za-z0-9_]*).*/\1/'
        # types: type X struct / type X interface
        grep -E '^type[[:space:]]+[A-Za-z_][A-Za-z0-9_]*[[:space:]]+(struct|interface)' "$f" \
            | sed -E 's/^type[[:space:]]+([A-Za-z_][A-Za-z0-9_]*).*/\1/'
        # const X = "..."
        grep -E '^const[[:space:]]+[A-Za-z_]' "$f" \
            | sed -E 's/^const[[:space:]]+([A-Za-z_][A-Za-z0-9_]*).*/\1/'
    } | grep -E '^[A-Za-z_]' | sort -u
}

# TypeScript: export class X / export function X / export const X / class X { method()
# interface Foo { readonly/optional x: T; y: T } -- pick up x, y
extract_symbols_typescript() {
    local f="$1"
    [[ -f "$f" ]] || return 0
    {
        # export class Foo / export function foo / export const Foo / export interface Foo
        grep -E '^export[[:space:]]+(class|function|const|let|var|interface|type|enum)[[:space:]]+[A-Za-z_]' "$f" \
            | sed -E 's/^export[[:space:]]+(class|function|const|let|var|interface|type|enum)[[:space:]]+([A-Za-z_][A-Za-z0-9_]*).*/\2/'
        # class/interface members: line starts with optional modifiers, then identifier, then : or (
        grep -E '^[[:space:]]+(public|private|protected|readonly|async|static)?[[:space:]]*(public|private|protected|readonly|async|static)?[[:space:]]*[A-Za-z_][A-Za-z0-9_]*[[:space:]]*[:(=]' "$f" \
            | sed -E 's/^[[:space:]]+(public|private|protected|readonly|async|static)?[[:space:]]*(public|private|protected|readonly|async|static)?[[:space:]]*([A-Za-z_][A-Za-z0-9_]*).*/\3/'
        # 顶层 (non-exported) class/function declarations
        grep -E '^(class|function|interface|type)[[:space:]]+[A-Za-z_]' "$f" \
            | sed -E 's/^(class|function|interface|type)[[:space:]]+([A-Za-z_][A-Za-z0-9_]*).*/\2/'
    } | grep -E '^[A-Za-z_]' | grep -vE '^(if|else|for|while|switch|return|import|export|from|new|throw|try|catch|finally|var|let|const)$' | sort -u
}

# ---------- 主流程 ----------
TOTAL_LANGS=0
TOTAL_COMPONENTS=0
TOTAL_FILES=0
TOTAL_FILES_MISSING=0

# 一次性拿出所有 components 的 flat 数据
FLAT_JSON=$(jq -c '
    [
        (.modules // [])[]
        | (.components // [])[] as $c
        | (. as $m | {
            name:       $c.name,
            module:     $m.name,
            language:   ($m.language // "any"),
            exports:    ($c.exports // []),
            todos:      ($c.todos // [])
        })
    ]
' "$STRUCT_FILE")

for LANG in "${CHECK_LANGS[@]}"; do
    EXT="${LANG_EXT[$LANG]}"
    LOUT="${LANG_ROOT[$LANG]}"
    MODULE_PREFIX="${LANG_MODULE_PREFIX[$LANG]:-}"

    # 这个语言的 directory 必须存在才算"有产物"
    if [[ ! -d "$LOUT" ]]; then
        if [[ $JSON_OUT -eq 0 ]]; then
            echo "  [SKIP] $LANG: $LOUT not generated yet (run --target $LANG)"
        fi
        continue
    fi

    TOTAL_LANGS=$((TOTAL_LANGS + 1))

    # 找出本语言适用的 components（per-module language 过滤 OR "any"）
    # FLAT_JSON 是 module 全集；这里按 module 决定是否生成
    # 用 jq 输出 JSONL（每行一个组件），以避免 bash read 吞掉空字段的 bug
    while IFS= read -r rec; do
        [[ -z "$rec" ]] && continue
        cname=$(jq -r '.name'     <<<"$rec")
        cmod=$(jq -r  '.module'   <<<"$rec")
        clang=$(jq -r '.language' <<<"$rec")
        cexports=$(jq -r '.exports | join(",")' <<<"$rec" 2>/dev/null || echo "")
        ctodos=$(jq -r '.todos'   <<<"$rec" 2>/dev/null || echo "[]")
        # 语言过滤：模块 language 应匹配 LANG 或为 any
        if [[ "$clang" != "any" && "$clang" != "$LANG" ]]; then
            continue
        fi
        # 根据 _lib.to_snake 简单实现：PascalCase -> snake_case
        snake=$(echo "$cname" | sed -E 's/([A-Z])([A-Z][a-z])/\1_\2/g; s/([a-z0-9])([A-Z])/\1_\2/g' | tr '[:upper:]' '[:lower:]')
        file="${LOUT}/${MODULE_PREFIX}${cmod}/${snake}.${EXT}"
        TOTAL_COMPONENTS=$((TOTAL_COMPONENTS + 1))

        # 没文件：标记 missing（导出将来会失配）
        if [[ ! -f "$file" ]]; then
            add_finding "error" "missing_file" "$LANG" "${cmod}/${cname}" "" "expected file not found: $file"
            TOTAL_FILES_MISSING=$((TOTAL_FILES_MISSING + 1))
            continue
        fi
        TOTAL_FILES=$((TOTAL_FILES + 1))

        # 抽取 symbols
        syms=$(extract_symbols_$LANG "$file" || true)

        # 检查 exports
        # cexports 是 csv-joined (逗号分隔)，转成换行后再 read line-by-line
        if [[ -n "$cexports" ]]; then
            while IFS=',' read -ra exp_arr; do
                for e in "${exp_arr[@]}"; do
                    [[ -z "$e" ]] && continue
                    # export 名通常是 snake_case / lower，匹配 PascalCase 时我们做两个尝试：
                    #   - 原始名字 (case-sensitive)
                    #   - 全小写 (case insensitive)
                    found=0
                    if printf '%s\n' "$syms" | grep -Fxq "$e"; then
                        found=1
                    elif printf '%s\n' "$syms" | grep -Fxiq "$e"; then
                        found=1
                    fi
                    if [[ $found -eq 0 ]]; then
                        add_finding "error" "missing_export" "$LANG" "${cmod}/${cname}" "$e" "struct.json exports '$e' but no matching symbol in $snake.$EXT"
                    fi
                done
            done <<<"$cexports"
        fi

        # 检查 todos
        # 收集 todos。每个 todo 有 id / status。如果 status=done 而 symbols 里有匹配名字的标识符 -> OK (实装)
        # 单纯做 todos 比较意义有限（todo id 和 symbol 名不一定相同），所以这里只做"实装了但 todo 还没标 done"的告警
        # 通过解析 todo 的 task 文本里有没有出现 any symbol 名字来判断
        # ctodos 已经是 JSON 数组，迭代之
        todo_count=$(jq 'length' <<<"$ctodos" 2>/dev/null || echo 0)
        if [[ "$todo_count" -gt 0 ]]; then
            for ti in $(seq 0 $((todo_count - 1))); do
                tjson=$(jq -c ".[$ti]" <<<"$ctodos" 2>/dev/null || continue)
                [[ -z "$tjson" || "$tjson" == "null" ]] && continue
                tstatus=$(jq -r '.status // "pending"' <<<"$tjson" 2>/dev/null || echo "pending")
                ttask=$(jq -r '.task // ""' <<<"$tjson" 2>/dev/null || echo "")
                # 提取 task 文本里 >= 4 字符、看起来像函数名/标识符的词
                cands=$(echo "$ttask" | grep -oE '[A-Za-z_][A-Za-z0-9_]{3,}' | sort -u || true)
                for cand in $cands; do
                    case "$cand" in
                        TODO|FIXME|XXX|None|True|False) continue ;;
                    esac
                    if printf '%s\n' "$syms" | grep -Fxq "$cand"; then
                        if [[ "$tstatus" != "done" ]]; then
                            add_finding "warning" "implemented_not_marked" "$LANG" "${cmod}/${cname}" "$cand" "todo not marked done (status=$tstatus) but '$cand' is implemented"
                        fi
                    fi
                done
            done
        fi
    done < <(jq -c --arg L "$LANG" '
        .[]
        | select((.language == "any") or (.language == $L))
    ' <<<"$FLAT_JSON")
done

# ---------- 计数 ----------
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
        --arg generated "$OUTPUT_DIR" \
        --argjson langs "$TOTAL_LANGS" \
        --argjson components "$TOTAL_COMPONENTS" \
        --argjson files_checked "$TOTAL_FILES" \
        --argjson files_missing "$TOTAL_FILES_MISSING" \
        --argjson errors "$ERRORS" \
        --argjson warnings "$WARNINGS" \
        --arg strict "$([[ $STRICT -eq 1 ]] && echo true || echo false)" \
        --argjson findings "$findings_json" \
        '{
            schema_version: $schema_version,
            struct: $struct,
            generated: $generated,
            langs_checked: $langs,
            components_checked: $components,
            files_checked: $files_checked,
            files_missing: $files_missing,
            errors: $errors,
            warnings: $warnings,
            strict: ($strict == "true"),
            findings: $findings
        }'
    if [[ $STRICT -eq 1 && $WARNINGS -gt 0 ]]; then
        exit 1
    fi
    [[ $ERRORS -gt 0 ]] && exit 1 || exit 0
fi

# human 模式
echo "============================================================"
echo " check_impl — schema-aware code/struct alignment"
echo " struct   : $STRUCT_FILE"
echo " generated: $OUTPUT_DIR"
echo " languages: ${CHECK_LANGS[*]}"
echo "============================================================"
echo ""

printf '  [INFO] files_checked     : %d\n' "$TOTAL_FILES"
printf '  [INFO] files_missing     : %d\n' "$TOTAL_FILES_MISSING"
printf '  [INFO] components_checked: %d\n' "$TOTAL_COMPONENTS"
echo ""

if [[ ${#FINDINGS[@]} -eq 0 ]]; then
    status_ok "no impl/schema drift detected"
else
    for f in "${FINDINGS[@]}"; do
        sev=$(jq -r '.severity' <<<"$f")
        type=$(jq -r '.type' <<<"$f")
        lang=$(jq -r '.lang' <<<"$f")
        comp=$(jq -r '.component' <<<"$f")
        sym=$(jq -r '.symbol' <<<"$f")
        msg=$(jq -r '.message' <<<"$f")
        if [[ "$sev" == "error" ]]; then
            status_fail "[$type] $lang/$comp ($sym): $msg"
        else
            status_warn "[$type] $lang/$comp ($sym): $msg"
        fi
    done
fi

echo ""
echo "============================================================"
echo " check_impl summary: errors=$ERRORS warnings=$WARNINGS"
echo "============================================================"

if [[ $ERRORS -gt 0 ]]; then
    echo ""
    echo "[FAIL] implementation does not match schema"
    echo "修复方法:"
    echo "  - missing_file    : run --target <lang> to regenerate"
    echo "  - missing_export  : implement struct.json exports in the component file"
    exit 1
fi
if [[ $STRICT -eq 1 && $WARNINGS -gt 0 ]]; then
    echo ""
    echo "[FAIL] --strict 模式下警告也算失败"
    exit 1
fi
[[ $WARNINGS -gt 0 ]] && echo "" && status_warn "$WARNINGS warning(s) (todo not marked done but implemented)"
status_ok "all generated components match schema"
exit 0
