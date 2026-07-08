#!/usr/bin/env bash
set -euo pipefail

usage() {
    cat <<'USAGE'
simple_model_pi.sh <command> [args]

Commands:
  validate                         Run validate/check/lint/drift summaries.
  full-check                       Run validate/check/lint/drift and tests/test_*.sh.
  ingest <repo-root> [out]          Draft struct.json from an existing repo.
  audit <repo-root>                 Audit unmanaged source files.
  interfaces <repo-root>            Scan public interfaces against struct.json.
  facts <repo-root>                 Emit generated/.ai/code_facts.json.
  pr-gate <repo-root> [files]        Run PR impact, drift gates, risk, tests, review route.
  dashboard [out]                   Generate static dashboard HTML.
  resolve                           Resolve multi-file struct includes.
USAGE
}

find_root() {
    local d="$PWD"
    while [[ "$d" != "/" ]]; do
        if [[ -x "$d/bootstrap.sh" && -d "$d/generators" ]]; then
            printf '%s\n' "$d"
            return 0
        fi
        d="$(dirname "$d")"
    done

    d="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
    if [[ -x "$d/bootstrap.sh" && -d "$d/generators" ]]; then
        printf '%s\n' "$d"
        return 0
    fi

    echo "[FAIL] cannot locate simple_model root with bootstrap.sh and generators/" >&2
    return 2
}

ROOT="$(find_root)"
cd "$ROOT"

cmd="${1:-}"
[[ -n "$cmd" ]] || { usage; exit 64; }
shift || true

case "$cmd" in
    validate)
        ./bootstrap.sh --validate
        ./bootstrap.sh --check-all
        ./bootstrap.sh --lint --json | jq '.summary'
        ./bootstrap.sh --drift --json | jq '.summary'
        ;;
    full-check)
        ./bootstrap.sh --validate
        ./bootstrap.sh --check-all
        ./bootstrap.sh --lint --json | jq '.summary'
        ./bootstrap.sh --drift --json | jq '.summary'
        for t in tests/test_*.sh; do bash "$t" || exit 1; done
        ;;
    ingest)
        repo="${1:-}"; out="${2:-generated/struct.ingested.json}"
        [[ -n "$repo" ]] || { usage; exit 64; }
        generators/ingest_repo.sh --root "$repo" --output "$out" --json
        ;;
    audit)
        repo="${1:-}"
        [[ -n "$repo" ]] || { usage; exit 64; }
        ./bootstrap.sh --adoption-audit "$repo" --json
        ;;
    interfaces)
        repo="${1:-}"
        [[ -n "$repo" ]] || { usage; exit 64; }
        ./bootstrap.sh --interface-scan "$repo" --json
        ;;
    facts)
        repo="${1:-}"
        [[ -n "$repo" ]] || { usage; exit 64; }
        generators/code_facts.sh --root "$repo" --struct struct.json --json
        ;;
    pr-gate)
        repo="${1:-}"; files="${2:-}"
        [[ -n "$repo" ]] || { usage; exit 64; }
        if [[ -n "$files" ]]; then
            generators/pr_gate.sh --root "$repo" --struct struct.json --files "$files" --json
        else
            ./bootstrap.sh --pr-gate "$repo" --json
        fi
        ;;
    dashboard)
        out="${1:-generated/dashboard.html}"
        generators/dashboard.sh "$out"
        ;;
    resolve)
        ./bootstrap.sh --resolve --json
        ;;
    -h|--help|help)
        usage
        ;;
    *)
        echo "[FAIL] unknown command: $cmd" >&2
        usage
        exit 64
        ;;
esac
