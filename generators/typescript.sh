#!/usr/bin/env bash
# generators/typescript.sh — TypeScript 代码骨架生成器（纯 bash + jq）
# 约定:
#   - PascalCase 组件 -> snake_case 文件名
#   - 每个 component: export interface + export class
#   - 每个 module 一个目录: <module>/index.ts 重导出所有 component
#   - 顶层: tsconfig.json (strict, ES2022) + package.json (ESM)
# 模板: 若 templates/typescript/<name>.tpl 存在, 用 render_template 渲染;
#       否则回退到内联 heredoc (向后兼容)。
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/_lib.sh"
source "$(dirname "${BASH_SOURCE[0]}")/_templates.sh"

LANG="typescript"
LANG_DIR="${OUTPUT_DIR}/${LANG}"
mkdir -p "$LANG_DIR"

# ---------- 顶层: tsconfig.json ----------
PKG_NAME=$(basename "$OUTPUT_DIR")
TSCONFIG_FILE="${LANG_DIR}/tsconfig.json"
if should_regenerate "$TSCONFIG_FILE" "$STRUCT_FILE"; then
    if ! render_to_file "$TSCONFIG_FILE" "typescript" "tsconfig" "/dev/null"; then
        cat > "$TSCONFIG_FILE" <<'TSJSON'
{
  "compilerOptions": {
    "target": "ES2022",
    "module": "ESNext",
    "moduleResolution": "Bundler",
    "lib": ["ES2022", "DOM", "DOM.Iterable"],
    "strict": true,
    "noImplicitAny": true,
    "strictNullChecks": true,
    "esModuleInterop": true,
    "skipLibCheck": true,
    "forceConsistentCasingInFileNames": true,
    "declaration": true,
    "declarationMap": true,
    "sourceMap": true,
    "resolveJsonModule": true,
    "isolatedModules": true,
    "outDir": "./dist",
    "rootDir": "."
  },
  "include": ["./**/*.ts"],
  "exclude": ["node_modules", "dist"]
}
TSJSON
    fi
    mark_generated "$TSCONFIG_FILE" "$STRUCT_FILE"
    say "  [OK] ${LANG_DIR#$OUTPUT_DIR/}/tsconfig.json"
else
    say "  [SKIP] ${LANG_DIR#$OUTPUT_DIR/}/tsconfig.json (unchanged)"
fi

# ---------- 顶层: package.json ----------
PACKAGE_FILE="${LANG_DIR}/package.json"
if should_regenerate "$PACKAGE_FILE" "$STRUCT_FILE"; then
    package_name=$(echo "$PKG_NAME" | tr '[:upper:]' '[:lower:]')
    vars_file=$(mktemp)
    {
        printf 'package_name=%s\n' "$(encode_value "${package_name}")"
    } > "$vars_file"
    if ! render_to_file "$PACKAGE_FILE" "typescript" "package" "$vars_file"; then
        cat > "$PACKAGE_FILE" <<PKGJSON
{
  "name": "${package_name}",
  "version": "0.1.0",
  "description": "Auto-generated TypeScript scaffold",
  "type": "module",
  "main": "./dist/index.js",
  "types": "./dist/index.d.ts",
  "scripts": {
    "build": "tsc",
    "typecheck": "tsc --noEmit",
    "clean": "rm -rf dist"
  },
  "devDependencies": {
    "typescript": "^5.4.0"
  }
}
PKGJSON
    fi
    rm -f "$vars_file"
    mark_generated "$PACKAGE_FILE" "$STRUCT_FILE"
    say "  [OK] ${LANG_DIR#$OUTPUT_DIR/}/package.json"
else
    say "  [SKIP] ${LANG_DIR#$OUTPUT_DIR/}/package.json (unchanged)"
fi

