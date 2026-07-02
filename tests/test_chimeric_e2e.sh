#!/usr/bin/env bash
# tests/test_chimeric_e2e.sh — chimeric 流水线端到端测试
# 用法: bash tests/test_chimeric_e2e.sh
# 不依赖外网/AI；使用仓库自带的 petstore.json fixture。
# 覆盖: spec.sh (IR 规范化) → adapter.sh (代码渲染) → verify.sh (4 模式 + 失败路径)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
TMP_DIR="$(mktemp -d)"
FIXTURE="$ROOT_DIR/tests/fixtures/openapi/petstore.json"
EXIT_CODE=0

pass=0
fail=0
check() {
    local name="$1"; shift
    if "$@" >/dev/null 2>&1; then
        printf '  [OK]   %s\n' "$name"
        pass=$((pass+1))
    else
        printf '  [FAIL] %s\n' "$name"
        fail=$((fail+1))
        EXIT_CODE=1
    fi
}
# check_rc <name> <expected_rc> <cmd...>  — 断言命令退出码 == expected
check_rc() {
    local name="$1" want="$2"; shift 2
    local got=0
    "$@" >/dev/null 2>&1 || got=$?
    if [[ "$got" == "$want" ]]; then
        printf '  [OK]   %s (exit %d)\n' "$name" "$got"
        pass=$((pass+1))
    else
        printf '  [FAIL] %s (exit %d, want %d)\n' "$name" "$got" "$want"
        fail=$((fail+1))
        EXIT_CODE=1
    fi
}

cleanup() { rm -rf "$TMP_DIR"; }
trap cleanup EXIT

PROJ="$TMP_DIR/project"
mkdir -p "$PROJ/generated"
cd "$PROJ"

# struct.json: 声明一个 python 模块，让 adapter 知道出哪种语言
cat > struct.json <<'EOF'
{
  "schema_version": "3.0",
  "modules": [{
    "name": "api", "language": "python", "description": "test module",
    "components": [{"name": "PetAPI", "description": "x", "exports": ["pet_id", "pet_name"]}]
  }]
}
EOF

# chimeric.json: 两个 integration_point；create_pet 带 field_mapping + invariant + golden
cat > chimeric.json <<EOF
{
  "schema_version": "1.0",
  "bridge": { "name": "petstore", "description": "petstore e2e test" },
  "self": {
    "project": "this",
    "components": [{"module": "api", "component": "PetAPI", "exports": ["pet_id", "pet_name"]}]
  },
  "peer": {
    "name": "petstore",
    "spec": { "kind": "openapi_3", "source": "$FIXTURE" }
  },
  "integration_points": [
    {
      "id": "create_pet",
      "self_export": "pet_id",
      "peer_path": "/pet",
      "peer_method": "POST",
      "field_mapping": {
        "pet_id":   { "from": "id",   "to": "pet_id",   "type": "string", "required": true },
        "pet_name": { "from": "name", "to": "pet_name", "type": "string", "required": true }
      },
      "invariants": [
        { "name": "token_long", "expression": ".pet_id | length > 2" }
      ],
      "golden": { "response": "create_pet.json" }
    },
    {
      "id": "get_pet",
      "self_export": "pet_id",
      "peer_path": "/pet/{id}",
      "peer_method": "GET"
    }
  ]
}
EOF

# 公共 env
export OUTPUT_DIR="$PROJ/generated"
export CHIMERIC_FILE="$PROJ/chimeric.json"
export STRUCT_FILE="$PROJ/struct.json"

echo "==============================================="
echo "  chimeric e2e tests"
echo "==============================================="
echo

# ===================== Step 1: spec.sh IR 规范化 =====================
echo "[step 1] chimeric_spec.sh IR normalization"
bash "$ROOT_DIR/generators/chimeric_spec.sh" 2>&1 | head -8

IR="$OUTPUT_DIR/.chimeric/petstore/ir.json"
SPEC="$OUTPUT_DIR/.chimeric/petstore/peer-spec.json"

check "peer-spec.json cached"        test -f "$SPEC"
check "ir.json emitted"              test -f "$IR"
check "ir is valid JSON"             jq empty "$IR"
check "ir has 3 endpoints"           test "$(jq '.endpoints | length' "$IR")" = "3"
check "POST /pet id normalized"      test "$(jq -r '.endpoints[] | select(.method == "POST" and .path == "/pet") | .id' "$IR")" = "POST_/pet"
check "type_map.name = string"       test "$(jq -r '.endpoints[] | select(.method == "POST" and .path == "/pet") | .type_map.name' "$IR")" = "string"
check "POST /pet required has id"    bash -c "jq -e '.endpoints[] | select(.method == \"POST\" and .path == \"/pet\") | .required | index(\"id\")' \"$IR\""
check "DELETE /pet/{id} present"     bash -c "jq -e '.endpoints[] | select(.method == \"DELETE\" and .path == \"/pet/{id}\")' \"$IR\""
echo

