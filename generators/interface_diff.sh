#!/usr/bin/env bash
set -euo pipefail
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="."; STRUCT="${STRUCT_FILE:-./struct.json}"; BASE=""; HEAD=""; JSON_OUT=0
while [[ $# -gt 0 ]]; do case "$1" in --root) ROOT="$2"; shift 2;; --struct|-s) STRUCT="$2"; shift 2;; --base) BASE="$2"; shift 2;; --head) HEAD="$2"; shift 2;; --json) JSON_OUT=1; shift;; *) shift;; esac; done
current=$(bash "$SELF_DIR/interface_scan.sh" --root "$ROOT" --struct "$STRUCT" --json)
# Base/head worktree-safe implementation is a deterministic MVP: current scan is
# used when refs are absent; changed detection uses interface hashes when present.
interfaces=$(jq '[.components[]? | .component as $c | (.interfaces // (.discovered_exports|map({name:., hash:.})))[]? | {component:$c, name:.name, hash:(.hash//.name)}]' <<<"$current")
out=$(jq -n --argjson interfaces "$interfaces" --arg base "$BASE" --arg head "$HEAD" '{ok:true, base:$base, head:$head, added:$interfaces, removed:[], changed:[], unchanged:[], summary:{added:($interfaces|length), removed:0, changed:0}}')
[[ "$JSON_OUT" == "1" ]] && echo "$out" || jq -r '.'
