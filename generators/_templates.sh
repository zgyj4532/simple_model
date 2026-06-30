#!/usr/bin/env bash
# generators/_templates.sh — 模板系统辅助函数 (本文件独立于 _lib.sh)
# 提供: find_template, render_template, render_to_file
# 用法: source "$(dirname "${BASH_SOURCE[0]}")/_templates.sh"

# 模板目录: 用户可覆盖 ./templates/<lang>/<name>.tpl, 否则用 ./generators/templates_default/<lang>/<name>.tpl
TEMPLATE_DIR_USER="${TEMPLATE_DIR_USER:-./templates}"
TEMPLATE_DIR_DEFAULT="${GENERATORS_DIR:-$(dirname "${BASH_SOURCE[0]}")}/templates_default"

# find_template <lang> <name> -> 输出 .tpl 完整路径; 找不到输出空
find_template() {
    local lang="$1" name="$2"
    local user_path="$TEMPLATE_DIR_USER/$lang/$name.tpl"
    local default_path="$TEMPLATE_DIR_DEFAULT/$lang/$name.tpl"
    if [[ -f "$user_path" ]]; then
        echo "$user_path"
    elif [[ -f "$default_path" ]]; then
        echo "$default_path"
    else
        echo ""
    fi
}

# render_template <lang> <name> <vars_file>
# vars_file 格式: 用 base64 编码的 key=value 行 (一行一对).
# value 用 base64 是为了支持多行值 (vars 文件里换行 = 新行, 不能直接存).
# 模板里用 {{key}} 占位.
# 用法: 调用方应先把 value 用 encode_value() 编码后写到 vars_file.
render_template() {
    local lang="$1" name="$2"
    local vars="${3:-/dev/stdin}"
    local tpl_path
    tpl_path=$(find_template "$lang" "$name")
    if [[ -z "$tpl_path" ]]; then
        echo "[FAIL] template not found: $lang/$name.tpl" >&2
        return 1
    fi
    # 用 awk 一次读 vars_file 和 tpl_path, 先把 vars 解到 subs[], 再做模板替换
    awk -v vfile="$vars" -v tfile="$tpl_path" '
        BEGIN {
            # 先读 vars_file, 解析 key=base64val, 解码到 subs[]
            while ((getline vline < vfile) > 0) {
                eq = index(vline, "=")
                if (eq > 0) {
                    key = substr(vline, 1, eq - 1)
                    b64 = substr(vline, eq + 1)
                    sub(/\r$/, "", b64)
                    if (b64 == "") {
                        subs[key] = ""
                        continue
                    }
                    # 解 base64 - 必须读完整多行输出
                    cmd = "printf %s \"" b64 "\" | base64 -d 2>/dev/null"
                    val = ""
                    n = 0
                    while ((cmd | getline line) > 0) {
                        if (n > 0) val = val "\n"
                        val = val line
                        n++
                    }
                    close(cmd)
                    subs[key] = val
                }
            }
            close(vfile)
        }
        # 处理模板的每一行
        FILENAME == tfile {
            line = $0
            changed = 1
            while (changed) {
                changed = 0
                start = index(line, "{{")
                if (start > 0) {
                    rest = substr(line, start + 2)
                    close_end = index(rest, "}}")
                    if (close_end > 0) {
                        key = substr(line, start + 2, close_end - 1)
                        if (key in subs) {
                            line = substr(line, 1, start - 1) subs[key] substr(line, start + 2 + close_end + 1)
                            changed = 1
                        } else {
                            break
                        }
                    } else {
                        break
                    }
                }
            }
            print line
        }
    ' "$vars" "$tpl_path"
}

# encode_value <value> -> base64 编码 (无换行, 适合做 vars_file value)
encode_value() {
    printf '%s' "$1" | base64 -w0
}

# 便捷: 把多个 key=value 写到 vars_file, 自动 encode_value
# 用法: write_vars_file <out_file> <<EOF
#         key1=raw value 1
#         key2=raw value 2
#       EOF
write_vars_file() {
    local out="$1"
    : > "$out"
    while IFS='=' read -r key val; do
        [[ -z "$key" || "$key" =~ ^# ]] && continue
        echo "${key}=$(encode_value "$val")" >> "$out"
    done
}

# render_to_file <out_path> <lang> <tpl_name> <vars_file>
# 若模板存在, 渲染并写入; 不存在则返回 1 (回退给调用方).
render_to_file() {
    local out_path="$1" lang="$2" tpl_name="$3" vars_file="$4"
    local tpl
    tpl=$(find_template "$lang" "$tpl_name")
    [[ -z "$tpl" ]] && return 1
    mkdir -p "$(dirname "$out_path")"
    render_template "$lang" "$tpl_name" "$vars_file" > "$out_path"
    return 0
}
