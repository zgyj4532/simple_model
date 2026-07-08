#!/opt/homebrew/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

pass=0; fail=0; EXIT_CODE=0
check() { local name="$1"; shift; if "$@" >/dev/null 2>&1; then echo "  [OK]   $name"; pass=$((pass+1)); else echo "  [FAIL] $name"; fail=$((fail+1)); EXIT_CODE=1; fi; }

mkdir -p "$TMP_DIR/src/api" "$TMP_DIR/tests" "$TMP_DIR/generated/.ai/work_records"
cat > "$TMP_DIR/src/api/db.ts" <<'TS'
export function queryDb(sql: string) { return sql; }
TS
cat > "$TMP_DIR/src/api/server.ts" <<'TS'
import { queryDb } from "./db";
export function startServer(port: number) { return queryDb(String(port)); }
export const serverHealth = true;
TS
cat > "$TMP_DIR/tests/server.test.ts" <<'TS'
import { startServer } from "../src/api/server";
startServer(3000);
TS
cat > "$TMP_DIR/CODEOWNERS" <<'EOF'
* @platform/team
EOF
cat > "$TMP_DIR/struct.json" <<'JSON'
{
  "schema_version": "3.0",
  "modules": [
    {
      "name": "api",
      "description": "api",
      "language": "typescript",
      "owners": ["team-api"],
      "checks": {"unit":"npm test"},
      "components": [
        {"name":"Db","description":"db","path":"src/api/db.ts","exports":["queryDb"],"imports":[],"risk":"medium"},
        {"name":"Server","description":"server","path":"src/api/server.ts","exports":["startServer"],"imports":["Db"],"risk":"high"}
      ]
    }
  ]
}
JSON
cat > "$TMP_DIR/generated/.ai/work_records/server.json" <<'JSON'
{"schema_version":"1.0","todo_id":"server","agent":"generic","status":"done","files_changed":["src/api/server.ts"],"commands":["npm test"],"tests":["npm test"],"summary":"ok"}
JSON

cd "$ROOT_DIR"
check "code facts json" bash -c "bash generators/code_facts.sh --root '$TMP_DIR' --struct '$TMP_DIR/struct.json' --output '$TMP_DIR/code_facts.json' --json | jq -e '.components|length == 2'"
check "interface v2 sees undeclared export" bash -c "bash generators/interface_scan.sh --root '$TMP_DIR' --struct '$TMP_DIR/struct.json' --json | jq -e '.summary.undeclared_exports == 1'"
check "import graph edge" bash -c "bash generators/import_graph_scan.sh --root '$TMP_DIR' --struct '$TMP_DIR/struct.json' --json | jq -e '.summary.edges >= 1'"
check "test surface scan" bash -c "bash generators/test_surface_scan.sh --root '$TMP_DIR' --struct '$TMP_DIR/struct.json' --json | jq -e '.summary.tests == 1'"
check "ownership resolve" bash -c "bash generators/ownership_resolve.sh --root '$TMP_DIR' --struct '$TMP_DIR/struct.json' --json | jq -e '.summary.components == 2'"
check "interface gate json" bash -c "bash generators/interface_drift_gate.sh --root '$TMP_DIR' --struct '$TMP_DIR/struct.json' --json | jq -e '.warnings == 1'"
check "dependency gate json" bash -c "bash generators/dependency_drift_gate.sh --root '$TMP_DIR' --struct '$TMP_DIR/struct.json' --json | jq -e '.ok == true'"
impact=$(bash generators/pr_impact.sh --root "$TMP_DIR" --struct "$TMP_DIR/struct.json" --files src/api/server.ts --json)
check "pr impact component" bash -c "echo '$impact' | jq -e '.summary.components == 1'"
check "risk score" bash -c "echo '$impact' | bash generators/risk_score.sh --json | jq -e '.risk.level == \"high\" or .risk.level == \"medium\"'"
check "review route" bash -c "echo '$impact' | bash generators/review_route.sh --json | jq -e '.reviewers|length >= 1'"
check "work records" bash -c "bash generators/work_record_collect.sh --dir '$TMP_DIR/generated/.ai/work_records' --json | jq -e '.summary.records == 1'"
check "test select" bash -c "echo '$impact' | bash generators/test_select.sh --json | jq -e '.summary.commands == 1'"
check "pr gate" bash -c "bash generators/pr_gate.sh --root '$TMP_DIR' --struct '$TMP_DIR/struct.json' --files src/api/server.ts --json | jq -e '.impact.summary.components == 1'"
check "github action generator" bash -c "bash generators/github_action.sh '$TMP_DIR/pr-gate.yml' && test -f '$TMP_DIR/pr-gate.yml'"
check "mcp code facts" bash -c "printf '{\"id\":1,\"method\":\"code_facts\"}\\n' | SIMPLE_MODEL_ROOT='$ROOT_DIR' bash tools/simple_model_mcp.sh | jq -e '.jsonrpc == \"2.0\"'"
cat > "$TMP_DIR/federation.json" <<JSON
{"repos":[{"name":"fixture","path":"$TMP_DIR","struct":"struct.json"}]}
JSON
check "federation resolve" bash -c "bash generators/federation_resolve.sh '$TMP_DIR/federation.json' --json | jq -e '.summary.repos == 1'"
check "batch plan" bash -c "echo '$impact' | bash generators/batch_plan.sh --json | jq -e '.summary.components == 1'"
check "architecture debt" bash -c "bash generators/architecture_debt.sh --root '$TMP_DIR' --struct '$TMP_DIR/struct.json' --json | jq -e '.summary.findings >= 0'"
check "todo roadmap done count" bash -c "jq -e '[.todos[]|select(.status==\"done\")]|length >= 20' todo.json"

echo "  passed: $pass"
echo "  failed: $fail"
exit $EXIT_CODE
