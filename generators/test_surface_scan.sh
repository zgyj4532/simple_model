#!/usr/bin/env bash
set -euo pipefail
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SELF_DIR/_lib.sh"
ROOT="."; JSON_OUT=0
while [[ $# -gt 0 ]]; do
    case "$1" in
        --root) ROOT="$2"; shift 2 ;;
        --struct|-s) STRUCT_FILE="$2"; shift 2 ;;
        --json) JSON_OUT=1; shift ;;
        *) echo "未知参数: $1" >&2; exit 64 ;;
    esac
done
ROOT="$(cd "$ROOT" && pwd)"
files=$(find "$ROOT" -type f \( -name '*test*.py' -o -name '*.test.ts' -o -name '*.spec.ts' -o -name '*_test.go' -o -name '*test*.rs' \) ! -path '*/node_modules/*' ! -path '*/generated/*' | sed "s#^$ROOT/##" | sort)
tests_json=$(printf '%s\n' "$files" | sed '/^$/d' | jq -R -s --slurpfile s "$STRUCT_FILE" '
  split("\n")[:-1] | map(. as $f | {
    path:$f,
    components: [($s[0].modules[]?.components[]? | select((.path//"") as $p | $p != "" and ($f | contains(($p|split("/")[-1]|sub("\\.[^.]+$"; ""))))) | .name)]
  })
')
untested=$(jq -n --slurpfile s "$STRUCT_FILE" --argjson tests "$tests_json" '
  [$s[0].modules[]?.components[]?.name] as $names
  | ($tests | map(.components[]) | unique) as $covered
  | $names | map(select(($covered | index(.)) == null))
')
out=$(jq -n --argjson tests "$tests_json" --argjson untested "$untested" '{ok:true, summary:{tests:($tests|length), untested_components:($untested|length)}, tests:$tests, untested_components:$untested}')
[[ "$JSON_OUT" == "1" ]] && echo "$out" || jq -r '.summary' <<<"$out"
