#!/usr/bin/env bash
# ============================================================================
# generators/chimeric_adapter.sh — chimeric 流水线第二站（glue code generator）
#
# 职责:
#   1. 读 chimeric.json (env override CHIMERIC_FILE, 默认 ./chimeric.json)
#   2. 读 chimeric_spec.sh 产出的 IR: $OUTPUT_DIR/.chimeric/<bridge>/ir.json
#   3. 从 struct.json 推断目标语言集合 ({python,rust,go,typescript} 的交集)
#   4. 对每个 integration_point × 每个目标语言，渲染一个 adapter 文件:
#        $OUTPUT_DIR/<lang>/chimeric/<bridge>/<ip_id>.<ext>
#      (rust 额外加 src/ 前缀: $OUTPUT_DIR/rust/src/chimeric/<bridge>/<ip_id>.rs)
#   5. 优先用模板 templates_default/chimeric/<lang>/adapter.tpl；
#      不存在则走内联 heredoc stub（保证 always emit 一份合法代码）。
#   6. 写 adapter-manifest.json: {bridge, generated_at, files:[{path,sha256}]}
#
# 用法:
#   bash generators/chimeric_adapter.sh                 # 默认 ./chimeric.json
#   bash generators/chimeric_adapter.sh --plan          # dry-run，只打印计划文件
#   bash generators/chimeric_adapter.sh --chimeric-file ./examples/foo.json
#   CHIMERIC_FILE=./foo.json bash generators/chimeric_adapter.sh
#
# 退出码:
#   0  成功（含 chimeric.json 不存在的 soft skip）
#   2  IR 缺失（需先跑 chimeric_spec.sh）
#   3  chimeric.json 不合法
# ============================================================================

set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/_lib.sh"
source "$(dirname "${BASH_SOURCE[0]}")/_templates.sh"

# ---------- 默认值 ----------
CHIMERIC_FILE="${CHIMERIC_FILE:-./chimeric.json}"
PLAN_ONLY="${PLAN_ONLY:-0}"

# ---------- CLI ----------
while [[ $# -gt 0 ]]; do
    case "$1" in
        --plan)           PLAN_ONLY=1; shift ;;
        --chimeric-file)  CHIMERIC_FILE="$2"; shift 2 ;;
        -h|--help)
            sed -n '2,/^# ====/p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//; s/^===.*/=/'
            exit 0
            ;;
        *) echo "[chimeric_adapter] 未知参数: $1" >&2; exit 64 ;;
    esac
done

# ---------- helpers ----------
# snake_case -> camelCase（给 TypeScript 函数名用）
# 用 awk 实现，不依赖 GNU sed 的 \U/\l 转义（macOS BSD sed 不支持）。
to_camel() {
    to_snake "$1" | awk -F_ '{
        out = "";
        for (i = 1; i <= NF; i++) {
            if (i == 1) out = out $i;
            else out = out toupper(substr($i, 1, 1)) substr($i, 2);
        }
        printf "%s", out;
    }'
}

# lang -> 文件扩展名
ext_of() {
    case "$1" in
        python)     echo "py" ;;
        rust)       echo "rs" ;;
        go)         echo "go" ;;
        typescript) echo "ts" ;;
        *)          echo "$1" ;;
    esac
}

# ---------- main ----------
# 1. chimeric.json 缺失 -> soft skip（--target all 时不能硬失败）
if [[ ! -f "$CHIMERIC_FILE" ]]; then
    say "chimeric.json not found ($CHIMERIC_FILE), skipping chimeric_adapter"
    exit 0
fi

# 2. 校验 chimeric.json 解析
if ! jq empty "$CHIMERIC_FILE" 2>/dev/null; then
    echo "[FAIL] chimeric.json is not valid JSON: $CHIMERIC_FILE" >&2
    exit 3
fi

BRIDGE_NAME=$(jq -r '.bridge.name' "$CHIMERIC_FILE")
PEER_NAME=$(jq -r '.peer.name // ""' "$CHIMERIC_FILE")

# 3. IR 必须存在
IR_FILE="$OUTPUT_DIR/.chimeric/${BRIDGE_NAME}/ir.json"
if [[ ! -f "$IR_FILE" ]]; then
    echo "[FAIL] IR not found: $IR_FILE — run chimeric_spec.sh first" >&2
    exit 2
fi
if ! jq empty "$IR_FILE" 2>/dev/null; then
    echo "[FAIL] IR is not valid JSON: $IR_FILE" >&2
    exit 2
fi

# 4. 从 struct.json 推断目标语言（与 {python,rust,go,typescript} 取交集）
# read -ra 只读到首个换行，故把 newline 分隔转成空格分隔。
LANGS=""
if [[ -f "${STRUCT_FILE:-}" ]]; then
    LANGS=$(jq -r '(.modules // []) | [.[].language] | unique | .[]' "$STRUCT_FILE" 2>/dev/null \
            | grep -E '^(python|rust|go|typescript)$' | tr '\n' ' ' || true)
