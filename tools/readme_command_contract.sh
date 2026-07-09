#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
README="$ROOT/README.md"
MODE="check"

usage() {
    cat <<'USAGE'
readme_command_contract.sh [--check|--list] [--readme <path>]

Validates README command blocks marked with:
  <!-- simple_model:test-command:start <name> -->
  <!-- simple_model:test-command:end -->
USAGE
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --check) MODE="check"; shift ;;
        --list) MODE="list"; shift ;;
        --readme)
            [[ $# -ge 2 ]] || { echo "--readme requires a path" >&2; exit 64; }
            README="$2"
            shift 2
            ;;
        -h|--help) usage; exit 0 ;;
        *) echo "unknown arg: $1" >&2; usage; exit 64 ;;
    esac
done

[[ -f "$README" ]] || { echo "[FAIL] README not found: $README" >&2; exit 1; }

extract_commands() {
    awk '
      /simple_model:test-command:start/ {in_block=1; next}
      /simple_model:test-command:end/ {in_block=0; next}
      in_block && $0 !~ /^```/ && $0 !~ /^#/ && $0 !~ /^[[:space:]]*$/ {print}
    ' "$README"
}

if [[ "$MODE" == "list" ]]; then
    extract_commands
    exit 0
fi

mapfile -t commands < <(extract_commands)
[[ ${#commands[@]} -gt 0 ]] || { echo "[FAIL] no README command contract blocks found" >&2; exit 1; }

missing=0
for line in "${commands[@]}"; do
    case "$line" in
        git\ clone*) command -v git >/dev/null 2>&1 || missing=$((missing+1)) ;;
        cd\ *) : ;;
        codex\ plugin*) command -v codex >/dev/null 2>&1 || missing=$((missing+1)) ;;
        *simple_model_pi.sh*)
            script=$(awk '{print $1}' <<<"$line")
            [[ -x "$ROOT/$script" ]] || { echo "[FAIL] missing executable: $script" >&2; missing=$((missing+1)); }
            ;;
        *)
            cmd=$(awk '{print $1}' <<<"$line")
            command -v "$cmd" >/dev/null 2>&1 || { echo "[FAIL] unknown README command: $line" >&2; missing=$((missing+1)); }
            ;;
    esac
done

[[ $missing -eq 0 ]]
