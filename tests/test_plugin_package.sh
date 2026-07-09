#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"; rm -rf "$ROOT_DIR/dist" "$ROOT_DIR/generated/plugin-self-audit" "$ROOT_DIR/generated/plugin-demo"' EXIT
pass=0; fail=0; EXIT_CODE=0
check(){ local n="$1"; shift; if "$@" >/dev/null 2>&1; then echo "  [OK]   $n"; pass=$((pass+1)); else echo "  [FAIL] $n"; fail=$((fail+1)); EXIT_CODE=1; fi; }

WRAP="$ROOT_DIR/plugins/simple-model-project-intelligence/skills/simple-model-project-intelligence/scripts/simple_model_pi.sh"
SRC_WRAP="$ROOT_DIR/codex/skills/simple-model-project-intelligence/scripts/simple_model_pi.sh"
TARGET="$ROOT_DIR/examples/plugin-target-repo"

cd "$ROOT_DIR"
check "marketplace json" jq -e '.name=="simple-model" and .plugins[0].name=="simple-model-project-intelligence"' .agents/plugins/marketplace.json
check "plugin manifest json" jq -e '.name=="simple-model-project-intelligence" and .version=="0.6.0" and .skills=="./skills/"' plugins/simple-model-project-intelligence/.codex-plugin/plugin.json
check "skill frontmatter has name" grep -q '^name: simple-model-project-intelligence$' codex/skills/simple-model-project-intelligence/SKILL.md
check "skill openai yaml parseable-ish" grep -q 'display_name: "Simple Model Project Intelligence"' codex/skills/simple-model-project-intelligence/agents/openai.yaml
check "no plugin TODO placeholders" bash -c "! rg -n 'TODO|\\[TODO|placeholder' codex/skills/simple-model-project-intelligence plugins/simple-model-project-intelligence .agents/plugins"
check "source and plugin skill sync" bash tools/sync_codex_plugin.sh --check
check "wrapper help" "$WRAP" help
check "source wrapper commands json" bash -c "'$SRC_WRAP' commands --json | jq -e '.commands|length >= 10'"
check "plugin wrapper commands json" bash -c "'$WRAP' commands --json | jq -e '.commands[]|select(.name==\"doctor\")'"
check "command manifest coverage matrix" bash -c "'$WRAP' commands --json | jq -e 'all(.commands[]; ((.tests // [])|length) > 0 and has(\"release_gate\"))'"
check "doctor json" bash -c "'$WRAP' --target-root '$TARGET' doctor --json | jq -e '.ok == true and .checks.jq == true'"
check "doctor environment matrix" bash -c "'$WRAP' --target-root '$TARGET' doctor --json | jq -e '.environment.os and .environment.bash_version and .environment.jq_version and .environment.git_version and .environment.plugin_cache and (.environment.dirty_files|type==\"number\")'"
check "cross repo doctor with SIMPLE_MODEL_HOME" bash -c "cd '$TMP_DIR' && SIMPLE_MODEL_HOME='$ROOT_DIR' '$WRAP' --target-root '$TARGET' doctor --json | jq -e '.simple_model_home == \"$ROOT_DIR\"'"
check "cross repo interface scan" bash -c "cd '$TMP_DIR' && SIMPLE_MODEL_HOME='$ROOT_DIR' '$WRAP' --target-root '$TARGET' --struct '$TARGET/struct.json' interfaces | jq -e '.components[0].component == \"Server\"'"
check "empty adoption audit array" bash -c "'$WRAP' audit | jq -e '.unmanaged_files == 0 and .unmanaged == []'"
check "pr gate without explicit files" bash -c "'$WRAP' pr-gate . | jq -e '.impact.summary.files >= 0'"
check "readme command contract list" bash -c "bash tools/readme_command_contract.sh --list | grep -q 'codex plugin add simple-model-project-intelligence@simple-model'"
check "readme command contract check" bash tools/readme_command_contract.sh --check
check "readme command contract failure fixture" bash -c "tmp='$TMP_DIR/bad-readme.md'; printf '<!-- simple_model:test-command:start bad -->\nnot-a-real-command --flag\n<!-- simple_model:test-command:end -->\n' > \"\$tmp\"; ! bash tools/readme_command_contract.sh --check --readme \"\$tmp\""
check "self check json" bash -c "'$WRAP' self-check --json | jq -e '.ok == true and (.command_coverage.untested == [])'"
check "self check severity schema" bash -c "'$WRAP' self-check --json | jq -e '.schema_version == \"1.0\" and .summary.fatal == 0 and .summary.blocking == 0 and all(.checks[]; .severity and .remediation)'"
check "self check writes reports" bash -c "test -s generated/plugin-self-audit/plugin-self-audit.json && test -s generated/plugin-self-audit/plugin-self-audit.md && test -s generated/plugin-self-audit/latest.json"
check "self audit history" bash -c "find generated/plugin-self-audit/history -type f -name '*.json' | grep -q ."
check "self audit json" bash -c "'$WRAP' self-audit --json | jq -e '.ok == true'"
check "self release dry run" bash -c "'$WRAP' self-release --version 0.6.0 --dry-run --json | jq -e '(.ok == true) and (.mode == \"dry-run\")'"
check "self release stages" bash -c "'$WRAP' self-release --version 0.6.0 --dry-run --json | jq -e '.ok == true and (([.stages[].name] | index(\"tag-check\")) != null) and ((.rollback|length) > 0)'"
check "wrong package version fails" bash -c "! bash tools/package_codex_plugin.sh --version 9.9.9"
check "plugin demo" bash -c "bash examples/plugin-demo/run.sh | jq -e '.ok == true'"
check "package plugin" bash -c "bash tools/package_codex_plugin.sh --version 0.6.0 | jq -e '.ok == true and ((.sha256|length) == 64)'"
check "package zip exists" test -s dist/simple-model-project-intelligence-plugin-0.6.0.zip
check "release manifest in zip" bash -c "zipinfo -1 dist/simple-model-project-intelligence-plugin-0.6.0.zip | grep -q 'simple-model-project-intelligence/release-manifest.json'"
check "release manifest has file hashes" bash -c "unzip -p dist/simple-model-project-intelligence-plugin-0.6.0.zip simple-model-project-intelligence/release-manifest.json | jq -e '.schema_version == \"1.0\" and .plugin == \"simple-model-project-intelligence\" and .version == \"0.6.0\" and (.files|length > 0) and all(.files[]; .path and .sha256)'"
check "skill drift failure fixture" bash -c "printf '\n# drift fixture\n' >> plugins/simple-model-project-intelligence/skills/simple-model-project-intelligence/SKILL.md; ! bash tools/sync_codex_plugin.sh --check; bash tools/sync_codex_plugin.sh --sync"
check "plugin docs mention update" grep -q 'Update Or Remove' docs/CODEX_PLUGIN.md
check "readme plugin commands documented" bash -c "grep -q 'codex plugin marketplace add' README.md && grep -q 'codex plugin add simple-model-project-intelligence@simple-model' README.md && grep -q 'simple_model_pi.sh doctor' README.md && grep -q 'simple_model_pi.sh commands --json' README.md && grep -q 'simple_model_pi.sh self-check --json' README.md"
check "plugin workflow exists" test -f .github/workflows/plugin.yml
check "layered plugin workflows exist" bash -c "test -f .github/workflows/plugin-fast.yml && test -f .github/workflows/plugin-nightly.yml && test -f .github/workflows/plugin-release.yml"
check "mcp plugin tools list" bash -c "printf '{\"id\":1,\"method\":\"tools/list\"}\\n' | SIMPLE_MODEL_ROOT='$ROOT_DIR' bash tools/simple_model_mcp.sh | jq -e '.result.tools[]|select(.name==\"plugin_doctor\")'"
check "mcp plugin doctor call" bash -c "printf '{\"id\":1,\"method\":\"tools/call\",\"params\":{\"name\":\"plugin_doctor\",\"arguments\":{\"target_root\":\"$TARGET\"}}}\\n' | SIMPLE_MODEL_ROOT='$ROOT_DIR' bash tools/simple_model_mcp.sh | jq -e '.result.ok == true'"
check "mcp plugin self-check call" bash -c "printf '{\"id\":1,\"method\":\"tools/call\",\"params\":{\"name\":\"plugin_self_check\",\"arguments\":{\"target_root\":\"$TARGET\"}}}\\n' | SIMPLE_MODEL_ROOT='$ROOT_DIR' bash tools/simple_model_mcp.sh | jq -e '.result.ok == true'"
check "todo done count" bash -c "jq -e '[.todos[]|select(.status==\"done\")]|length == 12' todo.json"

echo "  passed: $pass"
echo "  failed: $fail"
exit $EXIT_CODE
