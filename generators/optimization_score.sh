#!/usr/bin/env bash
set -euo pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="."
STRUCT="${STRUCT_FILE:-./struct.json}"
OUT_DIR="generated/optimization"
JSON_OUT=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        --root) ROOT="$2"; shift 2 ;;
        --struct|-s) STRUCT="$2"; shift 2 ;;
        --output-dir) OUT_DIR="$2"; shift 2 ;;
        --json) JSON_OUT=1; shift ;;
        -h|--help)
            echo "optimization_score.sh --root <repo> --struct <struct> [--json]"
            exit 0
            ;;
        *) echo "unknown arg: $1" >&2; exit 64 ;;
    esac
done

command -v jq >/dev/null 2>&1 || { echo "[FAIL] missing jq" >&2; exit 2; }
[[ -d "$ROOT" ]] || { echo "[FAIL] root not found: $ROOT" >&2; exit 2; }
[[ -f "$STRUCT" ]] || { echo "[FAIL] struct not found: $STRUCT" >&2; exit 2; }
jq empty "$STRUCT"
mkdir -p "$OUT_DIR"

ROOT="$(cd "$ROOT" && pwd)"
STRUCT_ABS="$(cd "$(dirname "$STRUCT")" && pwd)/$(basename "$STRUCT")"

adoption=$(bash "$SELF_DIR/adoption_audit.sh" --root "$ROOT" --struct "$STRUCT_ABS" --json || true)
interface=$(bash "$SELF_DIR/interface_scan.sh" --root "$ROOT" --struct "$STRUCT_ABS" --json || true)
imports=$(bash "$SELF_DIR/import_graph_scan.sh" --root "$ROOT" --struct "$STRUCT_ABS" --json || true)
tests=$(bash "$SELF_DIR/test_surface_scan.sh" --root "$ROOT" --struct "$STRUCT_ABS" --json || true)
owners=$(bash "$SELF_DIR/ownership_resolve.sh" --root "$ROOT" --struct "$STRUCT_ABS" --json || true)

score=$(jq -n \
  --arg root "$ROOT" \
  --arg struct "$STRUCT_ABS" \
  --arg generated_at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --argjson adoption "$adoption" \
  --argjson interface "$interface" \
  --argjson imports "$imports" \
  --argjson tests "$tests" \
  --argjson owners "$owners" '
  {
    unmanaged_files:($adoption.unmanaged_files // 0),
    interface_drift:(($interface.summary.undeclared_exports // 0) + ($interface.summary.missing_exports // 0) + ($interface.summary.missing_paths // 0)),
    import_drift:($imports.summary.warnings // 0),
    missing_tests:($tests.summary.untested_components // 0),
    owner_gaps:($owners.summary.orphaned // 0)
  } as $f
  | ($f.unmanaged_files * 4 + $f.interface_drift * 7 + $f.import_drift * 5 + $f.missing_tests * 2 + $f.owner_gaps * 2) as $debt
  | {
      schema_version:"1.0",
      ok:true,
      generated_at:$generated_at,
      root:$root,
      struct:$struct,
      score:(if (100 - $debt) < 0 then 0 else (100 - $debt) end),
      debt:$debt,
      factors:$f,
      weights:{unmanaged_files:4, interface_drift:7, import_drift:5, missing_tests:2, owner_gaps:2}
    }')

printf '%s\n' "$score" > "$OUT_DIR/score.json"
if [[ "$JSON_OUT" == "1" ]]; then
    printf '%s\n' "$score"
else
    jq -r '"Optimization Score\n\nTarget: " + .root + "\nScore: " + (.score|tostring) + "\nDebt: " + (.debt|tostring) + "\n\nFactors:\n  unmanaged files: " + (.factors.unmanaged_files|tostring) + "\n  interface drift: " + (.factors.interface_drift|tostring) + "\n  import drift: " + (.factors.import_drift|tostring) + "\n  missing tests: " + (.factors.missing_tests|tostring) + "\n  owner gaps: " + (.factors.owner_gaps|tostring)' <<<"$score"
fi
