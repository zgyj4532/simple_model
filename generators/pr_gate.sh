#!/usr/bin/env bash
set -euo pipefail
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="."; STRUCT="${STRUCT_FILE:-./struct.json}"; FILES=""; JSON_OUT=0; MARKDOWN_OUT=""
while [[ $# -gt 0 ]]; do case "$1" in --root) ROOT="$2"; shift 2;; --struct|-s) STRUCT="$2"; shift 2;; --files) FILES="$2"; shift 2;; --json) JSON_OUT=1; shift;; --markdown) MARKDOWN_OUT="$2"; shift 2;; *) shift;; esac; done
impact=$(bash "$SELF_DIR/pr_impact.sh" --root "$ROOT" --struct "$STRUCT" --files "$FILES" --json)
iface=$(bash "$SELF_DIR/interface_drift_gate.sh" --root "$ROOT" --struct "$STRUCT" --json || true)
dep=$(bash "$SELF_DIR/dependency_drift_gate.sh" --root "$ROOT" --struct "$STRUCT" --json || true)
risk=$(echo "$impact" | bash "$SELF_DIR/risk_score.sh" --json)
tests=$(echo "$impact" | bash "$SELF_DIR/test_select.sh" --json)
review=$(echo "$impact" | bash "$SELF_DIR/review_route.sh" --json)
ok=$(jq -n --argjson i "$iface" --argjson d "$dep" '($i.ok and $d.ok)')
out=$(jq -n --argjson ok "$ok" --argjson impact "$impact" --argjson interface "$iface" --argjson dependency "$dep" --argjson risk "$risk" --argjson tests "$tests" --argjson review "$review" '{ok:$ok, impact:$impact, gates:{interface:$interface, dependency:$dependency}, risk:$risk.risk, tests:$tests.commands, review:$review}')
if [[ -n "$MARKDOWN_OUT" ]]; then
    mkdir -p "$(dirname "$MARKDOWN_OUT")"
    echo "$out" | bash "$SELF_DIR/pr_comment.sh" > "$MARKDOWN_OUT"
fi
[[ "$JSON_OUT" == "1" ]] && echo "$out" || jq -r '.'
[[ "$ok" == "true" ]] || exit 1