fi
if [[ -z "$LANGS" ]]; then
    LANGS="python"
fi
read -ra LANG_ARR <<< "$LANGS"

# ---------- plan 模式 ----------
if [[ "$PLAN_ONLY" == "1" ]]; then
    N_IPS=$(jq '.integration_points | length' "$CHIMERIC_FILE")
    for ii in $(seq 0 $((N_IPS - 1))); do
        ip_id=$(jq -r ".integration_points[$ii].id" "$CHIMERIC_FILE")
        for lang in "${LANG_ARR[@]}"; do
            ext=$(ext_of "$lang")
            if [[ "$lang" == "rust" ]]; then
                out="$OUTPUT_DIR/rust/src/chimeric/${BRIDGE_NAME}/${ip_id}.${ext}"
            else
                out="$OUTPUT_DIR/${lang}/chimeric/${BRIDGE_NAME}/${ip_id}.${ext}"
            fi
            printf '[plan] %s\n' "${out#$OUTPUT_DIR/}"
        done
    done
    exit 0
fi

say "chimeric_adapter: bridge=$BRIDGE_NAME langs=${LANG_ARR[*]}"

# ---------- 渲染循环 ----------
MANIFEST_ENTRIES=$(mktemp)
: > "$MANIFEST_ENTRIES"

N_IPS=$(jq '.integration_points | length' "$CHIMERIC_FILE")
for ii in $(seq 0 $((N_IPS - 1))); do
    # --- 提取 integration_point 字段 ---
    ip_id=$(jq -r ".integration_points[$ii].id" "$CHIMERIC_FILE")
    self_export=$(jq -r ".integration_points[$ii].self_export" "$CHIMERIC_FILE")
    ip_method=$(jq -r ".integration_points[$ii].peer_method" "$CHIMERIC_FILE")
    ip_path=$(jq -r ".integration_points[$ii].peer_path" "$CHIMERIC_FILE")
    field_mappings_json=$(jq -c ".integration_points[$ii].field_mapping // {}" "$CHIMERIC_FILE")
    invariant_names_json=$(jq -c ".integration_points[$ii].invariants // [] | map(.name)" "$CHIMERIC_FILE")
    golden_response_path=$(jq -r ".integration_points[$ii].golden.response // \"\"" "$CHIMERIC_FILE")

    # --- 从 IR 找匹配的 endpoint（method + path）取 type_map ---
    type_map_json=$(jq -c --arg m "$ip_method" --arg p "$ip_path" \
        '[.endpoints[] | select(.method == $m and .path == $p)] | first | .type_map // {}' "$IR_FILE")

    # --- 找 self 端归属: self.components[].exports 包含 self_export 的那个 ---
    self_info=$(jq -c --arg exp "$self_export" \
        '[.self.components[] | select((.exports // []) | index($exp))] | first' "$CHIMERIC_FILE")
    self_module=$(echo "$self_info" | jq -r '.module // ""')
    self_component=$(echo "$self_info" | jq -r '.component // ""')

    for lang in "${LANG_ARR[@]}"; do
        ext=$(ext_of "$lang")
        if [[ "$lang" == "rust" ]]; then
            out="$OUTPUT_DIR/rust/src/chimeric/${BRIDGE_NAME}/${ip_id}.${ext}"
        else
            out="$OUTPUT_DIR/${lang}/chimeric/${BRIDGE_NAME}/${ip_id}.${ext}"
        fi

        # --- 增量: should_regenerate ---
        if ! should_regenerate "$out" "$CHIMERIC_FILE" "$IR_FILE"; then
            say "  [SKIP] ${out#$OUTPUT_DIR/} (unchanged)"
            # 即使 skip 也计入 manifest（文件仍在磁盘上）
            if [[ -f "$out" ]]; then
                rel="${out#$OUTPUT_DIR/}"
                sha=$(file_hash "$out")
                printf '%s\t%s\n' "$rel" "$sha" >> "$MANIFEST_ENTRIES"
            fi
            continue
        fi

        mkdir -p "$(dirname "$out")"

        # --- 构建 vars_file（模板路径用） ---
        vars_file=$(mktemp)
        {
            printf 'bridge=%s\n'               "$(encode_value "${BRIDGE_NAME}")"
            printf 'ip_id=%s\n'                "$(encode_value "${ip_id}")"
            printf 'ip_method=%s\n'            "$(encode_value "${ip_method}")"
            printf 'ip_path=%s\n'              "$(encode_value "${ip_path}")"
            printf 'self_module=%s\n'          "$(encode_value "${self_module}")"
            printf 'self_component=%s\n'       "$(encode_value "${self_component}")"
            printf 'self_export=%s\n'          "$(encode_value "${self_export}")"
            printf 'peer_name=%s\n'            "$(encode_value "${PEER_NAME}")"
            printf 'field_mappings_json=%s\n'  "$(encode_value "${field_mappings_json}")"
            printf 'type_map_json=%s\n'        "$(encode_value "${type_map_json}")"
            printf 'invariant_names_json=%s\n' "$(encode_value "${invariant_names_json}")"
            printf 'golden_response_path=%s\n' "$(encode_value "${golden_response_path}")"
        } > "$vars_file"

        # --- 函数名（按语言习惯） ---
        fn_snake=$(to_snake "$self_export")
        fn_camel=$(to_camel "$self_export")

        # --- 优先模板，否则 heredoc fallback ---
        tpl_path="${GENERATORS_DIR:-$(dirname "${BASH_SOURCE[0]}")}/templates_default/chimeric/${lang}/adapter.tpl"
        emitted=0
        if [[ -f "$tpl_path" ]]; then
            if render_template "chimeric_${lang}" "adapter" "$vars_file" > "$out" 2>/dev/null; then
                emitted=1
            fi
        fi

        if [[ "$emitted" == "0" ]]; then
            case "$lang" in
                python)
                    cat > "$out" <<EOF
