#!/opt/homebrew/bin/bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT
pass=0; fail=0; EXIT_CODE=0
check(){ local n="$1"; shift; if "$@" >/dev/null 2>&1; then echo "  [OK]   $n"; pass=$((pass+1)); else echo "  [FAIL] $n"; fail=$((fail+1)); EXIT_CODE=1; fi; }

mkdir -p "$TMP_DIR/src/api" "$TMP_DIR/tests" "$TMP_DIR/.simple_model/waivers"
cat > "$TMP_DIR/src/api/server.ts" <<'TS'
export function startServer(port: number): number { return port; }
export const serverHealth = true;
app.get("/health", () => serverHealth);
console.log(process.env.PORT);
TS
cat > "$TMP_DIR/tests/server.test.ts" <<'TS'
import { startServer } from "../src/api/server";
startServer(3000);
TS
cat > "$TMP_DIR/struct.json" <<'JSON'
{"schema_version":"3.0","modules":[{"name":"api","description":"api","owners":["team-api"],"checks":{"unit":"true"},"components":[{"name":"Server","description":"server","path":"src/api/server.ts","exports":["startServer"],"imports":[],"risk":"high"}]}]}
JSON
cat > "$TMP_DIR/.simple_model/waivers/w1.json" <<'JSON'
{"id":"w1","scope":{"rule":"undeclared_exports"},"reason":"adoption","owner":"team-api","expires":"2999-01-01"}
JSON

cd "$ROOT_DIR"
check "strict code facts schema" jq -e '.required|index("components")' specs/code-facts.json
bash generators/code_facts.sh --root "$TMP_DIR" --struct "$TMP_DIR/struct.json" --output "$TMP_DIR/facts1.json" --cache "$TMP_DIR/cache.json" --json >/dev/null
check "fact cache cold misses" bash -c "jq -e '.cache.misses == 1' '$TMP_DIR/facts1.json'"
bash generators/code_facts.sh --root "$TMP_DIR" --struct "$TMP_DIR/struct.json" --output "$TMP_DIR/facts2.json" --cache "$TMP_DIR/cache.json" --json >/dev/null
check "fact cache warm hits" bash -c "jq -e '.cache.hits == 1' '$TMP_DIR/facts2.json'"
check "interface signatures and hash" bash -c "bash generators/interface_scan.sh --root '$TMP_DIR' --struct '$TMP_DIR/struct.json' --json | jq -e '.components[0].interfaces[0].signature and .components[0].interface_hash'"
check "interface diff" bash -c "bash generators/interface_diff.sh --root '$TMP_DIR' --struct '$TMP_DIR/struct.json' --json | jq -e '.summary.added >= 1'"
check "surface scan routes env" bash -c "bash generators/surface_scan.sh --root '$TMP_DIR' --struct '$TMP_DIR/struct.json' --json | jq -e '.summary.routes == 1 and .summary.env == 1'"
scan=$(bash generators/interface_scan.sh --root "$TMP_DIR" --struct "$TMP_DIR/struct.json" --json)
check "struct suggest patch" bash -c "echo '$scan' | bash generators/struct_suggest.sh --json | jq -e '.summary.ops >= 1'"
check "waiver check" bash -c "bash generators/waiver_check.sh --dir '$TMP_DIR/.simple_model/waivers' --json | jq -e '.summary.waivers == 1'"
impact=$(bash generators/pr_impact.sh --root "$TMP_DIR" --struct "$TMP_DIR/struct.json" --files src/api/server.ts --json)
check "test select execute" bash -c "echo '$impact' | bash generators/test_select.sh --execute --json | jq -e '.mode == \"execute\" and .summary.failed == 0'"
check "risk factors" bash -c "echo '$impact' | bash generators/risk_score.sh --json | jq -e '.risk.factors|length >= 1'"
check "review routes reasons" bash -c "echo '$impact' | bash generators/review_route.sh --json | jq -e '.routes[0].reason == \"component_owner\"'"
gate=$(bash generators/pr_gate.sh --root "$TMP_DIR" --struct "$TMP_DIR/struct.json" --files src/api/server.ts --markdown "$TMP_DIR/gate.md" --json)
check "pr gate markdown" test -s "$TMP_DIR/gate.md"
check "pr comment marker" grep -q 'simple_model:pr-gate' "$TMP_DIR/gate.md"
check "mcp initialize" bash -c "printf '{\"id\":1,\"method\":\"initialize\"}\\n' | SIMPLE_MODEL_ROOT='$ROOT_DIR' bash tools/simple_model_mcp.sh | jq -e '.result.serverInfo.name == \"simple_model\"'"
check "mcp tools list" bash -c "printf '{\"id\":1,\"method\":\"tools/list\"}\\n' | SIMPLE_MODEL_ROOT='$ROOT_DIR' bash tools/simple_model_mcp.sh | jq -e '.result.tools|length >= 3'"
check "federation global ids" bash -c "printf '{\"repos\":[{\"name\":\"r\",\"path\":\"$TMP_DIR\",\"struct\":\"struct.json\"}]}' > '$TMP_DIR/fed.json'; bash generators/federation_resolve.sh '$TMP_DIR/fed.json' --json | jq -e '.components[0].id == \"r:api:Server\"'"
check "batch sizing" bash -c "echo '$impact' | bash generators/batch_plan.sh --json | jq -e '.summary.batches == 1'"
check "architecture debt remediation" bash -c "bash generators/architecture_debt.sh --root '$TMP_DIR' --struct '$TMP_DIR/struct.json' --json | jq -e '.findings[]? | has(\"remediation\")'"
check "dashboard generation" bash -c "bash generators/dashboard.sh '$TMP_DIR/dashboard.html' && grep -q 'Project Intelligence' '$TMP_DIR/dashboard.html'"
check "adoption playbook exists" test -f docs/ADOPTION_PLAYBOOK.md
check "evolution metrics" bash -c "bash examples/evolution-bench/run.sh | jq -e '.metrics.cache_invalidations == 1'"
diff=$(bash generators/interface_diff.sh --root "$TMP_DIR" --struct "$TMP_DIR/struct.json" --json)
check "release contract" bash -c "echo '$diff' | bash generators/release_contract.sh --json | jq -e '.summary.additive >= 1'"
check "todo done count" bash -c "jq -e '[.todos[]|select(.status==\"done\")]|length == 32' todo.json"
echo "  passed: $pass"; echo "  failed: $fail"; exit $EXIT_CODE