# ---------- 模块与组件 ----------
N_MODULES=$(jq '.modules // [] | length' "$STRUCT_FILE")
for mi in $(seq 0 $((N_MODULES - 1))); do
    module_json=$(read_module "$mi")
    module_name=$(echo "$module_json" | jq -r '.name')
    module_lang=$(echo "$module_json" | jq -r '.language // "any"')
    module_desc=$(echo "$module_json" | jq -r '.description')

    if [[ "$module_lang" != "any" && "$module_lang" != "$LANG" ]]; then
        say "跳过 ${module_name}（language=${module_lang}，不是 ${LANG}）"
        continue
    fi

    module_dir="${LANG_DIR}/${module_name}"
    mkdir -p "$module_dir"

    component_count=$(jq ".modules[$mi].components // [] | length" "$STRUCT_FILE")
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
            file_0=$(echo "$c_files" | jq -r '.[0]')
            file="${module_dir}/${file_0}"
        else
            file="${module_dir}/${snake}.ts"
        fi

        if should_regenerate "$file" "$STRUCT_FILE"; then
            imports_block=""
            while IFS= read -r dep; do
                [[ -z "$dep" ]] && continue
                dep_module=$(module_of "$dep")
                [[ -z "$dep_module" ]] && continue
                dep_snake=$(to_snake "$dep")
                if [[ "$dep_module" == "$module_name" ]]; then
                    imports_block+="import { ${dep} } from \"./${dep_snake}\";"$'\n'
                else
                    imports_block+="import { ${dep} } from \"../${dep_module}/${dep_snake}\";"$'\n'
                fi
            done < <(echo "$c_imports" | jq -r '.[]')

            exports_list=""
            while IFS= read -r e; do
                [[ -z "$e" ]] && continue
                exports_list+=" *   - ${e}"$'\n'
            done < <(echo "$c_exports" | jq -r '.[]')

            todos_block=""
            if [[ "$(echo "$c_todos_json" | jq 'length')" -gt 0 ]]; then
                todos_block=" *"$'\n'" * TODO:"$'\n'
                while IFS= read -r line; do
                    [[ -z "$line" ]] && continue
                    todos_block+=" *   - ${line}"$'\n'
                done < <(echo "$c_todos_json" | jq -r '.[] | "\(.id): \(.task) [priority=\(.priority // "medium")] [status=\(.status // "pending")] blocks=\(.blocks // [])"')
            fi

            ac_block=""
            if [[ "$(echo "$c_todos_json" | jq 'length')" -gt 0 ]]; then
                ac_raw=$(echo "$c_todos_json" | jq -r '.[] | select(.acceptance_criteria) | "* acceptance: \(.acceptance_criteria)"')
                if [[ -n "$ac_raw" ]]; then
                    while IFS= read -r ac_line; do
                        [[ -z "$ac_line" ]] && continue
                        ac_block+=" ${ac_line}"$'\n'
                    done <<< "$ac_raw"
                fi
            fi

            vars_file=$(mktemp)
            {
                printf 'component_name=%s\n' "$(encode_value "${c_name}")"
                printf 'module_name=%s\n' "$(encode_value "${module_name}")"
                printf 'snake_name=%s\n' "$(encode_value "${snake}")"
                printf 'description=%s\n' "$(encode_value "${c_desc}")"
                printf 'exports_list=%s\n' "$(encode_value "${exports_list}")"
                printf 'imports_block=%s\n' "$(encode_value "${imports_block}")"
                printf 'todos_block=%s\n' "$(encode_value "${todos_block}")"
                printf 'acceptance_criteria=%s\n' "$(encode_value "${ac_block}")"
                printf 'optional_ts=%s\n' "$(encode_value "${c_optional}")"
            } > "$vars_file"

            if ! render_to_file "$file" "typescript" "component" "$vars_file"; then
                # 回退
                cat > "$file" <<EOF
/**
 * Component: ${c_name} (module: ${module_name})
 *
 * ${c_desc}
 *
 * Auto-generated by bootstrap.sh — implement call().
${exports_list}${todos_block} */
$(echo "$imports_block" | sed '/^$/d')

/**
 * ${c_desc}
 */
export interface ${c_name}Options {
  readonly name: string;
  readonly optional: boolean;
}

