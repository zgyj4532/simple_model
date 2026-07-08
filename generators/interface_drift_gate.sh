#!/usr/bin/env bash
set -euo pipefail
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="."; STRUCT="${STRUCT_FILE:-./struct.json}"; JSON_OUT=0
while [[ $# -gt 0 ]]; do case "$1" in --root) ROOT="$2"; shift 2;; --struct|-s) STRUCT="$2"; shift 2;; --json) JSON_OUT=1; shift;; *) shift;; esac; done
scan=$(bash "$SELF_DIR/interface_scan.sh" --root "$ROOT" --struct "$STRUCT" --json || true)
missing=$(jq '.summary.missing_exports // 0' <<<"$scan")
paths=$(jq '.summary.missing_paths // 0' <<<"$scan")
ok=true; [[ $missing -gt 0 || $paths -gt 0 ]] && ok=false
out=$(jq -n --argjson scan "$scan" --argjson ok "$ok" '{ok:$ok, gate:"interface_drift", scan:$scan, errors:(($scan.summary.missing_exports//0)+($scan.summary.missing_paths//0)), warnings:($scan.summary.undeclared_exports//0)}')
[[ "$JSON_OUT" == "1" ]] && echo "$out" || jq -r '.'
[[ "$ok" == "true" ]] || exit 1
