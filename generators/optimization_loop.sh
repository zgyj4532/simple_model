#!/usr/bin/env bash
set -euo pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="."
STRUCT="${STRUCT_FILE:-./struct.json}"
OUT_DIR="generated/optimization"
MODE="dry-run"
BUDGET=3
JSON_OUT=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        --root) ROOT="$2"; shift 2 ;;
        --struct|-s) STRUCT="$2"; shift 2 ;;
        --output-dir) OUT_DIR="$2"; shift 2 ;;
        --budget) BUDGET="$2"; shift 2 ;;
        --dry-run) MODE="dry-run"; shift ;;
        --apply) MODE="apply"; shift ;;
        --json) JSON_OUT=1; shift ;;
        -h|--help)
            echo "optimization_loop.sh --root <repo> --struct <struct> [--budget 3] [--dry-run|--apply] [--json]"
            exit 0
            ;;
        *) echo "unknown arg: $1" >&2; exit 64 ;;
    esac
done

command -v jq >/dev/null 2>&1 || { echo "[FAIL] missing jq" >&2; exit 2; }
[[ "$BUDGET" =~ ^[0-9]+$ ]] || { echo "[FAIL] budget must be numeric" >&2; exit 64; }
[[ "$BUDGET" -ge 1 ]] || { echo "[FAIL] budget must be >= 1" >&2; exit 64; }
[[ -d "$ROOT" ]] || { echo "[FAIL] root not found: $ROOT" >&2; exit 2; }
[[ -f "$STRUCT" ]] || { echo "[FAIL] struct not found: $STRUCT" >&2; exit 2; }
jq empty "$STRUCT"
mkdir -p "$OUT_DIR/iterations"

ROOT="$(cd "$ROOT" && pwd)"
STRUCT="$(cd "$(dirname "$STRUCT")" && pwd)/$(basename "$STRUCT")"

restore_backups() {
    local rollback="$1"
    [[ -f "$rollback" ]] || return 0
    jq -r '.results[]? | select(.result.backup? and (.result.writes // [] | index("struct.json"))) | .result.backup' "$rollback" | tail -1 | while IFS= read -r backup; do
        [[ -f "$backup" ]] && cp "$backup" "$STRUCT"
    done
}

initial=$(bash "$SELF_DIR/optimization_score.sh" --root "$ROOT" --struct "$STRUCT" --output-dir "$OUT_DIR" --json)
current_score=$(jq '.score' <<<"$initial")
iterations=()
rolled_back=false
stop_reason="budget_exhausted"

