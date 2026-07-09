#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"; rm -rf "$ROOT_DIR/generated/optimization" "$ROOT_DIR/generated/optimization-smoke"' EXIT

pass=0
fail=0
EXIT_CODE=0
check() {
    local n="$1"; shift
    if "$@" >/dev/null 2>&1; then
        echo "  [OK]   $n"
        pass=$((pass + 1))
    else
        echo "  [FAIL] $n"
        fail=$((fail + 1))
        EXIT_CODE=1
    fi
}

cd "$ROOT_DIR"
cp -R examples/optimization-target-repo "$TMP_DIR/repo"
WRAP="$ROOT_DIR/plugins/simple-model-project-intelligence/skills/simple-model-project-intelligence/scripts/simple_model_pi.sh"

check "macro registry json" bash -c "generators/macro_registry.sh --json | jq -e '.ok == true and .summary.macros >= 6 and .summary.code >= 3 and .summary.exec >= 3'"
check "macro registry command output" bash -c "generators/macro_registry.sh | grep -q 'split_struct_include'"
check "macro suggest json" bash -c "generators/macro_suggest.sh --root '$TMP_DIR/repo' --struct '$TMP_DIR/repo/struct.json' --output-dir '$TMP_DIR/suggest' --json | jq -e '.ok == true and .summary.suggestions == 4 and all(.specs[]; .kind == \"generated_macro\")'"
check "macro suggest writes specs" bash -c "test -s '$TMP_DIR/suggest/macro-suggestions.json' && find '$TMP_DIR/suggest/specs' -type f | grep -q 'generated.field_sync.exports.server.json'"
check "macro compile json" bash -c "generators/macro_compile.sh --suggestions '$TMP_DIR/suggest/macro-suggestions.json' --root '$TMP_DIR/repo' --struct '$TMP_DIR/repo/struct.json' --output-dir '$TMP_DIR/compiled' --json | jq -e '.ok == true and .summary.specs == 4 and .summary.actions == 4'"
check "macro compile writes plan" bash -c "test -s '$TMP_DIR/compiled/compiled-plan.json' && test -s '$TMP_DIR/compiled/plan.json'"
bad_suggest="$TMP_DIR/bad-suggestions.json"
jq '.specs[0].rewrite.mode = "unsafe_shell"' "$TMP_DIR/suggest/macro-suggestions.json" > "$bad_suggest"
check "bad macro spec fixture fails" bash -c "! generators/macro_compile.sh --suggestions '$bad_suggest' --root '$TMP_DIR/repo' --struct '$TMP_DIR/repo/struct.json' --output-dir '$TMP_DIR/bad-compile' --json"
check "optimization score json" bash -c "generators/optimization_score.sh --root '$TMP_DIR/repo' --struct '$TMP_DIR/repo/struct.json' --output-dir '$TMP_DIR/score' --json | jq -e '.score == 73 and .factors.interface_drift == 2 and .factors.import_drift == 1'"
check "optimization plan json" bash -c "generators/optimization_plan.sh --root '$TMP_DIR/repo' --struct '$TMP_DIR/repo/struct.json' --output-dir '$TMP_DIR/out' --json | jq -e '.ok == true and .summary.actions == 4'"
check "optimization plan writes reports" bash -c "test -s '$TMP_DIR/out/plan.json' && test -s '$TMP_DIR/out/report.md'"
check "optimization plan is deterministic sans timestamp" bash -c "generators/optimization_plan.sh --root '$TMP_DIR/repo' --struct '$TMP_DIR/repo/struct.json' --output-dir '$TMP_DIR/out_a' --json >/dev/null; generators/optimization_plan.sh --root '$TMP_DIR/repo' --struct '$TMP_DIR/repo/struct.json' --output-dir '$TMP_DIR/out_b' --json >/dev/null; diff <(jq 'del(.generated_at)' '$TMP_DIR/out_a/plan.json') <(jq 'del(.generated_at)' '$TMP_DIR/out_b/plan.json')"
check "planner orders split last" bash -c "jq -e '([.actions[].macro_id][-1]) == \"split_struct_include\"' '$TMP_DIR/out/plan.json'"
check "planner sees export drift" bash -c "jq -e '.actions[] | select(.macro_id==\"normalize_component_exports\" and .target.component==\"Server\" and (.evidence.undeclared_exports|index(\"healthCheck\")))' '$TMP_DIR/out/plan.json'"
check "planner sees import drift" bash -c "jq -e '.actions[] | select(.macro_id==\"sync_struct_imports_from_code_facts\" and .target.component==\"Server\" and .target.target==\"UserService\")' '$TMP_DIR/out/plan.json'"

