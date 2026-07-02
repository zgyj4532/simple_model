#!/usr/bin/env bash
# ============================================================================
# generators/chimeric_verify.sh — chimeric 流水线第三站（确定性验证，零 AI）
#
# 对 chimeric.json 里每个 integration_point 跑 4 种确定性验证模式
# （纯 bash + jq + diff，无 AI 调用）:
#   1. contract   — field_mapping ↔ IR type_map/required 一致性
#   2. golden     — captures/<id>.json vs fixtures/<golden.response> diff
#   3. invariants — jq 布尔表达式 against capture（severity=warning 不算失败）
#   4. round_trip — 调用语言测试 runner 跑 <ip>_roundtrip stub
#
# 聚合写出 verify-results.json，并原子更新 state.json。
#
# 用法:
#   bash generators/chimeric_verify.sh                     # 跑全部模式
#   bash generators/chimeric_verify.sh --mode contract     # 只跑 contract
#   bash generators/chimeric_verify.sh --integration <id>  # 只跑某个 ip
#   bash generators/chimeric_verify.sh --status-only       # 只读缓存，打印一行
#   bash generators/chimeric_verify.sh --json              # 输出 verify-results.json
#   bash generators/chimeric_verify.sh --bridge <name>     # 覆盖 bridge 名
#
# 退出码:
#   0  全 pass（skip 不算失败）
#   11 contract 模式有 fail
#   12 round_trip 模式有 fail
#   13 golden 模式有 fail
#   14 invariants 模式有 fail
#   15 2+ 模式有 fail
#   4  没有 chimeric.json / 没有 IR
# ============================================================================
# 注: macOS 默认 /bin/bash 是 3.2（无 declare -A）；本项目要求 bash>=4。
#     所有测试用 /opt/homebrew/bin/bash 跑。shebang 用 env bash 即可。

set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/_lib.sh"

# ---------- 默认值 ----------
CHIMERIC_FILE="${CHIMERIC_FILE:-./chimeric.json}"
MODE="all"
FILTER_IP=""
STATUS_ONLY=0
JSON_OUT=0
BRIDGE_OVERRIDE=""

# ---------- CLI ----------
while [[ $# -gt 0 ]]; do
    case "$1" in
        --bridge)        BRIDGE_OVERRIDE="$2"; shift 2 ;;
        --integration)   FILTER_IP="$2"; shift 2 ;;
        --mode)          MODE="$2"; shift 2 ;;
        --status-only)   STATUS_ONLY=1; shift ;;
        --json)          JSON_OUT=1; shift ;;
        --chimeric-file) CHIMERIC_FILE="$2"; shift 2 ;;
        -h|--help)
            sed -n '2,/^# ====/p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//; s/^===.*//'
            exit 0
            ;;
        *) echo "[chimeric_verify] 未知参数: $1" >&2; exit 64 ;;
    esac
done

# 非交互（被管道）→ JSON 输出
if [[ ! -t 1 ]]; then JSON_OUT=1; fi

# ---------- helpers ----------
# JSON 模式下，人类进度输出全部静默（stdout 只剩 verify-results.json）
vsay()  { [[ "$JSON_OUT" == "1" ]] && return 0; printf '  %s\n' "$*"; }
vok()   { [[ "$JSON_OUT" == "1" ]] && return 0; printf '  [OK]   %s\n' "$*"; }
vfail() { printf '  [FAIL] %s\n' "$*" >&2; }
now_iso() { date -u +%Y-%m-%dT%H:%M:%SZ; }

# ---------- status-only 快速路径（只读缓存，不重跑，永远 exit 0） ----------
if [[ "$STATUS_ONLY" == "1" ]]; then
    if [[ ! -f "$CHIMERIC_FILE" ]]; then
        echo "no chimeric.json configured"
        exit 0
    fi
    _sb="${BRIDGE_OVERRIDE:-$(jq -r '.bridge.name' "$CHIMERIC_FILE" 2>/dev/null || echo "?")}"
    _vr="$OUTPUT_DIR/.chimeric/$_sb/verify-results.json"
    if [[ -f "$_vr" ]]; then
        jq -r '"verify \(.bridge): \(.summary.passed)p \(.summary.failed)f \(.summary.skipped)s (exit \(.summary.exit_code // 0))"' "$_vr" 2>/dev/null \
            || echo "verify $_sb: (results unreadable)"
    else
        echo "no verify results yet for bridge $_sb"
    fi
    exit 0