"""Chimeric adapter: bridge=${BRIDGE_NAME}, integration_point=${ip_id}.
Peer: ${ip_method} ${ip_path} on ${PEER_NAME}.
Self export: ${self_export}.
"""
# field_mapping: ${field_mappings_json}
# type_map: ${type_map_json}


def ${fn_snake}(payload):
    """TODO: call peer ${ip_method} ${ip_path} and map fields per field_mapping."""
    raise NotImplementedError("chimeric adapter ${ip_id} not implemented")
EOF
                    ;;
                rust)
                    cat > "$out" <<EOF
// Chimeric adapter: bridge=${BRIDGE_NAME}, integration_point=${ip_id}.
// Peer: ${ip_method} ${ip_path} on ${PEER_NAME}.
// Self export: ${self_export}.
// field_mapping: ${field_mappings_json}
// type_map: ${type_map_json}

pub fn ${fn_snake}(payload: serde_json::Value) -> Result<serde_json::Value, Box<dyn std::error::Error>> {
    // TODO: call peer ${ip_method} ${ip_path} and map fields per field_mapping.
    unimplemented!("chimeric adapter ${ip_id} not implemented")
}
EOF
                    ;;
                go)
                    cat > "$out" <<EOF
// Chimeric adapter: bridge=${BRIDGE_NAME}, integration_point=${ip_id}.
// Peer: ${ip_method} ${ip_path} on ${PEER_NAME}.
// Self export: ${self_export}.
// field_mapping: ${field_mappings_json}
// type_map: ${type_map_json}

package chimeric

// ${fn_snake} TODO: call peer ${ip_method} ${ip_path} and map fields per field_mapping.
func ${fn_snake}(payload map[string]interface{}) (map[string]interface{}, error) {
	return nil, fmt.Errorf("chimeric adapter ${ip_id} not implemented")
}
EOF
                    ;;
                typescript)
                    cat > "$out" <<EOF
// Chimeric adapter: bridge=${BRIDGE_NAME}, integration_point=${ip_id}.
// Peer: ${ip_method} ${ip_path} on ${PEER_NAME}.
// Self export: ${self_export}.
// field_mapping: ${field_mappings_json}
// type_map: ${type_map_json}

export function ${fn_camel}(payload: any): any {
    // TODO: call peer ${ip_method} ${ip_path} and map fields per field_mapping.
    throw new Error("chimeric adapter ${ip_id} not implemented");
}
EOF
                    ;;
                *)
                    cat > "$out" <<EOF
/* Chimeric adapter: bridge=${BRIDGE_NAME}, integration_point=${ip_id} (lang=${lang}) */
EOF
                    ;;
            esac
        fi

        rm -f "$vars_file"
        mark_generated "$out" "$CHIMERIC_FILE" "$IR_FILE"
        say "  [OK] ${out#$OUTPUT_DIR/}"

        # --- 累计 manifest 条目 ---
        rel="${out#$OUTPUT_DIR/}"
        sha=$(file_hash "$out")
        printf '%s\t%s\n' "$rel" "$sha" >> "$MANIFEST_ENTRIES"
    done
done

# ---------- 写 adapter-manifest.json ----------
MANIFEST_PATH="$OUTPUT_DIR/.chimeric/${BRIDGE_NAME}/adapter-manifest.json"
mkdir -p "$(dirname "$MANIFEST_PATH")"
now=$(date -u +%Y-%m-%dT%H:%M:%SZ)
jq -Rn --arg bridge "$BRIDGE_NAME" --arg now "$now" '
    [ inputs | split("\t") | select(length == 2) | { path: .[0], sha256: .[1]} ]
    | { bridge: $bridge, generated_at: $now, files: . }
' "$MANIFEST_ENTRIES" > "$MANIFEST_PATH"
rm -f "$MANIFEST_ENTRIES"

N_FILES=$(jq '.files | length' "$MANIFEST_PATH")
say "  [OK] ${MANIFEST_PATH#$OUTPUT_DIR/} ($N_FILES files)"
say "chimeric_adapter done: $N_FILES adapter file(s) for bridge=$BRIDGE_NAME"