before_hash=$(if command -v sha256sum >/dev/null 2>&1; then sha256sum "$TMP_DIR/repo/struct.json" | awk '{print $1}'; else shasum -a 256 "$TMP_DIR/repo/struct.json" | awk '{print $1}'; fi)
check "macro dry run json" bash -c "generators/macro_exec.sh --plan '$TMP_DIR/out/plan.json' --output-dir '$TMP_DIR/out' --dry-run --json | jq -e '.ok == true and .summary.dry_run == 4 and .summary.applied == 0'"
after_hash=$(if command -v sha256sum >/dev/null 2>&1; then sha256sum "$TMP_DIR/repo/struct.json" | awk '{print $1}'; else shasum -a 256 "$TMP_DIR/repo/struct.json" | awk '{print $1}'; fi)
check "macro dry run does not edit struct" test "$before_hash" = "$after_hash"
check "macro dry run writes patch previews" bash -c "find '$TMP_DIR/out/patches' -type f | grep -q 'normalize_component_exports'"

check "macro apply json" bash -c "generators/macro_exec.sh --plan '$TMP_DIR/out/plan.json' --output-dir '$TMP_DIR/out' --apply --json | jq -e '.ok == true and .summary.applied == 4 and .summary.failed == 0'"
check "macro apply writes rollback manifest" bash -c "test -s '$TMP_DIR/out/rollback.json' && jq -e '(.backups|length) >= 1' '$TMP_DIR/out/rollback.json'"
check "macro apply splits struct includes" bash -c "jq -e '.includes == [\"struct.modules/api.json\", \"struct.modules/core.json\"] and (.modules|not)' '$TMP_DIR/repo/struct.json'"
check "macro apply normalizes exports" bash -c "jq -e '.modules[0].components[0].exports == [\"healthCheck\", \"startServer\"]' '$TMP_DIR/repo/struct.modules/api.json'"
check "macro apply syncs imports" bash -c "jq -e '.modules[0].components[0].imports == [\"UserService\"]' '$TMP_DIR/repo/struct.modules/api.json'"
check "macro apply keeps resolved struct valid" bash -c "OUTPUT_DIR='$TMP_DIR/generated' generators/struct_resolve.sh --struct '$TMP_DIR/repo/struct.json' --json | jq -e '.ok == true and .source_count == 3' && jq -e '(.modules|length) == 2' '$TMP_DIR/generated/.bootstrap/resolved.struct.json'"

cp -R examples/optimization-target-repo "$TMP_DIR/loop-repo"
check "optimization loop dry-run" bash -c "generators/optimization_loop.sh --root '$TMP_DIR/loop-repo' --struct '$TMP_DIR/loop-repo/struct.json' --output-dir '$TMP_DIR/loop-dry' --budget 2 --dry-run --json | jq -e '.ok == true and .mode == \"dry-run\" and .improvement == 0 and .iterations[0].decision == \"dry-run\"'"
check "optimization loop apply improves score" bash -c "generators/optimization_loop.sh --root '$TMP_DIR/loop-repo' --struct '$TMP_DIR/loop-repo/struct.json' --output-dir '$TMP_DIR/loop-apply' --budget 2 --apply --json | jq -e '.ok == true and .improvement > 0 and .rolled_back == false and .final_score.score > .initial_score.score'"
check "optimization loop apply writes loop report" bash -c "test -s '$TMP_DIR/loop-apply/loop.json' && test -s '$TMP_DIR/loop-apply/loop.md'"