/**
 * ${c_desc}
 *
 * Auto-generated by bootstrap.sh.
 */
export class ${c_name} implements ${c_name}Options {
  public readonly name: string = "${c_name}";
  public readonly optional: boolean = ${c_optional};

  /**
   * 执行 ${c_name} 的核心逻辑
   * 待实现：在子类或本类中填充具体行为
   */
  public call(): unknown {
    throw new Error("${c_name}.call() 待实现");
  }
}

export default ${c_name};
EOF
            fi
            rm -f "$vars_file"
            mark_generated "$file" "$STRUCT_FILE"
            say "  [OK] ${LANG_DIR#$OUTPUT_DIR/}/${module_name}/$(basename "$file")"
        else
            say "  [SKIP] ${LANG_DIR#$OUTPUT_DIR/}/${module_name}/$(basename "$file") (unchanged)"
        fi

        # 多文件模式下的 test stub
        if [[ "$(echo "$c_files" | jq 'length')" -gt 1 ]]; then
            test_filename=$(echo "$c_files" | jq -r '.[1] // "test_'${snake}'.ts"')
            tests_dir="${module_dir}/tests"
            mkdir -p "$tests_dir"
            test_path="${tests_dir}/${test_filename}"
            if should_regenerate "$test_path" "$STRUCT_FILE"; then
                test_functions=""
                todos_block_ts=""
                if [[ "$(echo "$c_todos_json" | jq 'length')" -gt 0 ]]; then
                    while IFS= read -r todo; do
                        [[ -z "$todo" ]] && continue
                        todo_id=$(echo "$todo" | jq -r '.id')
                        todo_task=$(echo "$todo" | jq -r '.task')
                        todo_ac=$(echo "$todo" | jq -r '.acceptance_criteria // ""')
                        todos_block_ts+=" * TODO ${todo_id}: ${todo_task}"$'\n'
                        if [[ -n "${todo_ac}" && "${todo_ac}" != "null" && "${todo_ac}" != "" ]]; then
                            todos_block_ts+=" *   acceptance: ${todo_ac}"$'\n'
                        fi
                        test_functions+="  it(\"should ${todo_task}\", () => {"$'\n'
                        if [[ -n "${todo_ac}" && "${todo_ac}" != "null" && "${todo_ac}" != "" ]]; then
                            test_functions+="    // acceptance: ${todo_ac}"$'\n'
                        fi
                        test_functions+="    // TODO: replace with real assertion"$'\n'
                        test_functions+="    expect(true).toBe(true);"$'\n'
                        test_functions+="  });"$'\n'$'\n'
                    done < <(echo "$c_todos_json" | jq -c '.[]')
                fi

                vars_file2=$(mktemp)
                {
                    printf 'component_name=%s\n' "$(encode_value "${c_name}")"
                    printf 'module_name=%s\n' "$(encode_value "${module_name}")"
                    printf 'snake_name=%s\n' "$(encode_value "${snake}")"
                    printf 'todos_block=%s\n' "$(encode_value "${todos_block_ts}")"
                    printf 'test_functions=%s\n' "$(encode_value "${test_functions}")"
                } > "$vars_file2"

                if ! render_to_file "$test_path" "typescript" "test_stub" "$vars_file2"; then
                    cat > "$test_path" <<EOF
/**
 * Auto-generated test stubs for ${c_name} (module: ${module_name})
 */
import { describe, it, expect } from "vitest";
import { ${c_name} } from "../${snake}";

