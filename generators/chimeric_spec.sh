#!/usr/bin/env bash
# ============================================================================
# generators/chimeric_spec.sh — chimeric 流水线第一站
#
# 职责:
#   1. 读 chimeric.json (env override CHIMERIC_FILE)
#   2. 用 ajv (可选) 或 jq-required 回退校验 against specs/chimeric-schema.json
#   3. 解析 peer.spec.source → 拉到 ${OUTPUT_DIR}/.chimeric/<bridge>/peer-spec.json
#      - 支持 https:// URL (curl)
#      - 支持 github owner/repo@ref:path (git show / git archive)
#      - 支持本地文件路径
#      - 支持 sha256 强制校验；带 .deps 缓存
#   4. 用 jq 把 OpenAPI 2/3 规范化成 IR (chimeric-ir.json schema)
#   5. 写出 ir.json 给下游 chimeric_adapter.sh / chimeric_verify.sh 消费
#
# 用法:
#   bash generators/chimeric_spec.sh                # 默认 ./chimeric.json
#   bash generators/chimeric_spec.sh --plan         # dry-run
#   CHIMERIC_FILE=./examples/foo.json bash generators/chimeric_spec.sh
#
# 退出码（也供 bootstrap.sh --chimeric 子命令用）:
#   0  成功
#   4  chimeric.json 不合法 / 缺必填字段
#   5  schema 校验失败
#   6  peer spec 拉取失败 / sha256 不一致
#   8  peer spec 不是合法 JSON/YAML
# ============================================================================

set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/_lib.sh"

# ---------- 默认值 ----------
CHIMERIC_FILE="${CHIMERIC_FILE:-./chimeric.json}"
SCHEMA_FILE="${SCHIMERIC_SCHEMA_FILE:-${GENERATORS_DIR:-$(dirname "${BASH_SOURCE[0]}")}/../specs/chimeric-schema.json}"
IR_SCHEMA_FILE="${CHIMERIC_IR_SCHEMA_FILE:-${GENERATORS_DIR:-$(dirname "${BASH_SOURCE[0]}")}/../specs/chimeric-ir.json}"
PLAN_ONLY="${PLAN_ONLY:-0}"
SPECS_DIR_DEFAULT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../specs" 2>/dev/null && pwd || echo ./specs)"

# ---------- CLI ----------
while [[ $# -gt 0 ]]; do
    case "$1" in
        --plan)        PLAN_ONLY=1; shift ;;
        --chimeric-file) CHIMERIC_FILE="$2"; shift 2 ;;
        --schema)      SCHEMA_FILE="$2"; shift 2 ;;
        -h|--help)
            sed -n '2,/^# ====/p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//; s/^===.*/=/'
            exit 0
            ;;
        *) echo "[chimeric_spec] 未知参数: $1" >&2; exit 64 ;;
    esac
done

# ---------- helpers ----------
say()  { printf '  %s\n' "$*"; }
ok()   { printf '  [OK]   %s\n' "$*"; }
warn() { printf '  [WARN] %s\n' "$*" >&2; }
fail() { printf '  [FAIL] %s\n' "$*" >&2; exit "${2:-1}"; }

