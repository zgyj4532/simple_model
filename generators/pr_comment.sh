#!/usr/bin/env bash
set -euo pipefail
REPORT="${1:-}"
data="${REPORT:+$(cat "$REPORT")}"
[[ -z "${data:-}" ]] && data="$(cat)"
jq -r '
  "<!-- simple_model:pr-gate -->\n" +
  "## simple_model PR Gate\n\n" +
  "- verdict: `" + ((.ok|tostring) // "false") + "`\n" +
  "- impacted components: `" + ((.impact.summary.components // 0)|tostring) + "`\n" +
  "- risk: `" + ((.risk.level // "unknown")|tostring) + "`\n" +
  "- selected tests: `" + ((.tests|length // 0)|tostring) + "`\n"
' <<<"$data"
