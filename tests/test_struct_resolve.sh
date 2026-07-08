#!/opt/homebrew/bin/bash
# ============================================================================
# tests/test_struct_resolve.sh — multi-file struct + adoption-mode tests
# ============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

pass=0
fail=0
EXIT_CODE=0

check() {
    local name="$1"; shift
    if "$@" >/dev/null 2>&1; then
        printf '  [OK]   %s\n' "$name"
        pass=$((pass + 1))
    else
        printf '  [FAIL] %s\n' "$name"
        fail=$((fail + 1))
        EXIT_CODE=1
    fi
}

check_rc() {
    local name="$1" want="$2"; shift 2
    local got=0
    "$@" >/dev/null 2>&1 || got=$?
    if [[ "$got" == "$want" ]]; then
        printf '  [OK]   %s (exit %d)\n' "$name" "$got"
        pass=$((pass + 1))
    else
        printf '  [FAIL] %s (exit %d, want %d)\n' "$name" "$got" "$want"
        fail=$((fail + 1))
        EXIT_CODE=1
    fi
}

echo "==============================================="
echo "  struct_resolve / adoption tests"
echo "==============================================="
echo

mkdir -p "$TMP_DIR/struct.modules" "$TMP_DIR/src/api" "$TMP_DIR/src/web" "$TMP_DIR/out"

cat > "$TMP_DIR/struct.json" <<'JSON'
{
  "schema_version": "3.0",
  "description": "multi-file fixture",
  "includes": [
    "struct.modules/backend.json",
    "struct.modules/frontend.json"
  ],
  "phases": [
    {"phase":"build","order":1,"mode":"sequential","description":"build","core_components":["ApiServer","WebApp"]}
  ]
}
JSON

cat > "$TMP_DIR/struct.modules/backend.json" <<'JSON'
{
  "schema_version": "3.0",
  "modules": [
    {
      "name": "backend",
      "description": "backend",
      "language": "typescript",
      "owners": ["team-api"],
      "checks": {"unit": "npm test --workspace api"},
      "components": [
        {
          "name": "ApiServer",
          "description": "api",
          "path": "src/api/server.ts",
          "exports": ["startServer"],
          "imports": [],
          "risk": "high",
          "todos": [
            {"id":"api_done","task":"api exists","status":"done"}
          ]
        }
      ]
    }
  ]
}
JSON

cat > "$TMP_DIR/struct.modules/frontend.json" <<'JSON'
{
  "schema_version": "3.0",
  "modules": [
    {
      "name": "frontend",
      "description": "frontend",
      "language": "typescript",
      "components": [
        {
          "name": "WebApp",
          "description": "web",
          "path": "src/web/app.ts",
          "exports": ["renderApp"],
          "imports": ["ApiServer"],
          "todos": []
        }
      ]
    }
  ]
}
JSON

cat > "$TMP_DIR/src/api/server.ts" <<'TS'
export function startServer() {}
export const serverHealth = true;
TS
cat > "$TMP_DIR/src/web/app.ts" <<'TS'
export function renderApp() {}
TS
cat > "$TMP_DIR/src/web/orphan.ts" <<'TS'
export const orphan = true;
TS

RESOLVED="$TMP_DIR/out/resolved.struct.json"

echo "[test 1] resolver merges include fragments"
check_rc "struct_resolve exits 0" 0 \
    /opt/homebrew/bin/bash "$ROOT_DIR/generators/struct_resolve.sh" --struct "$TMP_DIR/struct.json" --output "$RESOLVED"
check "resolved json parses" jq empty "$RESOLVED"
check "resolved has two modules" bash -c "jq -e '.modules | length == 2' '$RESOLVED'"
check "resolved preserves root phase" bash -c "jq -e '.phases[0].core_components | index(\"WebApp\")' '$RESOLVED'"
check "resolved records provenance" bash -c "jq -e '._resolved.source_count == 3' '$RESOLVED'"
check "component metadata survives" bash -c "jq -e '.modules[] | select(.name==\"backend\") | .components[0].risk == \"high\"' '$RESOLVED'"
echo

echo "[test 2] bootstrap auto-resolves include roots"
check_rc "bootstrap validate include root" 0 \
    /opt/homebrew/bin/bash "$ROOT_DIR/bootstrap.sh" --struct "$TMP_DIR/struct.json" --output "$TMP_DIR/out/bootstrap" --validate