bad_plan="$TMP_DIR/bad-plan.json"
jq '.actions = [{macro_id:"missing_macro", auto_apply:true, target:{}, evidence:{}, risk:"low"}]' "$TMP_DIR/out/plan.json" > "$bad_plan"
check "bad macro fixture fails" bash -c "! generators/macro_exec.sh --plan '$bad_plan' --output-dir '$TMP_DIR/bad-out' --dry-run --json"

cp -R examples/optimization-target-repo "$TMP_DIR/wrap-repo"
check "plugin macros command" bash -c "'$WRAP' macros --json | jq -e '.ok == true and .summary.macros >= 6'"
check "plugin macro-suggest command" bash -c "'$WRAP' --target-root '$TMP_DIR/wrap-repo' --struct '$TMP_DIR/wrap-repo/struct.json' macro-suggest --json | jq -e '.ok == true and .summary.suggestions == 4'"
check "plugin macro-compile command" bash -c "'$WRAP' --target-root '$TMP_DIR/wrap-repo' --struct '$TMP_DIR/wrap-repo/struct.json' macro-compile --json | jq -e '.ok == true and .summary.actions == 4'"
check "plugin score command" bash -c "'$WRAP' --target-root '$TMP_DIR/wrap-repo' --struct '$TMP_DIR/wrap-repo/struct.json' score --json | jq -e '.score == 73'"
check "plugin optimize dry run json" bash -c "'$WRAP' --target-root '$TMP_DIR/wrap-repo' --struct '$TMP_DIR/wrap-repo/struct.json' optimize --dry-run --json | jq -e '.ok == true and .execution.summary.dry_run == 4'"
check "plugin optimize-loop dry run json" bash -c "'$WRAP' --target-root '$TMP_DIR/wrap-repo' --struct '$TMP_DIR/wrap-repo/struct.json' optimize-loop --budget 2 --dry-run --json | jq -e '.ok == true and .mode == \"dry-run\"'"
check "plugin optimize terminal report" bash -c "'$WRAP' --target-root '$TMP_DIR/wrap-repo' --struct '$TMP_DIR/wrap-repo/struct.json' optimize --dry-run | grep -q 'Project Optimization Report'"
check "plugin macro-run command" bash -c "'$WRAP' macro-run --plan '$ROOT_DIR/generated/optimization/plan.json' --dry-run --json | jq -e '.ok == true'"
check "mcp plugin optimize dry run" bash -c "printf '{\"id\":1,\"method\":\"tools/call\",\"params\":{\"name\":\"plugin_optimize\",\"arguments\":{\"target_root\":\"$TMP_DIR/wrap-repo\",\"struct\":\"$TMP_DIR/wrap-repo/struct.json\"}}}\\n' | SIMPLE_MODEL_ROOT='$ROOT_DIR' bash tools/simple_model_mcp.sh | jq -e '.result.ok == true and .result.execution.summary.dry_run == 4'"
check "mcp plugin optimize-loop dry run" bash -c "printf '{\"id\":1,\"method\":\"tools/call\",\"params\":{\"name\":\"plugin_optimize_loop\",\"arguments\":{\"target_root\":\"$TMP_DIR/wrap-repo\",\"struct\":\"$TMP_DIR/wrap-repo/struct.json\"}}}\\n' | SIMPLE_MODEL_ROOT='$ROOT_DIR' bash tools/simple_model_mcp.sh | jq -e '.result.ok == true and .result.mode == \"dry-run\"'"

echo "  passed: $pass"
echo "  failed: $fail"
exit $EXIT_CODE