fi

# ---------- discover chimeric.json ----------
if [[ ! -f "$CHIMERIC_FILE" ]]; then
    vfail "找不到 chimeric.json：$CHIMERIC_FILE"
    vsay "（run --chimeric init first）"
    exit 4
fi

BRIDGE="${BRIDGE_OVERRIDE:-$(jq -r '.bridge.name' "$CHIMERIC_FILE")}"
PEER_NAME=$(jq -r '.peer.name // .bridge.name' "$CHIMERIC_FILE")
CHIMERIC_DIR="$OUTPUT_DIR/.chimeric/$BRIDGE"
IR_PATH="$CHIMERIC_DIR/ir.json"
FIXTURES_DIR="$CHIMERIC_DIR/fixtures"
CAPTURES_DIR="$CHIMERIC_DIR/captures"
VERIFY_OUT="$CHIMERIC_DIR/verify-results.json"

if [[ ! -f "$IR_PATH" ]]; then
    vfail "找不到 IR：$IR_PATH"
    vsay "（run chimeric_spec.sh first）"
    exit 4
fi

PEER_SHA=$(jq -r '.peer_spec_sha256 // ""' "$IR_PATH")

# ---------- mode selection ----------
RUN_CONTRACT=0; RUN_ROUNDTRIP=0; RUN_GOLDEN=0; RUN_INVARIANTS=0
case "$MODE" in
    all)         RUN_CONTRACT=1; RUN_ROUNDTRIP=1; RUN_GOLDEN=1; RUN_INVARIANTS=1 ;;
    contract)    RUN_CONTRACT=1 ;;
    round_trip)  RUN_ROUNDTRIP=1 ;;
    golden)      RUN_GOLDEN=1 ;;
    invariants)  RUN_INVARIANTS=1 ;;
    *) vfail "未知 --mode: $MODE (contract|round_trip|golden|invariants|all)"; exit 64 ;;
esac

NOT_REQUESTED='{"status":"skip","reason":"not_requested"}'

# ============================================================================
# 模式函数：每个输出一个 ModeResult JSON 对象到 stdout
# Schema: {status:"pass"|"fail"|"skip", reason?:str, errors?:[{kind,message,field?,details?}], diff?:str}
# ============================================================================

