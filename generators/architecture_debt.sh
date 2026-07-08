#!/usr/bin/env bash
set -euo pipefail
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="."; STRUCT="${STRUCT_FILE:-./struct.json}"; JSON_OUT=0
while [[ $# -gt 0 ]]; do case "$1" in --root) ROOT="$2"; shift 2;; --struct|-s) STRUCT="$2"; shift 2;; --json) JSON_OUT=1; shift;; *) shift;; esac; done
adoption=$(bash "$SELF_DIR/adoption_audit.sh" --root "$ROOT" --struct "$STRUCT" --json || true)
interface=$(bash "$SELF_DIR/interface_scan.sh" --root "$ROOT" --struct "$STRUCT" --json || true)
imports=$(bash "$SELF_DIR/import_graph_scan.sh" --root "$ROOT" --struct "$STRUCT" --json || true)
tests=$(bash "$SELF_DIR/test_surface_scan.sh" --root "$ROOT" --struct "$STRUCT" --json || true)
owners=$(bash "$SELF_DIR/ownership_resolve.sh" --root "$ROOT" --struct "$STRUCT" --json || true)
findings=$(jq -n --argjson a "$adoption" --argjson i "$interface" --argjson d "$imports" --argjson t "$tests" --argjson o "$owners" '[
  (if ($a.unmanaged_files//0)>0 then {id:"debt.unmanaged_code", severity:"medium", type:"unmanaged_code", count:$a.unmanaged_files, remediation:"add component path or waiver"} else empty end),
  (if ($i.summary.undeclared_exports//0)>0 then {id:"debt.undeclared_exports", severity:"medium", type:"undeclared_exports", count:$i.summary.undeclared_exports, remediation:"declare exports or make symbols private"} else empty end),
  (if ($d.summary.warnings//0)>0 then {id:"debt.undeclared_imports", severity:"medium", type:"undeclared_imports", count:$d.summary.warnings, remediation:"declare imports or remove dependency"} else empty end),
  (if ($t.summary.untested_components//0)>0 then {id:"debt.untested_components", severity:"low", type:"untested_components", count:$t.summary.untested_components, remediation:"add tests or checks"} else empty end),
  (if ($o.summary.orphaned//0)>0 then {id:"debt.orphaned_owners", severity:"low", type:"orphaned_owners", count:$o.summary.orphaned, remediation:"add owners"} else empty end)
]')
out=$(jq -n --argjson findings "$findings" '{ok:true, findings:$findings, summary:{findings:($findings|length)}}')
[[ "$JSON_OUT" == "1" ]] && echo "$out" || jq -r '.'
