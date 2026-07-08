#!/opt/homebrew/bin/bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT
mkdir -p "$TMP_DIR/generated/.ai/slices" "$TMP_DIR/generated/.ai/work_records"
cat > "$TMP_DIR/slice.json" <<'JSON'
{"todo":{"id":"demo_task","task":"Implement demo"},"component":{"name":"Demo"}}
JSON
bash "$ROOT_DIR/generators/adapters/generic.sh" "$TMP_DIR/slice.json" "$TMP_DIR/generated/.ai/work_records/demo_task.json" >/dev/null
out=$(bash "$ROOT_DIR/generators/work_record_collect.sh" --dir "$TMP_DIR/generated/.ai/work_records" --json)
echo "$out" | jq -e '.summary.records == 1 and .work_record_hash' >/dev/null
echo "  [OK]   agent eval harness smoke"
