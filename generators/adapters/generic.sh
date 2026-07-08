#!/usr/bin/env bash
# Generic leaf adapter. It writes a bounded summary contract without invoking an LLM.
set -euo pipefail

SLICE="${1:-}"
OUT="${2:-summary.json}"
[[ -n "$SLICE" && -f "$SLICE" ]] || { echo "[FAIL] usage: generic.sh <slice.json> [summary.json]" >&2; exit 64; }

todo_id=$(jq -r '.todo.id // .todo_id // .component.name // "unknown_todo"' "$SLICE")
summary=$(jq -r '.todo.task // .task // .component.description // "No task text in slice."' "$SLICE")

jq -n --arg id "$todo_id" --arg summary "$summary" '{
  schema_version: "1.0",
  todo_id: ($id | gsub("[^a-zA-Z0-9_]"; "_") | ascii_downcase),
  agent: "generic",
  status: "blocked",
  summary: $summary,
  files_changed: [],
  commands: [],
  tests: [],
  diff: {files_changed: []},
  blockers: ["generic adapter is a deterministic placeholder; set AGENT_CMD to invoke a real leaf worker"],
  next_steps: []
}' > "$OUT"

printf '%s\n' "$OUT"