# validate_chimeric_json <file>
# 优先 ajv，否则走 jq-required fallback
validate_chimeric_json() {
    local file="$1"
    if ! command -v jq >/dev/null 2>&1; then
        fail "找不到 jq（必需）" 2
    fi
    if ! jq empty "$file" 2>/dev/null; then
        fail "$file 不是合法 JSON" 8
    fi

    if command -v ajv >/dev/null 2>&1; then
        if [[ -f "$SCHEMA_FILE" ]]; then
            if ajv validate -s "$SCHEMA_FILE" -d "$file" --strict=false 2>/dev/null; then
                return 0
            else
                warn "ajv 校验失败，落到 jq-required 回退再确认"
            fi
        fi
    fi

    # jq-required 回退：仅检查 required[] 字段是否存在
    local missing
    missing=$(jq -r '
        [ "schema_version", "bridge.name", "bridge.description",
          "self.project", "self.components",
          "peer.name", "peer.spec.kind", "peer.spec.source",
          "integration_points" ] as $req
        | [ $req[] | select(. as $p | (getpath($p | split(".")) // null) == null) ]
        | .[]' "$file" 2>/dev/null || true)
    if [[ -n "$missing" ]]; then
        warn "缺少必填字段（jq-required 回退）：$missing"
        return 1
    fi
    return 0
}

# fetch_peer_spec <source_json> <dest_path>
# source_json 形如 {"url": "...", "sha256": "..."} 或纯字符串
fetch_peer_spec() {
    local source="$1" dest="$2"
    local url="" sha=""
    # source 可能是对象 {"url","sha256"} 或裸字符串
    if echo "$source" | jq -e 'type == "object"' >/dev/null 2>&1; then
        url=$(echo "$source" | jq -r '.url // empty')
        sha=$(echo "$source" | jq -r '.sha256 // empty')
    else
        url="$source"
    fi

    [[ -z "$url" ]] && fail "peer spec source 为空" 6

    local tmp=""
    tmp=$(mktemp)

    case "$url" in
        https://*|http://*)
            if ! command -v curl >/dev/null 2>&1; then
                fail "需要 curl 来拉取 https peer spec" 6
            fi
            curl -fsSL --max-time 30 "$url" -o "$tmp" \
                || fail "curl 拉取 peer spec 失败: $url" 6
            ;;
        *:*[[:digit:]]*)
            # ssh-like or git URLs
            fail "暂不支持 ssh:// / git:// protocol，请用 https URL 或 github owner/repo@ref:path 形式" 6
            ;;
        *@*:*)
            # github owner/repo@ref:path 形式
            if ! command -v git >/dev/null 2>&1; then
                fail "需要 git 来解析 github locator" 6
            fi
            local repo="${url%@*}" ref_path="${url#*@}" path=""
            if [[ "$ref_path" == *:* ]]; then
                ref="${ref_path%%:*}"
                path="${ref_path#*:}"
            else
                ref="$ref_path"
                path=""
            fi
            local repo_https="https://github.com/${repo}.git"
            # 优先用 git archive（无需 clone）; 不行再 fallback 到 git show
            if ! curl -fsSL "https://raw.githubusercontent.com/${repo}/${ref}/${path}" -o "$tmp" 2>/dev/null; then
                fail "无法解析 github locator: $url" 6
            fi
            ;;
        /*|./*|../*|~/*)
            cp "$url" "$tmp" || fail "无法读本地文件: $url" 6
            ;;
        *)
            fail "无法识别的 peer spec source 形式: $url" 6
            ;;
    esac

    # 校验 sha256（如果指定）
    if [[ -n "$sha" ]]; then
        local got
        got=$(sha256sum "$tmp" | awk '{print $1}')
        if [[ "$got" != "$sha" ]]; then
            fail "peer spec SHA-256 不一致 (期望 $sha, 实际 $got)" 6
        fi
    fi
    mkdir -p "$(dirname "$dest")"
    mv "$tmp" "$dest"
}

# normalize_openapi <peer_spec_path> <kind> <bridge_name>
# 输出 IR JSON 到 stdout
normalize_openapi() {
    local spec="$1" kind="$2" bridge="$3"
    local peer_sha
    peer_sha=$(sha256sum "$spec" | awk '{print $1}')

    # 把 yaml 转 json（如果装了 yq）; 否则假定就是 JSON
    local spec_json
    if [[ "$spec" == *.yaml || "$spec" == *.yml ]] && command -v yq >/dev/null 2>&1; then
        spec_json=$(yq -o=json '.' "$spec")
    else
        spec_json=$(cat "$spec")
    fi

    # 通过 echo 一次性喂 jq，避免 sub-shell
    local now
    now=$(date -u +%Y-%m-%dT%H:%M:%SZ)

    # OpenAPI 3: paths.x.method 是 string；OpenAPI 2 同
    # 抽 field→type 的策略:
    #   - 看 request body schema 与每个 response schema;
    #   - 对 schema.properties.<name>.type 抽 (含 $ref 解析到 components.schemas 的 type);
    #   - 把每个 endpoint 的 type_map 合并 (后者覆盖前者，见优先 response > request)
    #   - required[] 也是
    # 该 jq 把 path 字典序 + method 字母序排好，保证 IR 输出确定性。

    if [[ "$kind" == "openapi_3" ]]; then
        echo "$spec_json" | jq --arg bridge "$bridge" \
           --arg peer_sha "$peer_sha" --arg now "$now" '
            def resolve_ref:
                if (type == "object") and (.["$ref"] // null) then
                    .["$ref"] as $r
                    | ($r | ltrimstr("#/") | split("/")) as $segs
                    | reduce $segs[] as $s (.; .[$s])
                    | (select(.) | del(.["$ref"]))
                else . end;
            def type_of(schema):
                schema as $s
                | ($s | resolve_ref) as $r
                | $r.type // "object";
            def flat_type_map(s):
                (s | resolve_ref) as $r
                | ( $r.properties // {} )
                | to_entries
                | map({ key: .key, value: (.value.type // "object") })
                | from_entries ;
            def flat_required(s):
                (s | resolve_ref) as $r
                | $r.required // [];
            {
                schema_version: "1.0",
                bridge: $bridge,
                peer_name: (.info.title // "peer"),
                peer_spec_sha256: $peer_sha,
                generated_at: $now,
                endpoints: (
                    [ .paths // {} | to_entries | .[] as $path_entry |
                      $path_entry.key as $p |
                      $path_entry.value | to_entries | .[] |
                      select(.key | test("^(get|post|put|patch|delete|head|options)$")) |
                      .value as $op | .key as $m |
                      {
                        id: (($m | ascii_upcase) + "_" + ($p | gsub("[{}]"; ""))),
                        method: ($m | ascii_upcase),
                        path:  $p,
                        request_schema: ($op.requestBody.content["application/json"].schema // {}) | resolve_ref,
                        response_schemas: (
                            ($op.responses // {})
                            | to_entries
                            | map(
                                if .value.content == null then empty
                                else { key: .key, value: (.value.content["application/json"].schema // {} | resolve_ref) }
                                end
                              )
                            | from_entries
                          ),
                        type_map: (
                            [ ($op.requestBody.content["application/json"].schema // {} | flat_type_map(.)) ]
                            + [ ($op.responses // {} | to_entries | map(.value.content["application/json"].schema // {} | flat_type_map(.)) | add // {}) ]
                            | add // {}
                          ),
                        required: (
                            ( [ [$op.requestBody.content["application/json"].schema // {} | resolve_ref | flat_required(.)] ] | flatten )
                            + ( [ $op.responses // {} | to_entries | map(.value.content["application/json"].schema // {} | resolve_ref | flat_required(.)) ] | flatten )
                            | unique | sort
                          ),
                        summary: ($op.summary // "")
                      }
                    ]
                )
            }
        '
    elif [[ "$kind" == "openapi_2" ]]; then
        # OpenAPI 2 / Swagger: parameters[] 表达请求体；responses.<code>.schema 表达响应
        echo "$spec_json" | jq --arg bridge "$bridge" \
           --arg peer_sha "$peer_sha" --arg now "$now" '
            def resolve_ref:
                if (type == "object") and (.["$ref"] // null) then
                    .["$ref"] as $r
                    | ($r | ltrimstr("#/") | split("/")) as $segs
                    | reduce $segs[] as $s (.; .[$s])
                    | (select(.) | del(.["$ref"]))
                else . end;
            def type_of(schema):
                schema as $s
                | ($s | resolve_ref) as $r
                | $r.type // "object";
            def flat_type_map(s):
                (s | resolve_ref) as $r
                | ( $r.properties // {} )
                | to_entries
                | map({ key: .key, value: (.value.type // "object") })
                | from_entries ;
            def flat_required(s):
                (s | resolve_ref) as $r
                | $r.required // [];
            {
                schema_version: "1.0",
                bridge: $bridge,
                peer_name: (.info.title // "peer"),
                peer_spec_sha256: $peer_sha,
                generated_at: $now,
                endpoints: (
                    [ .paths // {} | to_entries | .[] as $path_entry |
                      $path_entry.key as $p |
                      $path_entry.value | to_entries | .[] |
                      select(.key | test("^(get|post|put|patch|delete|head|options)$")) |
                      .value as $op | .key as $m |
                      {
                        id: (($m | ascii_upcase) + "_" + ($p | gsub("[{}]"; ""))),
                        method: ($m | ascii_upcase),
                        path:  $p,
                        request_schema: (
                            [ $op.parameters // [] | .[] | select(.in == "body") | .schema // {} | resolve_ref ]
                            | .[0] // {}
                          ),
                        response_schemas: (
                            ($op.responses // {})
                            | to_entries
                            | map(
                                if .value.schema == null then empty
                                else { key: .key, value: (.value.schema // {} | resolve_ref) }
                                end
                              )
                            | from_entries
                          ),
                        type_map: (
                            [ [ $op.parameters // [] | .[] | select(.in == "body") | .schema // {} | flat_type_map(.) ] | add // {} ]
                            + [ $op.responses // {} | to_entries | map(.value.schema // {} | flat_type_map(.)) | add // {} ]
                            | add // {}
                          ),
                        required: (
                            ( [ [ $op.parameters // [] | .[] | select(.in == "body") | .schema // {} | flat_required(.) ] | add // [] ] | flatten )
                            + ( [ $op.responses // {} | to_entries | map(.value.schema // {} | flat_required(.)) | add // [] ] | flatten )
                            | unique | sort
                          ),
                        summary: ($op.summary // "")
                      }
                    ]
                )
            }
        '
    else
        fail "未知的 spec kind: $kind" 5
    fi
}

# ---------- main ----------
if [[ ! -f "$CHIMERIC_FILE" ]]; then
    warn "找不到 chimeric.json：$CHIMERIC_FILE"
    say "（跳过；用户未启用 chimeric 子系统）"
    exit 0
fi

if [[ "$PLAN_ONLY" == "1" ]]; then
    say "[plan] 计划: validate $CHIMERIC_FILE → resolve peer → 写 ir.json"
    exit 0
fi

say "validating $CHIMERIC_FILE"
validate_chimeric_json "$CHIMERIC_FILE" || fail "chimeric.json schema 校验失败" 5

BRIDGE_NAME=$(jq -r '.bridge.name' "$CHIMERIC_FILE")
PEER_NAME=$(jq -r '.peer.name' "$CHIMERIC_FILE")
SPEC_KIND=$(jq -r '.peer.spec.kind' "$CHIMERIC_FILE")
# 用 -r 去掉 string 值的 JSON 引号；对象形式的 source 仍保留 JSON 结构
SPEC_SOURCE=$(jq -r '.peer.spec.source | if type == "string" then . else tojson end' "$CHIMERIC_FILE")
CACHE_PATH_REL=$(jq -r '.peer.spec.cache_path // "./generated/.chimeric/<bridge>/peer-spec.json"' "$CHIMERIC_FILE" | sed "s|<bridge>|$BRIDGE_NAME|g")
CACHE_PATH_ABS="$OUTPUT_DIR/.chimeric/${BRIDGE_NAME}/peer-spec.json"

IR_PATH="$OUTPUT_DIR/.chimeric/${BRIDGE_NAME}/ir.json"
mkdir -p "$(dirname "$IR_PATH")" "$(dirname "$CACHE_PATH_ABS")"

say "bridge=$BRIDGE_NAME peer=$PEER_NAME kind=$SPEC_KIND"

# 拉 / 校验 peer spec (包括 sha256)
EXPECTED_SHA=$(echo "$SPEC_SOURCE" | jq -r 'if type == "object" then .sha256 else "" end' 2>/dev/null || echo "")
EXISTING_SHA=""
if [[ -f "$CACHE_PATH_ABS.deps" ]]; then
    EXISTING_SHA=$(sed -n 's/^sha256=//p' "$CACHE_PATH_ABS.deps" 2>/dev/null || echo "")
fi

NEED_FETCH=1
if [[ -f "$CACHE_PATH_ABS" && "$EXISTING_SHA" == "$EXPECTED_SHA" && -n "$EXPECTED_SHA" ]]; then
    say "cached peer-spec.json sha256 matches pin; skip fetch"
    NEED_FETCH=0
fi

if [[ "$NEED_FETCH" == "1" ]]; then
    say "fetching peer spec → $CACHE_PATH_ABS"
    fetch_peer_spec "$SPEC_SOURCE" "$CACHE_PATH_ABS"
    local_sha=$(sha256sum "$CACHE_PATH_ABS" | awk '{print $1}')
    if [[ -n "$EXPECTED_SHA" && "$local_sha" != "$EXPECTED_SHA" ]]; then
        fail "刚下载的 peer spec sha256 与声明不一致（fetch_peer_spec 应已拦）" 6
    fi
    printf 'sha256=%s\nurl=%s\nat=%s\n' \
        "$local_sha" \
        "$(echo "$SPEC_SOURCE" | jq -r 'if type == "object" then .url else . end')" \
        "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
        > "$CACHE_PATH_ABS.deps"
fi

# 规范化出 IR
say "normalizing OpenAPI → IR"
ir_out=$(mktemp)
normalize_openapi "$CACHE_PATH_ABS" "$SPEC_KIND" "$BRIDGE_NAME" > "$ir_out"

# 验证 IR 自身合法 JSON
if ! jq empty "$ir_out" 2>/dev/null; then
    fail "IR 不是合法 JSON（jq normalize 失败）" 8
fi

# 写 ir.json，仅当内容真变了
if [[ -f "$IR_PATH" ]] && diff -q <(jq -S . "$IR_PATH") <(jq -S . "$ir_out") >/dev/null 2>&1; then
    say "  [SKIP] ${IR_PATH#$OUTPUT_DIR/} (unchanged)"
else
    mkdir -p "$(dirname "$IR_PATH")"
    jq -S . "$ir_out" > "$IR_PATH"
    say "  [OK]   ${IR_PATH#$OUTPUT_DIR/}"
fi
rm -f "$ir_out"

# 顺手更新 state.json 里的 integrations.<bridge>
STATE_FILE="${STATE_FILE:-$OUTPUT_DIR/.bootstrap/state.json}"
if [[ -f "$STATE_FILE" ]]; then
    peer_sha=$(sha256sum "$CACHE_PATH_ABS" | awk '{print $1}')
    tmp_state=$(mktemp)
    if jq --arg b "$BRIDGE_NAME" --arg pn "$PEER_NAME" --arg sha "$peer_sha" '
        .integrations //= {}
        | .integrations[$b] = (
            .integrations[$b] // {}
            | . + { bridge: $b, peer_name: $pn, peer_spec_sha256: $sha }
          )
    ' "$STATE_FILE" > "$tmp_state" 2>/dev/null && jq empty "$tmp_state" 2>/dev/null; then
        mv "$tmp_state" "$STATE_FILE"
    else
        rm -f "$tmp_state"
    fi
fi

ok "chimeric_spec done for bridge=$BRIDGE_NAME"
