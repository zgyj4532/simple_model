#!/usr/bin/env bash
# generators/orchestrate_collect.sh — collect bounded leaf-agent summaries
set -euo pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SELF_DIR/_lib.sh"

DISPATCH_DIR="${OUTPUT_DIR:-./generated}/.ai/dispatch"
OUT="${OUTPUT_DIR:-./generated}/.ai/agent_summaries.json"
MAX_CHARS=4000

usage() {
    cat <<'EOF'
orchestrate_collect.sh — collect leaf-agent summaries

Usage:
  bash generators/orchestrate_collect.sh [--dispatch-dir DIR] [--out FILE] [--max-chars N]
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --dispatch-dir) DISPATCH_DIR="${2:-}"; shift 2 ;;
        --out) OUT="${2:-}"; shift 2 ;;
        --max-chars) MAX_CHARS="${2:-}"; shift 2 ;;
        -h|--help) usage; exit 0 ;;
        *) echo "[FAIL] unknown arg: $1" >&2; usage; exit 64 ;;
    esac
done

SUMMARY_DIR="$DISPATCH_DIR/summaries"
mkdir -p "$(dirname "$OUT")"

if [[ ! -d "$SUMMARY_DIR" ]]; then
    jq -n --arg dir "$SUMMARY_DIR" '{
      schema_version: "1.0",
      generated_at: (now | todateiso8601),
      summary_dir: $dir,
      count: 0,
      summaries: []
    }' > "$OUT"
    say "$OUT"
    exit 0
fi

TMP=$(mktemp)
trap 'rm -f "$TMP"' EXIT

find "$SUMMARY_DIR" -name '*.json' -type f | sort | while IFS= read -r f; do
    if jq -e --argjson max "$MAX_CHARS" '
        .schema_version == "1.0"
        and (.todo_id | test("^[a-z][a-z0-9_]*$"))
        and ((.summary // "") | length <= $max)
        and ((.blockers // []) | type == "array")
    ' "$f" >/dev/null 2>&1; then
        jq -c . "$f" >> "$TMP"
    else
        jq -c -n --arg file "$f" '{
          schema_version: "1.0",
          todo_id: ($file | split("/")[-1] | sub("\\.json$"; "")),
          agent: "collector",
          status: "failed",
          summary: "summary file failed schema or size validation",
          diff: {files_changed: []},
          blockers: [$file]
        }' >> "$TMP"
    fi
done

jq -s --arg dir "$SUMMARY_DIR" '{
  schema_version: "1.0",
  generated_at: (now | todateiso8601),
  summary_dir: $dir,
  count: length,
  summaries: .
}' "$TMP" > "$OUT"

say "$OUT"