describe("${c_name}", () => {
${test_functions}});
EOF
                fi
                rm -f "$vars_file2"
                mark_generated "$test_path" "$STRUCT_FILE"
                say "  [OK] ${LANG_DIR#$OUTPUT_DIR/}/${module_name}/tests/${test_filename}"
            else
                say "  [SKIP] ${LANG_DIR#$OUTPUT_DIR/}/${module_name}/tests/${test_filename} (unchanged)"
            fi
        fi
    done

    # ---------- module 的 index.ts ----------
    index_file="${module_dir}/index.ts"
    if should_regenerate "$index_file" "$STRUCT_FILE"; then
        {
            echo "/**"
            echo " * Module: ${module_name}"
            echo " *"
            echo " * ${module_desc}"
            echo " *"
            echo " * Auto-generated by bootstrap.sh"
            echo " */"
            echo ""
            cc=$(jq ".modules[$mi].components // [] | length" "$STRUCT_FILE")
            for ci in $(seq 0 $((cc - 1))); do
                c_name=$(jq -r ".modules[$mi].components[$ci].name" "$STRUCT_FILE")
                c_files_inner=$(jq -c ".modules[$mi].components[$ci].files // []" "$STRUCT_FILE")
                snake=$(to_snake "$c_name")
                if [[ "$(echo "$c_files_inner" | jq 'length')" -gt 0 ]]; then
                    export_filename=$(echo "$c_files_inner" | jq -r '.[0]')
                else
                    export_filename="${snake}.ts"
                fi
                echo "export { ${c_name} } from \"./${export_filename%.ts}\";"
            done
        } > "$index_file"
        mark_generated "$index_file" "$STRUCT_FILE"
        say "  [OK] ${LANG_DIR#$OUTPUT_DIR/}/${module_name}/index.ts"
    else
        say "  [SKIP] ${LANG_DIR#$OUTPUT_DIR/}/${module_name}/index.ts (unchanged)"
    fi

    # ---------- per-module todo.json ----------
    if [[ "$(jq "[.modules[$mi].components[].todos // [] | length] | add // 0" "$STRUCT_FILE")" -gt 0 ]]; then
        todo_file="${module_dir}/todo.json"
        if should_regenerate "$todo_file" "$STRUCT_FILE"; then
            module_todo_json "$mi" "$todo_file"
            mark_generated "$todo_file" "$STRUCT_FILE"
            say "  [OK] ${LANG_DIR#$OUTPUT_DIR/}/${module_name}/todo.json"
        else
            say "  [SKIP] ${LANG_DIR#$OUTPUT_DIR/}/${module_name}/todo.json (unchanged)"
        fi
    fi
done

# ---------- 顶层 src/index.ts ----------
TOP_INDEX="${LANG_DIR}/index.ts"
if should_regenerate "$TOP_INDEX" "$STRUCT_FILE"; then
    {
        echo "/**"
        echo " * ${PKG_NAME} — Auto-generated TypeScript entry point"
        echo " * Auto-generated by bootstrap.sh"
        echo " */"
        echo ""
        for mi in $(seq 0 $((N_MODULES - 1))); do
            mlang=$(jq -r ".modules[$mi].language // \"any\"" "$STRUCT_FILE")
            [[ "$mlang" != "any" && "$mlang" != "$LANG" ]] && continue
            mname=$(jq -r ".modules[$mi].name" "$STRUCT_FILE")
            echo "export * from \"./${mname}\";"
        done
    } > "$TOP_INDEX"
    mark_generated "$TOP_INDEX" "$STRUCT_FILE"
    say "  [OK] ${LANG_DIR#$OUTPUT_DIR/}/index.ts"
else
    say "  [SKIP] ${LANG_DIR#$OUTPUT_DIR/}/index.ts (unchanged)"
fi

# ---------- tsc 校验 ----------
if command -v tsc >/dev/null 2>&1; then
    echo ""
    say "  ▶ tsc --noEmit ..."
    if (cd "$LANG_DIR" && tsc --noEmit --pretty false 2>&1); then
        say "  [OK] tsc --noEmit 通过"
    else
        say "  [WARN] tsc --noEmit 失败（生成的代码不能通过类型校验）" >&2
    fi
elif command -v npx >/dev/null 2>&1; then
    say "  [INFO] tsc 未全局安装；可运行 'npm install && npx tsc --noEmit' 验证"
else
    say "  [INFO] tsc / npx 都不可用，跳过类型校验"
fi

echo "  [OK] typescript 生成完成: $LANG_DIR/"
