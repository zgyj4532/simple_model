#!/usr/bin/env bash
set -euo pipefail
ROOT="${SIMPLE_MODEL_ROOT:-$(pwd)}"
read -r req
method=$(jq -r '.method // ""' <<<"$req")
id=$(jq '.id // 1' <<<"$req")
case "$method" in
  initialize)
    result=$(jq -n '{protocolVersion:"2024-11-05", serverInfo:{name:"simple_model", version:"0.5"}}')
    ;;
  tools/list)
    result=$(jq -n '{tools:[{name:"resolved_struct"},{name:"code_facts"},{name:"pr_impact"},{name:"pr_gate"},{name:"next"}]}')
    ;;
  tools/call)
    name=$(jq -r '.params.name // ""' <<<"$req")
    case "$name" in
      resolved_struct) result=$(cd "$ROOT" && bash ./bootstrap.sh --resolve --json) ;;
      code_facts) result=$(cd "$ROOT" && bash generators/code_facts.sh --json) ;;
      pr_impact) files=$(jq -r '.params.arguments.files // ""' <<<"$req"); result=$(cd "$ROOT" && bash generators/pr_impact.sh --files "$files" --json) ;;
      pr_gate) files=$(jq -r '.params.arguments.files // ""' <<<"$req"); result=$(cd "$ROOT" && bash generators/pr_gate.sh --files "$files" --json || true) ;;
      next) result=$(cd "$ROOT" && bash ./bootstrap.sh --next --json || true) ;;
      *) result=$(jq -n --arg name "$name" '{error:"unknown_tool", name:$name}') ;;
    esac
    ;;
  resolved_struct)
    result=$(cd "$ROOT" && bash ./bootstrap.sh --resolve --json)
    ;;
  code_facts)
    result=$(cd "$ROOT" && bash generators/code_facts.sh --json)
    ;;
  pr_impact)
    files=$(jq -r '.params.files // ""' <<<"$req")
    result=$(cd "$ROOT" && bash generators/pr_impact.sh --files "$files" --json)
    ;;
  next)
    result=$(cd "$ROOT" && bash ./bootstrap.sh --next --json || true)
    ;;
  *)
    result=$(jq -n --arg method "$method" '{error:"unknown_method", method:$method}')
    ;;
esac
jq -n --argjson id "$id" --argjson result "$result" '{jsonrpc:"2.0", id:$id, result:$result}'
