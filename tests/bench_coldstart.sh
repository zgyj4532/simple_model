#!/usr/bin/env bash
# tests/bench_coldstart.sh — coarse cold-start benchmark for validate path
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RUNS="${RUNS:-5}"
THRESHOLD_MS="${THRESHOLD_MS:-1000}"
JSON_OUT=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        --json) JSON_OUT=1; shift ;;
        --runs) RUNS="${2:-}"; shift 2 ;;
        --threshold-ms) THRESHOLD_MS="${2:-}"; shift 2 ;;
        -h|--help)
            echo "Usage: bash tests/bench_coldstart.sh [--json] [--runs N] [--threshold-ms N]"
            exit 0
            ;;
        *) echo "[FAIL] unknown arg: $1" >&2; exit 64 ;;
    esac
done

now_us() {
    if [[ -n "${EPOCHREALTIME:-}" ]]; then
        printf '%s\n' "${EPOCHREALTIME/./}"
    else
        date +%s000000
    fi
}

total=0
max=0
for _ in $(seq 1 "$RUNS"); do
    start=$(now_us)
    (cd "$ROOT_DIR" && ./bootstrap.sh --validate >/dev/null)
    end=$(now_us)
    elapsed_ms=$(( (10#$end - 10#$start) / 1000 ))
    total=$((total + elapsed_ms))
    [[ "$elapsed_ms" -gt "$max" ]] && max="$elapsed_ms"
done

avg=$((total / RUNS))
ok=true
[[ "$avg" -le "$THRESHOLD_MS" ]] || ok=false

if [[ "$JSON_OUT" == "1" ]]; then
    jq -n \
        --argjson runs "$RUNS" \
        --argjson avg "$avg" \
        --argjson max "$max" \
        --argjson threshold "$THRESHOLD_MS" \
        --argjson ok "$ok" \
        '{schema_version:"1.0", runs:$runs, avg_ms:$avg, max_ms:$max, threshold_ms:$threshold, ok:$ok}'
else
    printf 'runs=%d avg_ms=%d max_ms=%d threshold_ms=%d\n' "$RUNS" "$avg" "$max" "$THRESHOLD_MS"
fi

[[ "$ok" == "true" ]]
