#!/usr/bin/env bash
set -euo pipefail
DIR="${OUTPUT_DIR:-./generated}/.ai/work_records"; JSON_OUT=0
while [[ $# -gt 0 ]]; do case "$1" in --dir) DIR="$2"; shift 2;; --json) JSON_OUT=1; shift;; *) shift;; esac; done
mkdir -p "$DIR"
records=$(find "$DIR" -type f -name '*.json' 2>/dev/null | sort | while read -r f; do jq -c --arg file "$f" '. + {_file:$file}' "$f"; done | jq -s '.')
invalid=$(jq '[.[] | select((.schema_version//"")=="" or (.todo_id//"")=="" or (.status//"")=="" or ((.files_changed//[])|type)!="array")] | length' <<<"$records")
hash=$(jq -S -c . <<<"$records" | sha256sum | awk '{print $1}')
out=$(jq -n --arg hash "$hash" --argjson records "$records" --argjson invalid "$invalid" '{ok:($invalid==0), work_record_hash:$hash, summary:{records:($records|length), invalid:$invalid}, records:$records}')
[[ "$JSON_OUT" == "1" ]] && echo "$out" || jq -r '.summary' <<<"$out"
[[ $invalid -eq 0 ]] || exit 1
