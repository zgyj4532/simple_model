#!/usr/bin/env bash
set -euo pipefail
DIFF=""; JSON_OUT=0
while [[ $# -gt 0 ]]; do case "$1" in --diff) DIFF="$2"; shift 2;; --json) JSON_OUT=1; shift;; *) shift;; esac; done
data="${DIFF:+$(cat "$DIFF")}"; [[ -z "${data:-}" ]] && data="$(cat 2>/dev/null || echo '{"added":[],"removed":[],"changed":[]}')"
out=$(jq -n --argjson d "$data" '{ok:true, breaking:($d.removed + $d.changed), additive:$d.added, internal:[], summary:{breaking:(($d.removed|length)+($d.changed|length)), additive:($d.added|length)}}')
[[ "$JSON_OUT" == "1" ]] && echo "$out" || jq -r '.'
