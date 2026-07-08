#!/usr/bin/env bash
set -euo pipefail
IMPACT=""; JSON_OUT=0
while [[ $# -gt 0 ]]; do case "$1" in --impact) IMPACT="$2"; shift 2;; --json) JSON_OUT=1; shift;; *) shift;; esac; done
if [[ -n "$IMPACT" && -f "$IMPACT" ]]; then data=$(cat "$IMPACT"); else data=$(cat); fi
batches=$(jq '[.impacted_components[]?] | to_entries | map({batch:(.key/3|floor + 1), component:.value.component, owners:.value.owners, risk:.value.risk, rationale:"dependency-safe input order"})' <<<"$data")
out=$(jq -n --argjson batches "$batches" '{ok:true, batches:$batches, summary:{batches:([$batches[].batch]|unique|length), components:($batches|length)}}')
[[ "$JSON_OUT" == "1" ]] && echo "$out" || jq -r '.'
