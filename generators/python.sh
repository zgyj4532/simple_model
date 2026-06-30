#!/usr/bin/env bash
# generators/python.sh — Python 代码骨架生成器（纯 bash + jq）
# 约定: PascalCase 组件 -> snake_case 文件，class 封装
# 模板: 若 templates/python/<name>.tpl 存在, 用 render_template 渲染;
#       否则回退到内联 heredoc (向后兼容)。
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/_lib.sh"
source "$(dirname "${BASH_SOURCE[0]}")/_templates.sh"

LANG="python"
LANG_DIR="${OUTPUT_DIR}/${LANG}"
# 布局: $LANG_DIR/<module>/<comp>.py + $LANG_DIR/<module>/__init__.py
#       $LANG_DIR/base.py
mkdir -p "$LANG_DIR"

# ---------- 模板渲染助手 ----------
# 把 vars_file (key=value 格式) 渲染到 out_path。
# 若 tpl 不存在则返回 1, 让调用方决定是否走回退 heredoc。
render_to_file() {
    local out_path="$1" lang="$2" tpl_name="$3" vars_file="$4"
    local tpl
    tpl=$(find_template "$lang" "$tpl_name")
    [[ -z "$tpl" ]] && return 1
    mkdir -p "$(dirname "$out_path")"
    render_template "$lang" "$tpl_name" "$vars_file" > "$out_path"
    return 0
}

# to_py_list (保留以备兼容)
to_py_list() {
    jq -c '.' <<<"$1" | sed "s/^\[//; s/\]$//; s/^\"//; s/\"$//"
}

# 每个 module 的处理
N_MODULES=$(jq '.modules // [] | length' "$STRUCT_FILE")
for mi in $(seq 0 $((N_MODULES - 1))); do
    module_json=$(read_module "$mi")
    module_name=$(echo "$module_json" | jq -r '.name')
    module_lang=$(echo "$module_json" | jq -r '.language')
    module_desc=$(echo "$module_json" | jq -r '.description')

    # per-module language 过滤
    if [[ "$module_lang" != "any" && "$module_lang" != "$LANG" ]]; then
        say "跳过 ${module_name}（language=${module_lang}，不是 ${LANG}）"
        continue
    fi

    module_dir="${LANG_DIR}/${module_name}"
    mkdir -p "$module_dir"

    # __init__.py — 自动导出所有 component
    init_py="${module_dir}/__init__.py"
    if should_regenerate "$init_py" "$STRUCT_FILE"; then
        exports_lines=""
        while IFS= read -r comp; do
            [[ -z "$comp" ]] && continue
            snake_comp=$(to_snake "$comp")
            exports_lines+="from .${snake_comp} import ${comp}  # noqa: F401"$'\n'
        done < <(jq -r ".modules[$mi].components[].name" "$STRUCT_FILE")

        vars_file=$(mktemp)
        {
            printf 'module_name=%s\n' "$(encode_value "${module_name}")"
            printf 'module_description=%s\n' "$(encode_value "${module_desc}")"
            printf 'exports_lines=%s\n' "$(encode_value "${exports_lines}")"
        } > "$vars_file"

        if ! render_to_file "$init_py" "python" "module_init" "$vars_file"; then
            # 回退: 内联 heredoc (向后兼容)
            cat > "$init_py" <<EOF
