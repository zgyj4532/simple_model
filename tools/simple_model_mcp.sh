#!/usr/bin/env bash
set -euo pipefail
ROOT="${SIMPLE_MODEL_ROOT:-$(pwd)}"
MANIFEST="$ROOT/codex/skills/simple-model-project-intelligence/references/command-manifest.json"
WRAPPER="$ROOT/codex/skills/simple-model-project-intelligence/scripts/simple_model_pi.sh"
read -r req
method=$(jq -r '.method // ""' <<<"$req")
id=$(jq '.id // 1' <<<"$req")

tool_list() {
  if [[ -f "$MANIFEST" ]]; then
    jq '{
      tools: (
        [
          {name:"resolved_struct", description:"Resolve multi-file struct includes."},
          {name:"code_facts", description:"Emit normalized code facts."},
          {name:"pr_impact", description:"Compute PR impact."},
          {name:"pr_gate", description:"Run deterministic PR gate."},
          {name:"next", description:"Get next struct todo."}
        ] + (.commands | map({
          name:("plugin_" + (.name | gsub("-"; "_"))),
          description,
          inputSchema:{
            type:"object",
            properties:{
              target_root:{type:"string"},
              struct:{type:"string"},
              files:{type:"string"}
            }
          }
        }))
      )
    }' "$MANIFEST"
  else
    jq -n '{tools:[{name:"resolved_struct"},{name:"code_facts"},{name:"pr_impact"},{name:"pr_gate"},{name:"next"}]}'
  fi
}

call_plugin() {
  local plugin_name="$1"
  local command="${plugin_name#plugin_}"
  command="${command//_/-}"
  local target struct files
  target=$(jq -r '.params.arguments.target_root // "."' <<<"$req")
  struct=$(jq -r '.params.arguments.struct // ""' <<<"$req")
  files=$(jq -r '.params.arguments.files // ""' <<<"$req")
  args=(--target-root "$target")
  [[ -n "$struct" ]] && args+=(--struct "$struct")
  case "$command" in
    doctor|commands) args+=(--json "$command") ;;
    interfaces|facts|audit|resolve) args+=("$command") ;;
    pr-gate) args+=("$command" "$target"); [[ -n "$files" ]] && args+=("$files") ;;
    *) jq -n --arg name "$plugin_name" '{error:"unknown_plugin_tool", name:$name}'; return 0 ;;
  esac
  (cd "$ROOT" && SIMPLE_MODEL_HOME="$ROOT" "$WRAPPER" "${args[@]}" || true)
}

case "$method" in
  initialize)
    result=$(jq -n '{protocolVersion:"2024-11-05", serverInfo:{name:"simple_model", version:"0.6"}}')
    ;;
  tools/list)
    result=$(tool_list)
    ;;
  tools/call)
    name=$(jq -r '.params.name // ""' <<<"$req")
    case "$name" in
      resolved_struct) result=$(cd "$ROOT" && bash ./bootstrap.sh --resolve --json) ;;
      code_facts) result=$(cd "$ROOT" && bash generators/code_facts.sh --json) ;;
      pr_impact) files=$(jq -r '.params.arguments.files // ""' <<<"$req"); result=$(cd "$ROOT" && bash generators/pr_impact.sh --files "$files" --json) ;;
      pr_gate) files=$(jq -r '.params.arguments.files // ""' <<<"$req"); result=$(cd "$ROOT" && bash generators/pr_gate.sh --files "$files" --json || true) ;;
      next) result=$(cd "$ROOT" && bash ./bootstrap.sh --next --json || true) ;;
      plugin_*) result=$(call_plugin "$name") ;;
      *) result=$(jq -n --arg name "$name" '{error:"unknown_tool", name:$name, hint:"Call tools/list for available tools."}') ;;
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
    result=$(jq -n --arg method "$method" '{error:"unknown_method", method:$method, hint:"Use initialize, tools/list, or tools/call."}')
    ;;
esac
jq -n --argjson id "$id" --argjson result "$result" '{jsonrpc:"2.0", id:$id, result:$result}'
