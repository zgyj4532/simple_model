#!/usr/bin/env bash
set -euo pipefail
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="."; STRUCT="${STRUCT_FILE:-./struct.json}"; JSON_OUT=0; STRICT=0
while [[ $# -gt 0 ]]; do case "$1" in --root) ROOT="$2"; shift 2;; --struct|-s) STRUCT="$2"; shift 2;; --json) JSON_OUT=1; shift;; --strict) STRICT=1; shift;; *) shift;; esac; done
scan=$(bash "$SELF_DIR/import_graph_scan.sh" --root "$ROOT" --struct "$STRUCT" --json || true)
warnings=$(jq '.summary.warnings // 0' <<<"$scan")
ok=true; [[ "$STRICT" == "1" && $warnings -gt 0 ]] && ok=false
out=$(jq -n --argjson scan "$scan" --argjson ok "$ok" '{ok:$ok, gate:"dependency_drift", scan:$scan, warnings:($scan.summary.warnings//0), errors:0}')
[[ "$JSON_OUT" == "1" ]] && echo "$out" || jq -r '.'
[[ "$ok" == "true" ]] || exit 1