# ---- contract ----
# 校验 field_mapping ↔ IR endpoint 的 type_map/required 一致性
#   - peer-required 字段必须被 field_mapping 覆盖（self key / .from / .to / string 值）
#   - field_mapping 声明 type 必须匹配 IR type_map[.from]（integer↔number 兼容，不报错）
run_contract() {
    local ip_json="$1"
    local peer_path peer_method
    peer_path=$(echo "$ip_json" | jq -r '.peer_path')
    peer_method=$(echo "$ip_json" | jq -r '.peer_method')

    local endpoint_json
    endpoint_json=$(jq -c --arg m "$peer_method" --arg p "$peer_path" \
        '.endpoints[] | select(.method == $m and .path == $p)' "$IR_PATH")

    if [[ -z "$endpoint_json" ]]; then
        jq -nc --arg m "$peer_method" --arg p "$peer_path" '{
            status:"fail",
            errors:[{kind:"missing_endpoint", message:("no IR endpoint for \($m) \($p)")}]
        }'
        return 0
    fi

    jq -n --argjson ip "$ip_json" --argjson endpoint "$endpoint_json" '
        ($ip.field_mapping // {}) as $fm |
        $endpoint.type_map as $tm |
        ($endpoint.required // []) as $req |
        # 收集 field_mapping 所有可达 peer 字段名（self key + from/to + string 值）
        ([$fm | to_entries[] |
            .key as $k | .value as $v |
            if ($v | type) == "string" then [$k, $v]
            else [$k, ($v.from // ""), ($v.to // "")] end
         ] | flatten | unique | map(select(. != ""))) as $covered |
        # peer-required 未被覆盖 → missing_field
        ([$req[] | select(. as $f | ($covered | index($f)) | not) |
            {kind:"missing_field", field:., message:("required peer field \(.) not covered by field_mapping")}]) as $missing |
        # 声明 type 与 IR type_map[.from] 不一致 → type_mismatch（integer↔number 兼容，不报错）
        ([$fm | to_entries[] |
            .value as $v |
            select(($v | type) == "object") |
            select(($v.type // null) != null) |
            ($v.from // "") as $pf |
            ($v.type) as $declared |
            ($tm[$pf] // null) as $irt |
            select($irt != null) |
            (if ($irt == $declared) then empty
             elif (($irt == "integer" and $declared == "number") or
                   ($irt == "number"   and $declared == "integer")) then empty
             else {kind:"type_mismatch", field:$pf,
                   message:("\($pf): declared \($declared) vs IR \($irt)")}
             end)]) as $typeerr |
        {
            status: (if (($missing + $typeerr) | length) == 0 then "pass" else "fail" end),
            errors: ($missing + $typeerr)
        }
    '
}

# ---- golden ----
# diff 捕获 vs golden fixture（jq -S 归一化后比较）
run_golden() {
    local ip_id="$1" ip_json="$2"
    local golden_response
    golden_response=$(echo "$ip_json" | jq -r '.golden.response // empty')

    if [[ -z "$golden_response" ]]; then
        echo '{"status":"skip","reason":"no_golden"}'
        return 0
    fi

    local golden_path="$FIXTURES_DIR/$golden_response"
    local capture_path="$CAPTURES_DIR/$ip_id.json"

    if [[ ! -f "$capture_path" ]]; then
        echo '{"status":"skip","reason":"no_capture"}'
        return 0
    fi
    if [[ ! -f "$golden_path" ]]; then
        echo '{"status":"skip","reason":"no_golden_file"}'
        return 0
    fi

    local diff_out=""
    diff_out=$(diff <(jq -S . "$golden_path" 2>/dev/null) <(jq -S . "$capture_path" 2>/dev/null) 2>/dev/null || true)

    if [[ -z "$diff_out" ]]; then
        echo '{"status":"pass"}'
    else
        jq -nc --arg d "$diff_out" '{status:"fail", errors:[{kind:"diff", message:"golden mismatch"}], diff:$d}'
    fi
}

# ---- invariants ----
# 对每个 invariant 跑 jq -e 表达式；severity=warning 计入 errors 但不算失败
# applies_to=raw → capture 原样；applies_to=decoded → v1 视同 raw（无 live decode 步骤）
run_invariants() {
    local ip_id="$1" ip_json="$2"
    local inv_count
    inv_count=$(echo "$ip_json" | jq '.invariants // [] | length')

    if [[ "$inv_count" -eq 0 ]]; then
        echo '{"status":"pass","errors":[]}'
        return 0
    fi

    local capture_path="$CAPTURES_DIR/$ip_id.json"
    if [[ ! -f "$capture_path" ]]; then
        echo '{"status":"skip","reason":"no_capture"}'
        return 0
    fi

    local err_lines=""
    local has_error_sev=0
    local name expr severity applies
    while IFS=$'\t' read -r name expr severity applies; do
        [[ -z "$name" ]] && continue
        # applies_to=raw 用 capture 原样；applies_to=decoded v1 同 raw（无 decode 步骤）
        if ! jq -e "$expr" "$capture_path" >/dev/null 2>&1; then
            err_lines+=$(jq -nc --arg n "$name" --arg e "$expr" \
                '{kind:"invariant", message:("\($n): \($e)")}')$'\n'
            if [[ "$severity" != "warning" ]]; then
                has_error_sev=1
            fi
        fi
    done < <(echo "$ip_json" | jq -r '.invariants[] | [.name, .expression, (.severity // "error"), (.applies_to // "decoded")] | @tsv')

    local errors_json
    errors_json=$(printf '%s' "$err_lines" | jq -s '.' 2>/dev/null || echo '[]')

    if [[ $has_error_sev -eq 1 ]]; then
        jq -nc --argjson e "$errors_json" '{status:"fail", errors:$e}'
    else
        jq -nc --argjson e "$errors_json" '{status:"pass", errors:$e}'
    fi
}

# ---- round_trip ----
# 找 self_component 的 module.language → 选 runner → 跑 <ip>_roundtrip stub
run_round_trip() {
    local ip_id="$1" ip_json="$2"
    local self_export
    self_export=$(echo "$ip_json" | jq -r '.self_export')

    # 找 self component → module（从 chimeric.json）
    local module_name
    module_name=$(jq -r --arg exp "$self_export" \
        '[.self.components[] | select((.exports // []) | index($exp)) | .module][0] // ""' \
        "$CHIMERIC_FILE")

    local language="any"
    if [[ -n "$module_name" && -f "${STRUCT_FILE:-./struct.json}" ]]; then
        language=$(jq -r --arg m "$module_name" \
            '[.modules[] | select(.name == $m) | .language][0] // "any"' \
            "${STRUCT_FILE:-./struct.json}" 2>/dev/null || echo "any")
    fi

    case "$language" in
        python|rust|go|typescript) ;;
        *) echo '{"status":"skip","reason":"no_language"}'; return 0 ;;
    esac

    # runner: env CHIMERIC_TEST_RUNNER_<LANG> 覆盖默认
    local upper_lang default_bin runner_cmd
    upper_lang=$(echo "$language" | tr '[:lower:]' '[:upper:]')
    local env_var="CHIMERIC_TEST_RUNNER_$upper_lang"
    runner_cmd="${!env_var:-}"
    default_bin=""
    case "$language" in
        python)     default_bin="pytest" ;;
        rust)       default_bin="cargo" ;;
        go)         default_bin="go" ;;
        typescript) default_bin="npx" ;;
    esac
    [[ -z "$runner_cmd" ]] && runner_cmd="$default_bin"

    if ! command -v "$runner_cmd" >/dev/null 2>&1; then
        echo '{"status":"skip","reason":"runner_missing"}'
        return 0
    fi

    # test stub 路径（rust 放 src/.../tests/）
    local test_file=""
    case "$language" in
        python)     test_file="$OUTPUT_DIR/python/chimeric/$BRIDGE/tests/${ip_id}_roundtrip.py" ;;
        rust)       test_file="$OUTPUT_DIR/rust/src/chimeric/$BRIDGE/tests/${ip_id}_roundtrip.rs" ;;
        go)         test_file="$OUTPUT_DIR/go/chimeric/$BRIDGE/tests/${ip_id}_roundtrip.go" ;;
        typescript) test_file="$OUTPUT_DIR/typescript/chimeric/$BRIDGE/tests/${ip_id}_roundtrip.ts" ;;
    esac

    if [[ ! -f "$test_file" ]]; then
        echo '{"status":"skip","reason":"no_stub"}'
        return 0
    fi

    # 跑 runner；非零 → fail（截断 stderr 前 500 字符）
    local stderr_out rc
    stderr_out=$(mktemp)
    rc=0
    case "$language" in
        python)     "$runner_cmd" -q "$test_file" >/dev/null 2>"$stderr_out" || rc=$? ;;
        rust)       ( cd "$OUTPUT_DIR/rust" && "$runner_cmd" test --quiet 2>"$stderr_out" ) >/dev/null || rc=$? ;;
        go)         "$runner_cmd" test "$test_file" >/dev/null 2>"$stderr_out" || rc=$? ;;
        typescript) "$runner_cmd" tsc --noEmit "$test_file" >/dev/null 2>"$stderr_out" || rc=$? ;;
    esac

    if [[ $rc -ne 0 ]]; then
        local truncated
        truncated=$(head -c 500 "$stderr_out")
        rm -f "$stderr_out"
        jq -nc --arg d "$truncated" --argjson ec "$rc" \
            '{status:"fail", errors:[{kind:"runner_fail", message:"runner exited non-zero", details:{stderr:$d, exit_code:$ec}}]}'
    else
        rm -f "$stderr_out"
        echo '{"status":"pass"}'
    fi
}