check "bootstrap wrote resolved struct" test -f "$TMP_DIR/out/bootstrap/.bootstrap/resolved.struct.json"
check "bootstrap resolved struct has ApiServer" bash -c "jq -e '[.modules[].components[].name] | index(\"ApiServer\")' '$TMP_DIR/out/bootstrap/.bootstrap/resolved.struct.json'"
echo

echo "[test 3] conflicts and unsafe paths fail"
cat > "$TMP_DIR/conflict.json" <<'JSON'
{
  "schema_version": "3.0",
  "includes": ["struct.modules/backend.json"],
  "modules": [
    {"name":"backend","description":"different","components":[{"name":"ApiServer","description":"api"}]}
  ]
}
JSON
check_rc "scalar conflict fails" 1 \
    /opt/homebrew/bin/bash "$ROOT_DIR/generators/struct_resolve.sh" --struct "$TMP_DIR/conflict.json" --output "$TMP_DIR/out/conflict.json"
cat > "$TMP_DIR/unsafe.json" <<'JSON'
{"schema_version":"3.0","includes":["../outside.json"]}
JSON
check_rc "unsafe include path fails" 1 \
    /opt/homebrew/bin/bash "$ROOT_DIR/generators/struct_resolve.sh" --struct "$TMP_DIR/unsafe.json" --output "$TMP_DIR/out/unsafe.json"
echo

echo "[test 4] repo ingest and adoption audit"
INGESTED="$TMP_DIR/out/struct.ingested.json"
check_rc "ingest_repo exits 0" 0 \
    /opt/homebrew/bin/bash "$ROOT_DIR/generators/ingest_repo.sh" --root "$TMP_DIR" --output "$INGESTED"
check "ingested json parses" jq empty "$INGESTED"
check "ingested components include server" bash -c "jq -e '[.modules[].components[].path] | index(\"src/api/server.ts\")' '$INGESTED'"
check "ingested exports include startServer" bash -c "jq -e '[.modules[].components[] | select(.path==\"src/api/server.ts\") | .exports[]] | index(\"startServer\")' '$INGESTED'"
AUDIT_JSON=$(/opt/homebrew/bin/bash "$ROOT_DIR/generators/adoption_audit.sh" --root "$TMP_DIR" --struct "$RESOLVED" --json)
check "adoption audit reports one unmanaged file" bash -c "echo '$AUDIT_JSON' | jq -e '.unmanaged_files == 1'"
check "adoption audit names orphan" bash -c "echo '$AUDIT_JSON' | jq -e '.unmanaged | index(\"src/web/orphan.ts\")'"
check_rc "strict adoption audit fails on unmanaged" 1 \
    /opt/homebrew/bin/bash "$ROOT_DIR/generators/adoption_audit.sh" --root "$TMP_DIR" --struct "$RESOLVED" --strict
echo

echo "[test 5] interface scanner"
SCAN_JSON=$(/opt/homebrew/bin/bash "$ROOT_DIR/generators/interface_scan.sh" --root "$TMP_DIR" --struct "$RESOLVED" --json)
check "interface scan json parses" bash -c "echo '$SCAN_JSON' | jq empty"
check "interface scan sees two components" bash -c "echo '$SCAN_JSON' | jq -e '.summary.components_scanned == 2'"
check "interface scan detects undeclared export" bash -c "echo '$SCAN_JSON' | jq -e '.summary.undeclared_exports == 1'"
check "interface scan names serverHealth" bash -c "echo '$SCAN_JSON' | jq -e '.components[] | select(.component==\"ApiServer\") | .undeclared_exports | index(\"serverHealth\")'"
check_rc "strict interface scan fails on undeclared export" 1 \
    /opt/homebrew/bin/bash "$ROOT_DIR/generators/interface_scan.sh" --root "$TMP_DIR" --struct "$RESOLVED" --strict
BOOT_SCAN=$(/opt/homebrew/bin/bash "$ROOT_DIR/bootstrap.sh" --struct "$TMP_DIR/struct.json" --output "$TMP_DIR/out/bootstrap-scan" --interface-scan "$TMP_DIR" --json)
check "bootstrap interface scan auto-resolves includes" bash -c "echo '$BOOT_SCAN' | jq -e '.summary.undeclared_exports == 1'"
echo

echo "  passed: $pass"
echo "  failed: $fail"
echo "==============================================="
exit $EXIT_CODE