"""Module: ${module_name}

${module_desc}
"""
${exports_lines}
EOF
        fi
        rm -f "$vars_file"
        mark_generated "$init_py" "$STRUCT_FILE"
        say "  [OK] ${LANG_DIR#$OUTPUT_DIR/}/${module_name}/__init__.py"
    else
        say "  [SKIP] ${LANG_DIR#$OUTPUT_DIR/}/${module_name}/__init__.py (unchanged)"
    fi

    # 每个 component 生成文件
    component_count=$(jq ".modules[$mi].components | length" "$STRUCT_FILE")
    for ci in $(seq 0 $((component_count - 1))); do
        c_name=$(jq -r ".modules[$mi].components[$ci].name" "$STRUCT_FILE")
        c_desc=$(jq -r ".modules[$mi].components[$ci].description" "$STRUCT_FILE")
        c_exports=$(jq -c ".modules[$mi].components[$ci].exports // []" "$STRUCT_FILE")
        c_imports=$(jq -c ".modules[$mi].components[$ci].imports // .modules[$mi].components[$ci].depends_on // []" "$STRUCT_FILE")
        c_optional=$(jq -r ".modules[$mi].components[$ci].optional // false" "$STRUCT_FILE")
        c_todos_json=$(jq -c ".modules[$mi].components[$ci].todos // []" "$STRUCT_FILE")
        c_files=$(jq -c ".modules[$mi].components[$ci].files // []" "$STRUCT_FILE")

        snake=$(to_snake "$c_name")

        # 多文件支持
        if [[ "$(echo "$c_files" | jq 'length')" -gt 0 ]]; then
            has_files="true"
            file_0=$(echo "$c_files" | jq -r '.[0]')
            default_test_name="test_${snake}.py"
            test_file=$(echo "$c_files" | jq -r --arg def "${default_test_name}" '.[1] // $def')
            file="${module_dir}/${file_0}"
        else
            has_files="false"
            file="${module_dir}/${snake}.py"
        fi

        if should_regenerate "$file" "$STRUCT_FILE"; then
            if [[ "$c_optional" == "true" ]]; then
                optional_py="True"
            else
                optional_py="False"
            fi

            # 构建 import 块
            imports_block=""
            while IFS= read -r dep; do
                [[ -z "$dep" ]] && continue
                dep_module=$(module_of "$dep")
                [[ -z "$dep_module" ]] && continue
                dep_snake=$(to_snake "$dep")
                if [[ "$dep_module" == "$module_name" ]]; then
                    imports_block+="from .${dep_snake} import ${dep}"$'\n'
                else
                    imports_block+="from ..${dep_module}.${dep_snake} import ${dep}"$'\n'
                fi
            done < <(echo "$c_imports" | jq -r '.[]')

            exports_py=$(echo "$c_exports" | jq -r '. | tostring')
            imports_py=$(echo "$c_imports" | jq -r '. | tostring')

            # todos 注释
            todos_block=""
            if [[ "$(echo "$c_todos_json" | jq 'length')" -gt 0 ]]; then
                todos_block="    # TODO:"$'\n'
                while IFS= read -r line; do
                    [[ -z "$line" ]] && continue
                    todos_block+="    #   - ${line}"$'\n'
                done < <(echo "$c_todos_json" | jq -r '.[] | "\(.id): \(.task) [priority=\(.priority // "medium")] [\(.status // "pending")] blocks=\(.blocks // [])"')
            fi

            # acceptance_criteria 注释 (合并自 todos)
            acceptance_block=""
            if [[ "$(echo "$c_todos_json" | jq 'length')" -gt 0 ]]; then
                ac_raw=$(echo "$c_todos_json" | jq -r '.[] | select(.acceptance_criteria) | "Acceptance: \(.acceptance_criteria)"')
                if [[ -n "$ac_raw" ]]; then
                    while IFS= read -r ac_line; do
                        [[ -z "$ac_line" ]] && continue
                        acceptance_block+="${ac_line}"$'\n'
                    done <<< "$ac_raw"
                fi
            fi

            vars_file=$(mktemp)
            {
                printf 'component_name=%s\n' "$(encode_value "${c_name}")"
                printf 'module_name=%s\n' "$(encode_value "${module_name}")"
                printf 'snake_name=%s\n' "$(encode_value "${snake}")"
                printf 'description=%s\n' "$(encode_value "${c_desc}")"
                printf 'exports_json=%s\n' "$(encode_value "${exports_py}")"
                printf 'imports_json=%s\n' "$(encode_value "${imports_py}")"
                printf 'imports_block=%s\n' "$(encode_value "${imports_block}")"
                printf 'struct_fields=\n'
                printf 'todos_block=%s\n' "$(encode_value "${todos_block}")"
                printf 'acceptance_criteria=%s\n' "$(encode_value "${acceptance_block}")"
                printf 'optional_py=%s\n' "$(encode_value "${optional_py}")"
                printf 'base_class=_BaseComponent\n'
            } > "$vars_file"

            if ! render_to_file "$file" "python" "component" "$vars_file"; then
                # 回退: 内联 heredoc (向后兼容)
                cat > "$file" <<EOF