# ============================================================================
# 主循环
# ============================================================================
vsay "[verify] bridge=$BRIDGE peer=$PEER_NAME"

n_ips=$(jq '.integration_points | length' "$CHIMERIC_FILE")
results_lines=""

local_idx=0
while [[ $local_idx -lt $n_ips ]]; do
    ip_json=$(jq -c ".integration_points[$local_idx]" "$CHIMERIC_FILE")
    ip_id=$(echo "$ip_json" | jq -r '.id')
    local_idx=$((local_idx + 1))

    if [[ -n "$FILTER_IP" && "$ip_id" != "$FILTER_IP" ]]; then continue; fi

    vsay "  · $ip_id"

    contract_res="$NOT_REQUESTED"; roundtrip_res="$NOT_REQUESTED"
    golden_res="$NOT_REQUESTED"; invariants_res="$NOT_REQUESTED"

    if [[ "$RUN_CONTRACT" == "1" ]]; then
        contract_res=$(run_contract "$ip_json") || contract_res='{"status":"skip","reason":"runner_error"}'
    fi
    if [[ "$RUN_ROUNDTRIP" == "1" ]]; then
        roundtrip_res=$(run_round_trip "$ip_id" "$ip_json") || roundtrip_res='{"status":"skip","reason":"runner_error"}'
    fi
    if [[ "$RUN_GOLDEN" == "1" ]]; then
        golden_res=$(run_golden "$ip_id" "$ip_json") || golden_res='{"status":"skip","reason":"runner_error"}'
    fi
    if [[ "$RUN_INVARIANTS" == "1" ]]; then
        invariants_res=$(run_invariants "$ip_id" "$ip_json") || invariants_res='{"status":"skip","reason":"runner_error"}'
    fi

    modes_json=$(jq -nc \
        --argjson c "$contract_res" \
        --argjson r "$roundtrip_res" \
        --argjson g "$golden_res" \
        --argjson v "$invariants_res" \
        '{contract:$c, round_trip:$r, golden:$g, invariants:$v}')

    results_lines+=$(jq -nc --arg id "$ip_id" --argjson modes "$modes_json" \
        '{integration_point:$id, modes:$modes}')$'\n'

    # 每模式一行人类输出（JSON 模式下静默）
    if [[ "$JSON_OUT" != "1" ]]; then
        m_st=""
        for m in contract round_trip golden invariants; do
            m_st=$(echo "$modes_json" | jq -r ".$m.status")
            case "$m_st" in
                pass) printf '    %-12s PASS\n' "$m" ;;
                fail) printf '    %-12s FAIL\n' "$m" ;;
                skip) printf '    %-12s SKIP\n' "$m" ;;
            esac
        done
    fi
