#!/usr/bin/env bash
set -euo pipefail
DIR=".simple_model/waivers"; FINDINGS=""; JSON_OUT=0
while [[ $# -gt 0 ]]; do case "$1" in --dir) DIR="$2"; shift 2;; --findings) FINDINGS="$2"; shift 2;; --json) JSON_OUT=1; shift;; *) shift;; esac; done
mkdir -p "$DIR"
today=$(date +%Y-%m-%d)
waivers=$(find "$DIR" -type f -name '*.json' 2>/dev/null | sort | while read -r f; do jq -c --arg file "$f" '. + {_file:$file}' "$f"; done | jq -s '.')
expired=$(jq --arg today "$today" '[.[] | select((.expires // "0000-00-00") < $today)]' <<<"$waivers")
findings_json="[]"; [[ -n "$FINDINGS" && -f "$FINDINGS" ]] && findings_json=$(jq '.findings // .' "$FINDINGS")
out=$(jq -n --argjson waivers "$waivers" --argjson expired "$expired" --argjson findings "$findings_json" '{ok:(($expired|length)==0), waivers:$waivers, expired:$expired, findings:$findings, summary:{waivers:($waivers|length), expired:($expired|length), findings:($findings|length)}}')
[[ "$JSON_OUT" == "1" ]] && echo "$out" || jq -r '.'
[[ $(jq '.summary.expired' <<<"$out") -eq 0 ]] || exit 1
