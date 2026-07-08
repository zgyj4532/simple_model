#!/usr/bin/env bash
set -euo pipefail
IMPACT=""; JSON_OUT=0
while [[ $# -gt 0 ]]; do case "$1" in --impact) IMPACT="$2"; shift 2;; --json) JSON_OUT=1; shift;; *) shift;; esac; done
if [[ -n "$IMPACT" && -f "$IMPACT" ]]; then data=$(cat "$IMPACT"); else data=$(cat); fi
routes=$(jq '[.impacted_components[]? as $c | ($c.owners[]? // empty) | {reviewer:., component:$c.component, reason:"component_owner"}]' <<<"$data")
reviewers=$(jq '[.[].reviewer] | unique' <<<"$routes")
out=$(jq -n --argjson reviewers "$reviewers" --argjson routes "$routes" '{ok:true, reviewers:$reviewers, routes:$routes, required_approvals:(if ($reviewers|length)>1 then 2 elif ($reviewers|length)>0 then 1 else 0 end)}')
[[ "$JSON_OUT" == "1" ]] && echo "$out" || jq -r '.'