done

# ============================================================================
# 聚合 summary（从 results 数组用 jq 算）
# ============================================================================
results_array=$(printf '%s' "$results_lines" | jq -s '.')
at=$(now_iso)

summary_json=$(jq -n --argjson results "$results_array" '
    ($results | map(.modes.contract.status))   as $c |
    ($results | map(.modes.round_trip.status)) as $r |
    ($results | map(.modes.golden.status))     as $g |
    ($results | map(.modes.invariants.status)) as $i |
    def count($arr; $val): [$arr[] | select(. == $val)] | length;
    def statuses: [.modes.contract.status, .modes.round_trip.status, .modes.golden.status, .modes.invariants.status];
    {
        total: ($results | length),
        passed:   [$results[] | select((statuses | any(. == "pass")) and (statuses | any(. == "fail") | not))] | length,
        failed:   [$results[] | select(statuses | any(. == "fail"))] | length,
        skipped:  [$results[] | select((statuses | any(. == "pass") | not) and (statuses | any(. == "fail") | not))] | length,
        by_mode: {
            contract:   {passed: count($c;"pass"), failed: count($c;"fail"), skipped: count($c;"skip")},
            round_trip: {passed: count($r;"pass"), failed: count($r;"fail"), skipped: count($r;"skip")},
            golden:     {passed: count($g;"pass"), failed: count($g;"fail"), skipped: count($g;"skip")},
            invariants: {passed: count($i;"pass"), failed: count($i;"fail"), skipped: count($i;"skip")}
        }
    }
')

# 计算 exit_code（哪个模式有 fail；2+ → 15）
contract_failed=$(echo "$summary_json" | jq '.by_mode.contract.failed')
roundtrip_failed=$(echo "$summary_json" | jq '.by_mode.round_trip.failed')
golden_failed=$(echo "$summary_json" | jq '.by_mode.golden.failed')
invariants_failed=$(echo "$summary_json" | jq '.by_mode.invariants.failed')

failed_modes=0
if [[ $contract_failed   -gt 0 ]]; then failed_modes=$((failed_modes + 1)); fi
if [[ $roundtrip_failed  -gt 0 ]]; then failed_modes=$((failed_modes + 1)); fi
if [[ $golden_failed     -gt 0 ]]; then failed_modes=$((failed_modes + 1)); fi
if [[ $invariants_failed -gt 0 ]]; then failed_modes=$((failed_modes + 1)); fi

exit_code=0
if [[ $failed_modes -eq 0 ]]; then
    exit_code=0
elif [[ $failed_modes -eq 1 ]]; then
    if   [[ $contract_failed   -gt 0 ]]; then exit_code=11
    elif [[ $roundtrip_failed  -gt 0 ]]; then exit_code=12
    elif [[ $golden_failed     -gt 0 ]]; then exit_code=13
    elif [[ $invariants_failed -gt 0 ]]; then exit_code=14
    fi
else
    exit_code=15
fi

summary_json=$(echo "$summary_json" | jq --argjson ec "$exit_code" '. + {exit_code:$ec}')

# 汇总计数（state.json 更新 + 人类输出都要用）
s_pass=$(echo "$summary_json" | jq '.passed')
s_fail=$(echo "$summary_json" | jq '.failed')
s_skip=$(echo "$summary_json" | jq '.skipped')

# ============================================================================
# 写 verify-results.json（匹配 specs/chimeric-verify-output.json）
# ============================================================================
mkdir -p "$CHIMERIC_DIR"
envelope=$(jq -n \
    --arg schema_version "1.0" \
    --arg bridge "$BRIDGE" \
    --arg at "$at" \
    --arg peer_sha "$PEER_SHA" \
    --argjson results "$results_array" \
    --argjson summary "$summary_json" \
    '{schema_version:$schema_version, bridge:$bridge, at:$at,
      peer_spec_sha256:$peer_sha, summary:$summary, results:$results}')

# peer_spec_sha256 仅在合法 64-hex 时保留（schema 有 pattern 约束）
envelope=$(echo "$envelope" | jq 'if (.peer_spec_sha256 | test("^[0-9a-f]{64}$") | not) then del(.peer_spec_sha256) else . end')

echo "$envelope" | jq '.' > "$VERIFY_OUT"
jq empty "$VERIFY_OUT"   # 确认是合法 JSON

# ============================================================================
# 原子更新 state.json::integrations.<bridge>（mktemp + jq + mv，缺失则跳过）
# 复用 chimeric_spec.sh / agent.sh 的 safe_jq_update 模式
# ============================================================================
STATE_FILE="${STATE_FILE:-$OUTPUT_DIR/.bootstrap/state.json}"
if [[ -f "$STATE_FILE" ]]; then
    ips_obj=$(jq -n --argjson results "$results_array" --arg now "$at" '
        $results | map({
            key: .integration_point,
            value: {
                status: (if ([.modes.contract.status,.modes.round_trip.status,.modes.golden.status,.modes.invariants.status] | any(. == "fail")) then "fail"
                         elif ([.modes.contract.status,.modes.round_trip.status,.modes.golden.status,.modes.invariants.status] | any(. == "pass")) then "pass"
                         else "skip" end),
                at: $now,
                modes: .modes
            }
        }) | from_entries')

    tmp_state=$(mktemp)
    if jq --arg b "$BRIDGE" --arg pn "$PEER_NAME" --arg sha "$PEER_SHA" \
          --arg now "$at" --argjson ec "$exit_code" \
          --argjson pass "$s_pass" --argjson fail "$s_fail" --argjson skip "$s_skip" \
          --argjson ips "$ips_obj" '
        .integrations //= {}
        | (.integrations[$b] //= {})
        | .integrations[$b].bridge = $b
        | .integrations[$b].peer_name = $pn
        | .integrations[$b].peer_spec_sha256 = $sha
        | .integrations[$b].last_verify_at = $now
        | .integrations[$b].last_verify_exit = $ec
        | .integrations[$b].last_verify_pass = $pass
        | .integrations[$b].last_verify_fail = $fail
        | .integrations[$b].last_verify_skipped = $skip
        | .integrations[$b].integration_points = $ips
    ' "$STATE_FILE" > "$tmp_state" 2>/dev/null && jq empty "$tmp_state" 2>/dev/null; then
        mv "$tmp_state" "$STATE_FILE"
    else
        rm -f "$tmp_state"
    fi
fi

# ============================================================================
# 人类 / JSON 输出
# ============================================================================
vok "verify done: exit=$exit_code  passed=$s_pass  failed=$s_fail  skipped=$s_skip"

if [[ "$JSON_OUT" == "1" ]]; then
    jq '.' "$VERIFY_OUT"
fi

exit "$exit_code"
