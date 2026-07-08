#!/usr/bin/env bash
set -euo pipefail
IMPACT=""; JSON_OUT=0; EXECUTE=0; TIMEOUT=30
while [[ $# -gt 0 ]]; do case "$1" in --impact) IMPACT="$2"; shift 2;; --json) JSON_OUT=1; shift;; --execute) EXECUTE=1; shift;; --timeout) TIMEOUT="$2"; shift 2;; *) shift;; esac; done
if [[ -n "$IMPACT" && -f "$IMPACT" ]]; then data=$(cat "$IMPACT"); else data=$(cat); fi
cmds=$(jq '[.impacted_components[]?.checks | to_entries[]? | .value] | unique' <<<"$data")
results="[]"
if [[ "$EXECUTE" == "1" ]]; then
    results=$(jq -r '.[]' <<<"$cmds" | while read -r cmd; do
        start=$(date +%s)
        rc=0
        if command -v timeout >/dev/null 2>&1; then
            timeout "$TIMEOUT" bash -lc "$cmd" >/tmp/simple_model_test_select.out 2>/tmp/simple_model_test_select.err || rc=$?
        else
            bash -lc "$cmd" >/tmp/simple_model_test_select.out 2>/tmp/simple_model_test_select.err || rc=$?
        fi
        end=$(date +%s)
        jq -cn --arg cmd "$cmd" --argjson rc "$rc" --argjson duration "$((end-start))" '{command:$cmd, exit_code:$rc, duration_seconds:$duration}'
    done | jq -s '.')
fi
out=$(jq -n --argjson commands "$cmds" --argjson results "$results" --argjson execute "$EXECUTE" '{ok:($results|map(select(.exit_code != 0))|length == 0), mode:(if $execute==1 then "execute" else "dry-run" end), commands:$commands, results:$results, summary:{commands:($commands|length), failed:($results|map(select(.exit_code != 0))|length)}}')
[[ "$JSON_OUT" == "1" ]] && echo "$out" || jq -r '.'
