#!/usr/bin/env bash
set -euo pipefail
IMPACT=""; JSON_OUT=0
while [[ $# -gt 0 ]]; do case "$1" in --impact) IMPACT="$2"; shift 2;; --json) JSON_OUT=1; shift;; *) shift;; esac; done
if [[ -n "$IMPACT" && -f "$IMPACT" ]]; then data=$(cat "$IMPACT"); else data=$(cat); fi
factors=$(jq '[.impacted_components[]? | {component:.component, factor:"component_risk", risk:(.risk//"medium"), points:(if .risk=="critical" then 40 elif .risk=="high" then 25 elif .risk=="medium" then 10 else 3 end)}]' <<<"$data")
score=$(jq '[.[].points] | add // 0' <<<"$factors")
fanout=$(jq '.impacted_components|length' <<<"$data")
score=$((score + fanout * 5))
level=low; [[ $score -ge 20 ]] && level=medium; [[ $score -ge 50 ]] && level=high; [[ $score -ge 90 ]] && level=critical
out=$(jq -n --arg level "$level" --argjson score "$score" --argjson components "$fanout" --argjson factors "$factors" '{ok:true, risk:{level:$level, score:$score, factors:$factors, fanout:$components}}')
[[ "$JSON_OUT" == "1" ]] && echo "$out" || jq -r '.'