"""Component: ${c_name} (module: ${module_name})

${c_desc}

Auto-generated by bootstrap.sh — implement __call__().
"""
from typing import Any, List
${imports_block}from ..base import Service as _BaseComponent


class ${c_name}(_BaseComponent):
    """${c_desc}"""

    name: str = "${c_name}"
    exports: List[str] = ${exports_py}
    imports: List[str] = ${imports_py}
    optional: bool = ${optional_py}
${todos_block}    def __call__(self) -> Any:
        """执行 ${c_name} 的核心逻辑"""
        raise NotImplementedError("${c_name}.__call__() 待实现")
EOF
            fi
            rm -f "$vars_file"
            mark_generated "$file" "$STRUCT_FILE"
            say "  [OK] ${module_name}/$(basename "$file")"
        else
            say "  [SKIP] ${module_name}/$(basename "$file") (unchanged)"
        fi

        # 多文件模式下的 test stub
        if [[ "${has_files}" == "true" ]]; then
            tests_dir="${module_dir}/tests"
            mkdir -p "$tests_dir"
            test_path="${tests_dir}/${test_file}"
            if should_regenerate "$test_path" "$STRUCT_FILE"; then
                test_functions=""
                todos_block_py=""
                if [[ "$(echo "$c_todos_json" | jq 'length')" -gt 0 ]]; then
                    while IFS= read -r todo; do
                        [[ -z "$todo" ]] && continue
                        todo_id=$(echo "$todo" | jq -r '.id')
                        todo_task=$(echo "$todo" | jq -r '.task')
                        todo_ac=$(echo "$todo" | jq -r '.acceptance_criteria // ""')
                        todos_block_py+="# TODO ${todo_id}: ${todo_task}"$'\n'
                        if [[ -n "${todo_ac}" && "${todo_ac}" != "null" && "${todo_ac}" != "" ]]; then
                            todos_block_py+="#   acceptance: ${todo_ac}"$'\n'
                        fi
                        test_functions+="def test_${todo_id}():"$'\n'
                        test_functions+="    \"\"\"Auto-stub for todo ${todo_id}: ${todo_task}\"\"\""$'\n'
                        if [[ -n "${todo_ac}" && "${todo_ac}" != "null" && "${todo_ac}" != "" ]]; then
                            test_functions+="    # acceptance: ${todo_ac}"$'\n'
                        fi
                        test_functions+="    # TODO: replace with real assertion"$'\n'
                        test_functions+="    assert True"$'\n'$'\n'
                    done < <(echo "$c_todos_json" | jq -c '.[]')
                fi

                vars_file2=$(mktemp)
                {
                    printf 'component_name=%s\n' "$(encode_value "${c_name}")"
                    printf 'module_name=%s\n' "$(encode_value "${module_name}")"
                    printf 'snake_name=%s\n' "$(encode_value "${snake}")"
                    printf 'todos_block=%s\n' "$(encode_value "${todos_block_py}")"
                    printf 'test_functions=%s\n' "$(encode_value "${test_functions}")"
                } > "$vars_file2"

                if ! render_to_file "$test_path" "python" "test_stub" "$vars_file2"; then
                    # 回退
                    cat > "$test_path" <<EOF