for ((i=1; i<=BUDGET; i++)); do
    iter_dir="$OUT_DIR/iterations/$i"
    mkdir -p "$iter_dir"
    before=$(bash "$SELF_DIR/optimization_score.sh" --root "$ROOT" --struct "$STRUCT" --output-dir "$iter_dir" --json)
    suggestions=$(bash "$SELF_DIR/macro_suggest.sh" --root "$ROOT" --struct "$STRUCT" --output-dir "$iter_dir" --json)
    compiled=$(bash "$SELF_DIR/macro_compile.sh" --suggestions "$iter_dir/macro-suggestions.json" --root "$ROOT" --struct "$STRUCT" --output-dir "$iter_dir" --json)
    action_count=$(jq '.summary.actions' <<<"$compiled")
    if [[ "$action_count" -eq 0 ]]; then
        stop_reason="no_actions"
        iterations+=("$(jq -n --argjson iteration "$i" --argjson before "$before" --argjson suggestions "$suggestions" --argjson compiled "$compiled" '{iteration:$iteration, before:$before, suggestions:$suggestions.summary, compiled:$compiled.summary, execution:null, after:$before, decision:"stop_no_actions"}')")
        break
    fi

    execution=$(bash "$SELF_DIR/macro_exec.sh" --plan "$iter_dir/plan.json" "--$MODE" --output-dir "$iter_dir" --json || true)
    after=$(bash "$SELF_DIR/optimization_score.sh" --root "$ROOT" --struct "$STRUCT" --output-dir "$iter_dir" --json)
    decision="kept"
    if [[ "$MODE" == "dry-run" ]]; then
        decision="dry-run"
        stop_reason="dry_run_complete"
    else
        before_score=$(jq '.score' <<<"$before")
        after_score=$(jq '.score' <<<"$after")
        exec_ok=$(jq -r '.ok' <<<"$execution")
        if [[ "$exec_ok" != "true" || "$after_score" -le "$before_score" ]]; then
            restore_backups "$iter_dir/rollback.json"
            after=$(bash "$SELF_DIR/optimization_score.sh" --root "$ROOT" --struct "$STRUCT" --output-dir "$iter_dir" --json)
            decision="rolled_back"
            rolled_back=true
            stop_reason="no_score_improvement"
            iterations+=("$(jq -n --argjson iteration "$i" --argjson before "$before" --argjson suggestions "$suggestions" --argjson compiled "$compiled" --argjson execution "$execution" --argjson after "$after" --arg decision "$decision" '{iteration:$iteration, before:$before, suggestions:$suggestions.summary, compiled:$compiled.summary, execution:$execution.summary, after:$after, decision:$decision}')")
            break
        fi
        if [[ "$after_score" -eq 100 ]]; then
            stop_reason="perfect_score"
        fi
    fi
    iterations+=("$(jq -n --argjson iteration "$i" --argjson before "$before" --argjson suggestions "$suggestions" --argjson compiled "$compiled" --argjson execution "$execution" --argjson after "$after" --arg decision "$decision" '{iteration:$iteration, before:$before, suggestions:$suggestions.summary, compiled:$compiled.summary, execution:$execution.summary, after:$after, decision:$decision}')")
    [[ "$MODE" == "dry-run" ]] && break
    [[ "$stop_reason" == "perfect_score" ]] && break
done

iterations_json="[]"
[[ ${#iterations[@]} -gt 0 ]] && iterations_json=$(printf '%s\n' "${iterations[@]}" | jq -s '.')
final=$(bash "$SELF_DIR/optimization_score.sh" --root "$ROOT" --struct "$STRUCT" --output-dir "$OUT_DIR" --json)
report=$(jq -n \
  --arg mode "$MODE" \
  --arg root "$ROOT" \
  --arg struct "$STRUCT" \
  --arg generated_at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --arg stop_reason "$stop_reason" \
  --argjson budget "$BUDGET" \
  --argjson rolled_back "$rolled_back" \
  --argjson initial "$initial" \
  --argjson final "$final" \
  --argjson iterations "$iterations_json" \
  '{
    schema_version:"1.0",
    ok:($rolled_back|not),
    mode:$mode,
    generated_at:$generated_at,
    root:$root,
    struct:$struct,
    budget:$budget,
    stop_reason:$stop_reason,
    initial_score:$initial,
    final_score:$final,
    improvement:($final.score - $initial.score),
    rolled_back:$rolled_back,
    iterations:$iterations
  }')

printf '%s\n' "$report" > "$OUT_DIR/loop.json"
{
    echo "# Project Optimization Loop"
    echo
    jq -r '"- mode: " + .mode, "- ok: " + (.ok|tostring), "- initial score: " + (.initial_score.score|tostring), "- final score: " + (.final_score.score|tostring), "- improvement: " + (.improvement|tostring), "- stop: " + .stop_reason, "- rolled_back: " + (.rolled_back|tostring)' <<<"$report"
    echo
    echo "## Iterations"
    jq -r '.iterations[]? | "- iteration " + (.iteration|tostring) + " decision=" + .decision + " before=" + (.before.score|tostring) + " after=" + (.after.score|tostring)' <<<"$report"
} > "$OUT_DIR/loop.md"

if [[ "$JSON_OUT" == "1" ]]; then
    printf '%s\n' "$report"
else
    jq -r '"Project Optimization Loop\n\nTarget: " + .root + "\nMode: " + .mode + "\nInitial score: " + (.initial_score.score|tostring) + "\nFinal score: " + (.final_score.score|tostring) + "\nImprovement: " + (.improvement|tostring) + "\nStop: " + .stop_reason + "\nRolled back: " + (.rolled_back|tostring) + "\n\nReport: generated/optimization/loop.md"' <<<"$report"
fi

jq -e '.ok == true' <<<"$report" >/dev/null
