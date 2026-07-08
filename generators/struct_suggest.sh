#!/usr/bin/env bash
set -euo pipefail
FINDINGS=""; JSON_OUT=0; APPLY=0
while [[ $# -gt 0 ]]; do case "$1" in --findings) FINDINGS="$2"; shift 2;; --json) JSON_OUT=1; shift;; --apply) APPLY=1; shift;; *) shift;; esac; done
data="${FINDINGS:+$(cat "$FINDINGS")}"
[[ -z "${data:-}" ]] && data="$(cat 2>/dev/null || echo '{"findings":[]}')"
patch=$(jq '[.findings[]? | if .type=="undeclared_exports" then {op:"add", path:("/modules/0/components/0/exports/-"), value:(.symbols[0] // "")} elif .type=="undeclared_import" then {op:"add", path:"/modules/0/components/0/imports/-", value:(.target // "")} else empty end]' <<<"$data")
out=$(jq -n --argjson patch "$patch" '{ok:true, patch:$patch, summary:{ops:($patch|length)}}')
[[ "$APPLY" == "1" ]] && { echo "[FAIL] --apply intentionally requires a future safe patch engine" >&2; exit 64; }
[[ "$JSON_OUT" == "1" ]] && echo "$out" || jq -r '.'