"""Auto-generated test stubs for ${c_name} (module: ${module_name})"""
import pytest
from ..${snake} import ${c_name}
${test_functions}
EOF
                fi
                rm -f "$vars_file2"
                mark_generated "$test_path" "$STRUCT_FILE"
                say "  [OK] ${module_name}/tests/${test_file}"
            else
                say "  [SKIP] ${module_name}/tests/${test_file} (unchanged)"
            fi
        fi
    done

    # per-module todo.json
    if [[ "$(jq "[.modules[$mi].components[].todos // [] | length] | add // 0" "$STRUCT_FILE")" -gt 0 ]]; then
        todo_file="${module_dir}/todo.json"
        if should_regenerate "$todo_file" "$STRUCT_FILE"; then
            module_name_jq=$(jq -r ".modules[$mi].name" "$STRUCT_FILE")
            jq --arg mod "${module_name_jq}" "{module: .modules[$mi].name, description: .modules[$mi].description, todos: [.modules[$mi].components[] | . as \$c | .todos[]? | . + {module: \$mod, component: \$c.name}]}" "${STRUCT_FILE}" \
                > "$todo_file"
            mark_generated "$todo_file" "$STRUCT_FILE"
            say "  [OK] ${module_name}/todo.json"
        else
            say "  [SKIP] ${module_name}/todo.json (unchanged)"
        fi
    fi
done

# 顶层 base.py
mkdir -p "$LANG_DIR"
BASE_PY="${LANG_DIR}/base.py"
if should_regenerate "$BASE_PY" "$STRUCT_FILE"; then
    if ! render_to_file "$BASE_PY" "python" "base" "/dev/null"; then
        cat > "$BASE_PY" <<'PY'
"""Auto-generated base — do not edit, rerun bootstrap.sh"""
from abc import ABC, abstractmethod
from dataclasses import dataclass, field
from typing import Any, Dict, List, Optional, Type


@dataclass
class Service(ABC):
    """所有 component 的抽象基类"""
    name: str = ""
    exports: List[str] = field(default_factory=list)
    imports: List[str] = field(default_factory=list)
    optional: bool = False

    @abstractmethod
    def __call__(self) -> Any:
        raise NotImplementedError(f"{self.__class__.__name__}.__call__() 未实现")


class Registry:
    _r: Dict[str, Type[Service]] = {}
    @classmethod
    def register(cls, c): cls._r[c.name] = c; return c
    @classmethod
    def get(cls, n): return cls._r.get(n)
    @classmethod
    def all(cls): return dict(cls._r)
PY
    fi
    mark_generated "$BASE_PY" "$STRUCT_FILE"
    say "  [OK] base.py"
else
    say "  [SKIP] base.py (unchanged)"
fi

echo "  [OK] python 生成完成: $LANG_DIR/"

# 让整个 $LANG_DIR/ 成为一个可导入的 Python package
PACKAGE_INIT="${LANG_DIR}/__init__.py"
if should_regenerate "$PACKAGE_INIT" "$STRUCT_FILE"; then
    cat > "$PACKAGE_INIT" <<EOF
"""${LANG} — auto-generated package (do not edit)"""
__version__ = "0.1.0"
EOF
    mark_generated "$PACKAGE_INIT" "$STRUCT_FILE"
    say "  [OK] ${LANG_DIR#$OUTPUT_DIR/}/__init__.py (package marker)"
fi

# pyproject.toml — 让 python -m pip install -e . 可用
PYPROJECT="${LANG_DIR}/pyproject.toml"
if should_regenerate "$PYPROJECT" "$STRUCT_FILE"; then
    cat > "$PYPROJECT" <<TOML
[build-system]
requires = ["setuptools>=68", "wheel"]
build-backend = "setuptools.build_meta"

[project]
name = "${LANG}"
version = "0.1.0"
description = "Auto-generated from struct.json by bootstrap.sh"
requires-python = ">=3.9"
dynamic = ["dependencies"]

[tool.setuptools.packages.find]
include = ["${LANG}*"]
TOML
    mark_generated "$PYPROJECT" "$STRUCT_FILE"
    say "  [OK] ${LANG_DIR#$OUTPUT_DIR/}/pyproject.toml"
fi

# 顶层 README + 父 __init__.py
PARENT_DIR="$(dirname "$LANG_DIR")"
PARENT_INIT="${PARENT_DIR}/__init__.py"
if [[ ! -f "$PARENT_INIT" ]]; then
    echo "# Auto-generated parent package marker" > "$PARENT_INIT"
fi
PARENT_PYPROJECT="${PARENT_DIR}/pyproject.toml"
if [[ ! -f "$PARENT_PYPROJECT" && "$LANG_DIR" != "${OUTPUT_DIR}/${LANG}" ]]; then
    cat > "$PARENT_PYPROJECT" <<TOML
[build-system]
requires = ["setuptools>=68", "wheel"]
build-backend = "setuptools.build_meta"

[project]
name = "$(basename "$PARENT_DIR")"
version = "0.1.0"
description = "Auto-generated project root"
requires-python = ">=3.9"
TOML
fi

echo ""
echo "  用法:"
echo "    pip install -e ${LANG_DIR}"
echo "    python3 -c 'from ${LANG}.data import DataLoader; print(DataLoader)'"
