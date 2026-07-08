#!/usr/bin/env bash
# tools/depcheck.sh — dependency audit for the bash+jq runtime
set -euo pipefail

JSON_OUT=0
while [[ $# -gt 0 ]]; do
    case "$1" in
        --json) JSON_OUT=1; shift ;;
        -h|--help)
            echo "Usage: bash tools/depcheck.sh [--json]"
            exit 0
            ;;
        *) echo "[FAIL] unknown arg: $1" >&2; exit 64 ;;
    esac
done

required=(bash jq git)
optional=(cargo ajv curl shasum sha256sum)
forbidden_runtime=(python python3 node npm)

has_cmd() { command -v "$1" >/dev/null 2>&1; }

missing=()
for c in "${required[@]}"; do
    has_cmd "$c" || missing+=("$c")
done

forbidden_present=()
for c in "${forbidden_runtime[@]}"; do
    has_cmd "$c" && forbidden_present+=("$c")
done

if [[ "$JSON_OUT" == "1" ]]; then
    jq -n \
        --argjson ok "$([[ ${#missing[@]} -eq 0 ]] && echo true || echo false)" \
        --arg required "$(IFS=,; echo "${required[*]}")" \
        --arg missing "$(IFS=,; echo "${missing[*]:-}")" \
        --arg optional "$(IFS=,; echo "${optional[*]}")" \
        --arg forbidden "$(IFS=,; echo "${forbidden_present[*]:-}")" \
        '{
          schema_version: "1.0",
          ok: $ok,
          required: ($required | split(",") | map(select(length > 0))),
          missing: ($missing | split(",") | map(select(length > 0))),
          optional: ($optional | split(",") | map(select(length > 0))),
          forbidden_runtime_present: ($forbidden | split(",") | map(select(length > 0))),
          note: "python/node may exist on the host, but simple_model runtime checks require only bash+jq plus git for worktree dispatch"
        }'
else
    printf 'required: %s\n' "${required[*]}"
    if [[ ${#missing[@]} -eq 0 ]]; then
        printf '[OK] required dependencies present\n'
    else
        printf '[FAIL] missing: %s\n' "${missing[*]}" >&2
    fi
    [[ ${#forbidden_present[@]} -gt 0 ]] && printf '[INFO] host also has: %s\n' "${forbidden_present[*]}"
fi

[[ ${#missing[@]} -eq 0 ]]