# ===================== Step 2: adapter.sh 代码渲染 =====================
echo "[step 2] chimeric_adapter.sh render"
bash "$ROOT_DIR/generators/chimeric_adapter.sh" 2>&1 | head -8

MANIFEST="$OUTPUT_DIR/.chimeric/petstore/adapter-manifest.json"
ADAPTER_PY="$OUTPUT_DIR/python/chimeric/petstore/create_pet.py"

check "adapter-manifest.json exists" test -f "$MANIFEST"
check "manifest is valid JSON"        jq empty "$MANIFEST"
check "manifest lists >=1 file"       bash -c "jq -e '.files | length >= 1' \"$MANIFEST\""
check "python adapter emitted"        test -f "$ADAPTER_PY"
check "python adapter parses (ast)"   python3 -c "import ast; ast.parse(open('$ADAPTER_PY').read())"
echo

# ===================== Step 3: verify.sh 全 pass 路径 =====================
echo "[step 3] chimeric_verify.sh — all-pass path"
# 准备 golden fixture + matching capture
mkdir -p "$OUTPUT_DIR/.chimeric/petstore/fixtures" "$OUTPUT_DIR/.chimeric/petstore/captures"
printf '{"pet_id":"abc123","pet_name":"rex"}' > "$OUTPUT_DIR/.chimeric/petstore/fixtures/create_pet.json"
cp "$OUTPUT_DIR/.chimeric/petstore/fixtures/create_pet.json" "$OUTPUT_DIR/.chimeric/petstore/captures/create_pet.json"

VR="$OUTPUT_DIR/.chimeric/petstore/verify-results.json"
# 只验 create_pet（get_pet 无 mapping，contract 必失败，单独验）
check_rc "verify create_pet all-pass exits 0" 0 \
    bash "$ROOT_DIR/generators/chimeric_verify.sh" --integration create_pet
check "verify-results.json valid"   jq empty "$VR"
check "contract pass"               bash -c "jq -e '.results[] | select(.integration_point==\"create_pet\") | .modes.contract.status == \"pass\"' \"$VR\""
check "golden pass"                 bash -c "jq -e '.results[] | select(.integration_point==\"create_pet\") | .modes.golden.status == \"pass\"' \"$VR\""
check "invariants pass"             bash -c "jq -e '.results[] | select(.integration_point==\"create_pet\") | .modes.invariants.status == \"pass\"' \"$VR\""
# get_pet 无 field_mapping → 全量 verify 的 contract 必失败（非零退出）
check_rc "full verify exits non-zero (get_pet unmapped)" 11 \
    bash "$ROOT_DIR/generators/chimeric_verify.sh" --mode contract
echo

# ===================== Step 4: verify.sh 失败路径 =====================
echo "[step 4] chimeric_verify.sh — failure paths"
# 4a. contract 单 mode 失败：field_mapping 类型非法
ORIG="$(cat chimeric.json)"
jq '.integration_points[0].field_mapping.pet_id.type = "int42"' chimeric.json > chimeric.json.bad
mv chimeric.json.bad chimeric.json
check_rc "contract bad-type exits 11" 11 bash "$ROOT_DIR/generators/chimeric_verify.sh" --mode contract --integration create_pet
# 还原
echo "$ORIG" > chimeric.json

# 4b. golden 失败：mutate capture 使其与 fixture 分叉
printf '{"pet_id":"abc123","pet_name":"CHANGED"}' > "$OUTPUT_DIR/.chimeric/petstore/captures/create_pet.json"
check_rc "golden drift exits 13" 13 bash "$ROOT_DIR/generators/chimeric_verify.sh" --mode golden --integration create_pet
check "golden diff non-empty"       bash -c "jq -e '.results[] | select(.integration_point==\"create_pet\") | .modes.golden.diff | length > 0' \"$VR\""

# 4c. invariant 失败：pet_id 太短
printf '{"pet_id":"a","pet_name":"rex"}' > "$OUTPUT_DIR/.chimeric/petstore/captures/create_pet.json"
check_rc "invariant fail exits 14" 14 bash "$ROOT_DIR/generators/chimeric_verify.sh" --mode invariants --integration create_pet
check "invariant error named"       bash -c "jq -e '.results[] | select(.integration_point==\"create_pet\") | .modes.invariants.errors[0].message | startswith(\"token_long\")' \"$VR\""
echo

# ===================== Step 5: CLI surface (bootstrap.sh) =====================
echo "[step 5] bootstrap.sh --chimeric CLI surface"
check_rc "--chimeric verify (create_pet contract) exits 0" 0 \
    bash "$ROOT_DIR/bootstrap.sh" --chimeric verify --mode contract --integration create_pet
check_rc "--chimeric-status exits 0" 0 \
    bash "$ROOT_DIR/bootstrap.sh" --chimeric-status

echo
echo "  passed: $pass"
echo "  failed: $fail"
echo "==============================================="
exit $EXIT_CODE
