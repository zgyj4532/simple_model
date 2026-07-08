#!/usr/bin/env bash
# generators/orchestrate_dispatch.sh — worktree-isolated wave dispatch wrapper
set -euo pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SELF_DIR/_lib.sh"

WAVE=1
PLAN_ONLY=0
TODO_ID=""
ADAPTER="${AGENT_ADAPTER:-generic}"
OUT_DIR="${OUTPUT_DIR:-./generated}/.ai/dispatch"

usage() {
    cat <<'EOF'
orchestrate_dispatch.sh — plan or create isolated leaf-agent worktrees

Usage:
  bash generators/orchestrate_dispatch.sh [--plan] [--wave N] [--todo ID] [--adapter NAME]

Options:
  --plan       Print the dispatch plan; do not create worktrees
  --wave N     Dispatch one wave from generated/.ai/dev_queue.json
  --todo ID    Restrict the plan/dispatch manifest to one todo in the wave
  --adapter N  Leaf adapter name: generic, claude, codex, cursor
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --plan|--dry-run) PLAN_ONLY=1; shift ;;
        --wave) WAVE="${2:-}"; shift 2 ;;
        --todo) TODO_ID="${2:-}"; shift 2 ;;
        --adapter) ADAPTER="${2:-}"; shift 2 ;;
        -h|--help) usage; exit 0 ;;
        *) echo "[FAIL] unknown arg: $1" >&2; usage; exit 64 ;;
    esac
done

case "$ADAPTER" in
    generic|claude|codex|cursor) ;;
    *) echo "[FAIL] unsupported adapter: $ADAPTER" >&2; exit 64 ;;
esac

QUEUE="${OUTPUT_DIR:-./generated}/.ai/dev_queue.json"
[[ -f "$QUEUE" ]] || { echo "[FAIL] missing $QUEUE; run ./bootstrap.sh --target queue" >&2; exit 2; }
jq empty "$QUEUE" >/dev/null

WAVE_JSON=$(jq -c --argjson wave "$WAVE" '.waves[] | select(.wave == $wave)' "$QUEUE")
[[ -n "$WAVE_JSON" && "$WAVE_JSON" != "null" ]] || { echo "[FAIL] wave not found: $WAVE" >&2; exit 2; }

PLAN_JSON=$(jq -c \
    --arg adapter "$ADAPTER" \
    --arg todo "$TODO_ID" \
    --arg out "$OUT_DIR" '
    .todos
    | map(select(($todo == "") or (.id == $todo)))
    | {
        schema_version: "1.0",
        wave: (.[]?.wave // '"$WAVE"'),
        adapter: $adapter,
        dispatch_dir: $out,
        todos: map({
            id, task, priority, status, component, module, blocks,
            branch: ("agent/wave-'"$WAVE"'/" + .id),
            worktree_path: ("../wt-wave-'"$WAVE"'-" + .id),
            summary_path: ($out + "/summaries/" + .id + ".json")
        })
      }
    ' <<<"$WAVE_JSON")

if [[ "$(jq '.todos | length' <<<"$PLAN_JSON")" -eq 0 ]]; then
    echo "[FAIL] no todo selected for wave=$WAVE todo=${TODO_ID:-<all>}" >&2
    exit 2
fi

if [[ "$PLAN_ONLY" == "1" ]]; then
    jq . <<<"$PLAN_JSON"
    exit 0
fi

mkdir -p "$OUT_DIR/summaries"
jq . <<<"$PLAN_JSON" > "$OUT_DIR/manifest.json"

# Reuse the existing git worktree implementation for the actual filesystem
# isolation; this wrapper adds the stable manifest consumed by collectors.
bash "$SELF_DIR/git_dispatch.sh" --wave "$WAVE"

say "$OUT_DIR/manifest.json"
