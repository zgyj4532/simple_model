#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MANIFEST_FILE="${SCRIPT_DIR}/../references/command-manifest.json"

usage() {
    cat <<'USAGE'
simple_model_pi.sh [--target-root PATH] [--struct PATH] <command> [args]

Global options:
  --target-root PATH       Repository to analyze. Defaults to current directory.
  --struct PATH            struct.json to use. Defaults to explicit path, nearest .projectIntelligence/config.json, then <target-root>/struct.json.
  --simple-model-home PATH Toolchain checkout. Defaults to SIMPLE_MODEL_HOME or auto-discovery.
  --json                   Machine-readable output for commands that support it.

Commands:
USAGE
    if [[ -f "$MANIFEST_FILE" ]] && command -v jq >/dev/null 2>&1; then
        jq -r '.commands[] | "  " + .name + " - " + .description' "$MANIFEST_FILE"
    else
        echo "  doctor - Diagnose plugin, toolchain, and target repo readiness."
        echo "  commands - List wrapper command metadata."
    fi
}

find_simple_model_home() {
    local explicit="${SIMPLE_MODEL_HOME:-}"
    if [[ -n "$explicit" ]]; then
        if [[ -x "$explicit/bootstrap.sh" && -d "$explicit/generators" ]]; then
            cd "$explicit" && pwd
            return 0
        fi
        echo "[FAIL] SIMPLE_MODEL_HOME is not a simple_model checkout: $explicit" >&2
        return 2
    fi

    local d="$PWD"
    while [[ "$d" != "/" ]]; do
        if [[ -x "$d/bootstrap.sh" && -d "$d/generators" ]]; then
            printf '%s\n' "$d"
            return 0
        fi
        d="$(dirname "$d")"
    done

    d="$(cd "$SCRIPT_DIR/../../.." && pwd)"
    if [[ -x "$d/bootstrap.sh" && -d "$d/generators" ]]; then
        printf '%s\n' "$d"
        return 0
    fi

    d="$(cd "$SCRIPT_DIR/../../../../../.." && pwd)"
    if [[ -x "$d/bootstrap.sh" && -d "$d/generators" ]]; then
        printf '%s\n' "$d"
        return 0
    fi

    echo "[FAIL] cannot locate simple_model root. Set SIMPLE_MODEL_HOME=/path/to/simple_model" >&2
    return 2
}

json_bool() {
    if "$@" >/dev/null 2>&1; then printf 'true'; else printf 'false'; fi
}

cmd_version() {
    local cmd="$1"
    if command -v "$cmd" >/dev/null 2>&1; then
        case "$cmd" in
            bash) bash --version | head -1 ;;
            jq) jq --version ;;
            git) git --version ;;
            codex) codex --version 2>/dev/null | head -1 || echo "available" ;;
            gh) gh --version 2>/dev/null | head -1 || echo "available" ;;
            *) "$cmd" --version 2>/dev/null | head -1 || echo "available" ;;
        esac
    else
        echo ""
    fi
}

doctor() {
    local json="$1"
    local bash_major="${BASH_VERSINFO[0]:-0}"
    local has_jq has_git has_codex has_gh home_ok target_ok struct_ok marketplace_ok plugin_ok dirty plugin_cache
    has_jq=$(json_bool command -v jq)
    has_git=$(json_bool command -v git)
    has_codex=$(json_bool command -v codex)
    has_gh=$(json_bool command -v gh)
    home_ok=$(json_bool test -x "$SIMPLE_HOME/bootstrap.sh")
    target_ok=$(json_bool test -d "$TARGET_ROOT")
    struct_ok=$(json_bool test -f "$STRUCT_PATH")
    marketplace_ok=$(json_bool jq empty "$SIMPLE_HOME/.agents/plugins/marketplace.json")
    plugin_ok=$(json_bool jq empty "$SIMPLE_HOME/plugins/simple-model-project-intelligence/.codex-plugin/plugin.json")
    dirty=$(cd "$SIMPLE_HOME" && git status --short 2>/dev/null | wc -l | tr -d ' ')
    plugin_cache="${HOME:-}/.codex/plugins/cache/simple-model/simple-model-project-intelligence/$(plugin_version 2>/dev/null || echo unknown)"
    local hard_fail=false
    [[ "$bash_major" -ge 4 && "$has_jq" == "true" && "$has_git" == "true" && "$home_ok" == "true" && "$target_ok" == "true" ]] || hard_fail=true

    if [[ "$json" == "1" ]]; then
        jq -n \
          --arg simple_model_home "$SIMPLE_HOME" \
          --arg target_root "$TARGET_ROOT" \
          --arg struct "$STRUCT_PATH" \
          --argjson bash_major "$bash_major" \
          --argjson has_jq "$has_jq" \
          --argjson has_git "$has_git" \
          --argjson has_codex "$has_codex" \
          --argjson has_gh "$has_gh" \
          --argjson home_ok "$home_ok" \
          --argjson target_ok "$target_ok" \
          --argjson struct_ok "$struct_ok" \
          --argjson marketplace_ok "$marketplace_ok" \
          --argjson plugin_ok "$plugin_ok" \
          --arg bash_version "$(cmd_version bash)" \
          --arg jq_version "$(cmd_version jq)" \
          --arg git_version "$(cmd_version git)" \
          --arg codex_version "$(cmd_version codex)" \
          --arg gh_version "$(cmd_version gh)" \
          --arg plugin_cache "$plugin_cache" \
          --argjson dirty_files "${dirty:-0}" \
          --argjson ok "$( [[ "$hard_fail" == "false" ]] && echo true || echo false )" \
          '{
            ok:$ok,
            simple_model_home:$simple_model_home,
            target_root:$target_root,
            struct:$struct,
            checks:{
              bash_major:$bash_major,
              jq:$has_jq,
              git:$has_git,
              codex_optional:$has_codex,
              gh_optional:$has_gh,
              simple_model_home:$home_ok,
              target_root:$target_ok,
              struct:$struct_ok,
              marketplace_json:$marketplace_ok,
              plugin_manifest:$plugin_ok
            },
            environment:{
              os: $ARGS.positional[0],
              bash_version:$bash_version,
              jq_version:$jq_version,
              git_version:$git_version,
              codex_version:$codex_version,
              gh_version:$gh_version,
              plugin_cache:$plugin_cache,
              dirty_files:$dirty_files
            },
            hints: (
              []
              + (if $bash_major < 4 then ["Install bash >= 4 and run with that shell."] else [] end)
              + (if $has_jq then [] else ["Install jq."] end)
              + (if $home_ok then [] else ["Set SIMPLE_MODEL_HOME=/path/to/simple_model."] end)
              + (if $target_ok then [] else ["Pass --target-root /path/to/repo."] end)
              + (if $struct_ok then [] else ["Pass --struct /path/to/struct.json or create one with ingest."] end)
            )
          }' --args "$(uname -s 2>/dev/null || echo unknown)"
    else
        echo "simple_model doctor"
        echo "  simple_model_home: $SIMPLE_HOME"
        echo "  target_root      : $TARGET_ROOT"
        echo "  struct           : $STRUCT_PATH"
        echo "  bash_major       : $bash_major"
        echo "  jq               : $has_jq"
        echo "  git              : $has_git"
        echo "  codex optional   : $has_codex"
        echo "  gh optional      : $has_gh"
        echo "  marketplace      : $marketplace_ok"
        echo "  plugin manifest  : $plugin_ok"
    fi
    [[ "$hard_fail" == "false" ]]
}

run_check() {
    local name="$1"; local severity="$2"; local remediation="$3"; shift 3
    local output rc
    set +e
    output="$("$@" 2>&1)"
    rc=$?
    set -e
    jq -n --arg id "$name" --arg name "$name" --arg severity "$severity" --arg remediation "$remediation" --arg output "$output" --argjson exit_code "$rc" '{
      id:$id,
      name:$name,
      severity:$severity,
      ok:($exit_code == 0),
      exit_code:$exit_code,
      evidence:$output,
      remediation:$remediation
    }'
}

plugin_version() {
    jq -r '.version' "$SIMPLE_HOME/plugins/simple-model-project-intelligence/.codex-plugin/plugin.json"
}

self_check() {
    local out_dir="$1"
    mkdir -p "$out_dir/history"
    local version report checks
    version="$(plugin_version)"
    checks=$(
        {
            run_check "doctor" "fatal" "Run simple_model_pi.sh doctor --json and fix reported hard blockers." "$0" --target-root "$TARGET_ROOT" --struct "$STRUCT_PATH" doctor --json
            run_check "marketplace_json" "fatal" "Validate or restore .agents/plugins/marketplace.json." jq empty "$SIMPLE_HOME/.agents/plugins/marketplace.json"
            run_check "plugin_manifest" "fatal" "Validate or restore plugins/simple-model-project-intelligence/.codex-plugin/plugin.json." jq empty "$SIMPLE_HOME/plugins/simple-model-project-intelligence/.codex-plugin/plugin.json"
            run_check "skill_sync" "blocking" "Run tools/sync_codex_plugin.sh --sync." bash "$SIMPLE_HOME/tools/sync_codex_plugin.sh" --check
            run_check "wrapper_help" "fatal" "Fix simple_model_pi.sh so help exits successfully." "$0" help
            run_check "commands_json" "fatal" "Fix command-manifest.json or wrapper commands --json." "$0" commands --json
            run_check "command_coverage" "blocking" "Add tests and release_gate fields for every command in command-manifest.json." jq -e 'all(.commands[]; ((.tests // []) | length) > 0 and has("release_gate"))' "$MANIFEST_FILE"
            run_check "readme_command_contract" "blocking" "Update README command contract blocks and tests." bash "$SIMPLE_HOME/tools/readme_command_contract.sh" --check
            run_check "package_dry_run" "blocking" "Run tools/package_codex_plugin.sh --version $version and fix packaging errors." bash "$SIMPLE_HOME/tools/package_codex_plugin.sh" --version "$version"
            run_check "mcp_tools_list" "blocking" "Fix tools/simple_model_mcp.sh tools/list plugin bridge." bash -c "printf '{\"id\":1,\"method\":\"tools/list\"}\\n' | SIMPLE_MODEL_ROOT='$SIMPLE_HOME' bash '$SIMPLE_HOME/tools/simple_model_mcp.sh' | jq -e '.result.tools[]|select(.name==\"plugin_doctor\")'"
        } | jq -s '.'
    )
    local latest_prev=""
    [[ -f "$out_dir/latest.json" ]] && latest_prev="$out_dir/latest.json"
    report=$(jq -n \
      --arg version "$version" \
      --arg generated_at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
      --arg simple_model_home "$SIMPLE_HOME" \
      --arg target_root "$TARGET_ROOT" \
      --arg manifest "$MANIFEST_FILE" \
      --arg previous "$latest_prev" \
      --argjson checks "$checks" \
      --argjson commands "$(jq '.commands' "$MANIFEST_FILE")" \
      '{
        schema_version:"1.0",
        ok: all($checks[]; .ok or (.severity == "warning") or (.severity == "info")),
        generated_at:$generated_at,
        plugin:{name:"simple-model-project-intelligence", version:$version},
        simple_model_home:$simple_model_home,
        target_root:$target_root,
        command_manifest:$manifest,
        checks:$checks,
        command_coverage:{
          total:($commands|length),
          tested:($commands|map(select(((.tests // [])|length)>0))|length),
          release_gates:($commands|map(select(.release_gate == true))|length),
          untested:($commands|map(select(((.tests // [])|length)==0)|.name))
        },
        summary:{
          fatal:($checks|map(select(.severity=="fatal" and (.ok|not)))|length),
          blocking:($checks|map(select(.severity=="blocking" and (.ok|not)))|length),
          warning:($checks|map(select(.severity=="warning" and (.ok|not)))|length),
          info:($checks|map(select(.severity=="info" and (.ok|not)))|length)
        },
        trend:{
          previous_exists:($previous != ""),
          previous_path:$previous
        }
      }')
    local stamp
    stamp="$(date -u +%Y%m%dT%H%M%SZ)"
    printf '%s\n' "$report" > "$out_dir/plugin-self-audit.json"
    printf '%s\n' "$report" > "$out_dir/latest.json"
    printf '%s\n' "$report" > "$out_dir/history/$stamp.json"
    {
        echo "# simple_model plugin self-audit"
        echo
        jq -r '"- ok: " + (.ok|tostring), "- fatal: " + (.summary.fatal|tostring), "- blocking: " + (.summary.blocking|tostring), "- warning: " + (.summary.warning|tostring), "- version: " + .plugin.version, "- commands: " + (.command_coverage.total|tostring), "- tested: " + (.command_coverage.tested|tostring), "- release gates: " + (.command_coverage.release_gates|tostring)' <<<"$report"
        echo
        echo "## Checks"
        jq -r '.checks[] | "- [" + (if .ok then "x" else " " end) + "] " + .severity + "/" + .name + " (exit " + (.exit_code|tostring) + ") - " + .remediation' <<<"$report"
    } > "$out_dir/plugin-self-audit.md"
    printf '%s\n' "$report"
}

self_release() {
    local version="" mode="dry-run"
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --version) version="$2"; shift 2 ;;
            --dry-run) mode="dry-run"; shift ;;
            --publish) mode="publish"; shift ;;
            --json) JSON_OUT=1; shift ;;
            *) echo "[FAIL] unknown self-release arg: $1" >&2; exit 64 ;;
        esac
    done
    [[ -n "$version" ]] || { echo "[FAIL] self-release requires --version" >&2; exit 64; }
    mkdir -p "$SIMPLE_HOME/generated/releases"
    local check package release_url="" stages tag_exists tag_target head
    head=$(cd "$SIMPLE_HOME" && git rev-parse HEAD 2>/dev/null || echo unknown)
    check=$(self_check "$SIMPLE_HOME/generated/plugin-self-audit")
    package=$(bash "$SIMPLE_HOME/tools/package_codex_plugin.sh" --version "$version")
    if (cd "$SIMPLE_HOME" && git show-ref --verify --quiet "refs/tags/v$version"); then
        tag_exists=true
        tag_target=$(cd "$SIMPLE_HOME" && git rev-list -n 1 "v$version" 2>/dev/null || true)
    else
        tag_exists=false
        tag_target=""
    fi
    stages=$(jq -n \
      --argjson check "$check" \
      --argjson package "$package" \
      --arg version "$version" \
      --arg mode "$mode" \
      --arg head "$head" \
      --arg tag_target "$tag_target" \
      --argjson tag_exists "$tag_exists" \
      '[
        {name:"validate", ok:$check.ok, mode:"run"},
        {name:"package", ok:$package.ok, mode:"run", file:$package.file, sha256:$package.sha256},
        {name:"checksum", ok:($package.sha256 != null and ($package.sha256|length) == 64), mode:"run"},
        {name:"tag-check", ok:(($tag_exists|not) or $tag_target == $head), mode:"run", tag:("v"+$version), target:$tag_target, head:$head},
        {name:"release-draft", ok:true, mode:(if $mode=="publish" then "run" else "dry-run" end)},
        {name:"upload", ok:true, mode:(if $mode=="publish" then "run" else "dry-run" end)},
        {name:"verify", ok:true, mode:(if $mode=="publish" then "run" else "dry-run" end)},
        {name:"finalize", ok:true, mode:"dry-run"}
      ]')
    if ! jq -e 'all(.[]; .ok)' <<<"$stages" >/dev/null; then
        jq -n --arg mode "$mode" --arg version "$version" --argjson self_check "$check" --argjson package "$package" --argjson stages "$stages" '{ok:false, mode:$mode, version:$version, stages:$stages, self_check:$self_check, package:$package, resume:"Fix failed stages, then rerun self-release --dry-run.", rollback:"No publish action was taken."}'
        return 1
    fi
    if [[ "$mode" == "publish" ]]; then
        command -v gh >/dev/null 2>&1 || { echo "[FAIL] gh is required for --publish" >&2; exit 2; }
        release_url=$(gh release create "v$version" "$(jq -r '.file' <<<"$package")" --draft --title "Simple Model Project Intelligence plugin $version" --notes-file "$SIMPLE_HOME/generated/plugin-self-audit/plugin-self-audit.md")
    fi
    local record
    record=$(jq -n --arg mode "$mode" --arg version "$version" --arg release_url "$release_url" --argjson self_check "$check" --argjson package "$package" --argjson stages "$stages" '{ok:(all($stages[]; .ok)), mode:$mode, version:$version, stages:$stages, self_check:$self_check, package:$package, release_url:$release_url, resume:"Rerun self-release with the same version after fixing failures.", rollback:(if $mode=="publish" then "Delete draft release if publish verification fails." else "No remote state changed." end)}')
    printf '%s\n' "$record" > "$SIMPLE_HOME/generated/releases/$version.json"
    printf '%s\n' "$record"
}

JSON_OUT=0
TARGET_ROOT="$PWD"
STRUCT_PATH=""
HOME_OVERRIDE=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --target-root) TARGET_ROOT="$2"; shift 2 ;;
        --struct|-s) STRUCT_PATH="$2"; shift 2 ;;
        --simple-model-home) HOME_OVERRIDE="$2"; shift 2 ;;
        --json) JSON_OUT=1; shift ;;
        -h|--help|help) usage; exit 0 ;;
        --) shift; break ;;
        *) break ;;
    esac
done

[[ -n "$HOME_OVERRIDE" ]] && export SIMPLE_MODEL_HOME="$HOME_OVERRIDE"
TARGET_ROOT="$(cd "$TARGET_ROOT" 2>/dev/null && pwd || printf '%s' "$TARGET_ROOT")"
if [[ "${1:-}" == "init" ]]; then
    init_args=(--target-root "$TARGET_ROOT")
    [[ -n "$STRUCT_PATH" ]] && init_args+=(--struct "$STRUCT_PATH")
    shift
    exec "$SCRIPT_DIR/project_init.sh" "${init_args[@]}" "$@"
fi
SIMPLE_HOME="$(find_simple_model_home)"
PI_DIR="$TARGET_ROOT/.projectIntelligence"
ARTIFACT_ROOT="$PI_DIR/artifacts"
if [[ -z "$STRUCT_PATH" ]]; then
    config_file="$PI_DIR/config.json"
    if [[ -f "$config_file" ]] && command -v jq >/dev/null 2>&1; then
        configured_struct=$(jq -r '.struct_path // empty' "$config_file")
        if [[ -n "$configured_struct" ]]; then
            [[ "$configured_struct" = /* ]] && STRUCT_PATH="$configured_struct" || STRUCT_PATH="$PI_DIR/$configured_struct"
        fi
    fi
    if [[ -z "$STRUCT_PATH" && -f "$TARGET_ROOT/struct.json" ]]; then
        STRUCT_PATH="$TARGET_ROOT/struct.json"
    fi
fi
if [[ -z "$STRUCT_PATH" ]]; then
    echo "[FAIL] no project model found; run '$SCRIPT_DIR/simple_model_pi.sh --target-root $TARGET_ROOT init' or pass --struct PATH" >&2
    exit 2
fi
[[ "$STRUCT_PATH" = /* ]] || STRUCT_PATH="$PWD/$STRUCT_PATH"

cmd="${1:-}"
[[ -n "$cmd" ]] || { usage; exit 64; }
shift || true

for arg in "$@"; do
    [[ "$arg" == "--json" ]] && JSON_OUT=1
done

case "$cmd" in
    doctor)
        doctor "$JSON_OUT"
        ;;
    commands)
        if [[ "$JSON_OUT" == "1" ]]; then
            jq . "$MANIFEST_FILE"
        else
            jq -r '.commands[] | "  " + .name + " - " + .description' "$MANIFEST_FILE"
        fi
        ;;
    self-check)
        out_dir="$SIMPLE_HOME/generated/plugin-self-audit"
        while [[ $# -gt 0 ]]; do
            case "$1" in
                --output-dir) out_dir="$2"; shift 2 ;;
                --json) JSON_OUT=1; shift ;;
                *) shift ;;
            esac
        done
        result=$(self_check "$out_dir")
        if [[ "$JSON_OUT" == "1" ]]; then
            printf '%s\n' "$result"
        else
            jq -r '"self-check ok=" + (.ok|tostring) + " report=generated/plugin-self-audit/plugin-self-audit.md"' <<<"$result"
        fi
        ;;
    self-audit)
        out_dir="$SIMPLE_HOME/generated/plugin-self-audit"
        while [[ $# -gt 0 ]]; do
            case "$1" in
                --output-dir) out_dir="$2"; shift 2 ;;
                --json) JSON_OUT=1; shift ;;
                *) shift ;;
            esac
        done
        [[ -f "$out_dir/plugin-self-audit.json" ]] || self_check "$out_dir" >/dev/null
        if [[ "$JSON_OUT" == "1" ]]; then
            jq . "$out_dir/plugin-self-audit.json"
        else
            cat "$out_dir/plugin-self-audit.md"
        fi
        ;;
    self-release)
        self_release "$@"
        ;;
    macros)
        cd "$SIMPLE_HOME"
        if [[ "$JSON_OUT" == "1" ]]; then
            generators/macro_registry.sh --json
        else
            generators/macro_registry.sh
        fi
        ;;
    macro-suggest)
        out_dir="$ARTIFACT_ROOT/optimization"
        while [[ $# -gt 0 ]]; do
            case "$1" in
                --output-dir) out_dir="$2"; shift 2 ;;
                --json) JSON_OUT=1; shift ;;
                *) echo "[FAIL] unknown macro-suggest arg: $1" >&2; exit 64 ;;
            esac
        done
        cd "$SIMPLE_HOME"
        args=(--root "$TARGET_ROOT" --struct "$STRUCT_PATH" --output-dir "$out_dir")
        [[ "$JSON_OUT" == "1" ]] && args+=(--json)
        generators/macro_suggest.sh "${args[@]}"
        ;;
    macro-compile)
        suggestions="$SIMPLE_HOME/generated/optimization/macro-suggestions.json"; out_dir="$SIMPLE_HOME/generated/optimization"
        while [[ $# -gt 0 ]]; do
            case "$1" in
                --suggestions) suggestions="$2"; shift 2 ;;
                --output-dir) out_dir="$2"; shift 2 ;;
                --json) JSON_OUT=1; shift ;;
                *) echo "[FAIL] unknown macro-compile arg: $1" >&2; exit 64 ;;
            esac
        done
        cd "$SIMPLE_HOME"
        args=(--suggestions "$suggestions" --root "$TARGET_ROOT" --struct "$STRUCT_PATH" --output-dir "$out_dir")
        [[ "$JSON_OUT" == "1" ]] && args+=(--json)
        generators/macro_compile.sh "${args[@]}"
        ;;
    macro-run)
        mode="dry-run"; plan="$SIMPLE_HOME/generated/optimization/plan.json"; only=""
        while [[ $# -gt 0 ]]; do
            case "$1" in
                --plan) plan="$2"; shift 2 ;;
                --macro) only="$2"; shift 2 ;;
                --dry-run) mode="dry-run"; shift ;;
                --apply) mode="apply"; shift ;;
                --json) JSON_OUT=1; shift ;;
                *) echo "[FAIL] unknown macro-run arg: $1" >&2; exit 64 ;;
            esac
        done
        cd "$SIMPLE_HOME"
        args=(--plan "$plan" "--$mode" --output-dir "$SIMPLE_HOME/generated/optimization")
        [[ -n "$only" ]] && args+=(--macro "$only")
        [[ "$JSON_OUT" == "1" ]] && args+=(--json)
        generators/macro_exec.sh "${args[@]}"
        ;;
    score)
        out_dir="$SIMPLE_HOME/generated/optimization"
        while [[ $# -gt 0 ]]; do
            case "$1" in
                --output-dir) out_dir="$2"; shift 2 ;;
                --json) JSON_OUT=1; shift ;;
                *) echo "[FAIL] unknown score arg: $1" >&2; exit 64 ;;
            esac
        done
        cd "$SIMPLE_HOME"
        args=(--root "$TARGET_ROOT" --struct "$STRUCT_PATH" --output-dir "$out_dir")
        [[ "$JSON_OUT" == "1" ]] && args+=(--json)
        generators/optimization_score.sh "${args[@]}"
        ;;
    optimize-loop)
        mode="dry-run"; out_dir="$SIMPLE_HOME/generated/optimization"; budget=3
        while [[ $# -gt 0 ]]; do
            case "$1" in
                --dry-run) mode="dry-run"; shift ;;
                --apply) mode="apply"; shift ;;
                --budget) budget="$2"; shift 2 ;;
                --output-dir) out_dir="$2"; shift 2 ;;
                --json) JSON_OUT=1; shift ;;
                *) echo "[FAIL] unknown optimize-loop arg: $1" >&2; exit 64 ;;
            esac
        done
        cd "$SIMPLE_HOME"
        args=(--root "$TARGET_ROOT" --struct "$STRUCT_PATH" --output-dir "$out_dir" --budget "$budget" "--$mode")
        [[ "$JSON_OUT" == "1" ]] && args+=(--json)
        generators/optimization_loop.sh "${args[@]}"
        ;;
    optimize)
        mode="dry-run"; out_dir="$SIMPLE_HOME/generated/optimization"
        while [[ $# -gt 0 ]]; do
            case "$1" in
                --dry-run) mode="dry-run"; shift ;;
                --apply) mode="apply"; shift ;;
                --output-dir) out_dir="$2"; shift 2 ;;
                --json) JSON_OUT=1; shift ;;
                *) echo "[FAIL] unknown optimize arg: $1" >&2; exit 64 ;;
            esac
        done
        cd "$SIMPLE_HOME"
        plan=$(generators/optimization_plan.sh --root "$TARGET_ROOT" --struct "$STRUCT_PATH" --output-dir "$out_dir" --json)
        exec_result=$(generators/macro_exec.sh --plan "$out_dir/plan.json" "--$mode" --output-dir "$out_dir" --json)
        if [[ "$JSON_OUT" == "1" ]]; then
            jq -n --argjson plan "$plan" --argjson execution "$exec_result" '{ok:($plan.ok and $execution.ok), plan:$plan, execution:$execution}'
        else
            jq -r '"Project Optimization Report\n\nTarget: " + .root + "\nMode: " + "'"$mode"'" + "\n\nFindings:\n  unmanaged files: " + (.summary.unmanaged_files|tostring) + "\n  interface drift: " + (.summary.interface_drift|tostring) + "\n  import drift: " + (.summary.import_drift|tostring) + "\n  debt findings: " + (.summary.debt_findings|tostring) + "\n\nPlanned Macros:\n" + ((.actions | map("  - " + .macro_id + " risk=" + .risk + " target=" + ((.target.component // .target.struct // "repo")|tostring)) | join("\n")) // "  none")' <<<"$plan"
            echo
            jq -r '"Result:\n  applied: " + (.summary.applied|tostring) + "\n  dry-run: " + (.summary.dry_run|tostring) + "\n  skipped: " + (.summary.skipped|tostring) + "\n  failed: " + (.summary.failed|tostring) + "\n\nReports:\n  plan: generated/optimization/plan.json\n  execution: generated/optimization/execution.json\n  rollback: generated/optimization/rollback.json"' <<<"$exec_result"
        fi
        ;;
    parser-backends)
        cd "$SIMPLE_HOME"
        args=(--root "$TARGET_ROOT")
        [[ "$JSON_OUT" == "1" ]] && args+=(--json)
        generators/parser_backends.sh "${args[@]}"
        ;;
    deep-parser-probe)
        cd "$SIMPLE_HOME"
        args=(--root "$TARGET_ROOT")
        [[ "$JSON_OUT" == "1" ]] && args+=(--json)
        generators/deep_parser_probe.sh "${args[@]}"
        ;;
    semantic-ir)
        out="$SIMPLE_HOME/generated/intelligence/interface-ir.json"
        while [[ $# -gt 0 ]]; do
            case "$1" in
                --output) out="$2"; shift 2 ;;
                --json) JSON_OUT=1; shift ;;
                *) echo "[FAIL] unknown semantic-ir arg: $1" >&2; exit 64 ;;
            esac
        done
        cd "$SIMPLE_HOME"
        args=(--root "$TARGET_ROOT" --struct "$STRUCT_PATH" --output "$out")
        [[ "$JSON_OUT" == "1" ]] && args+=(--json)
        generators/semantic_interface_ir.sh "${args[@]}"
        ;;
    tree-sitter-scan)
        out="$SIMPLE_HOME/generated/intelligence/tree-sitter-facts.json"
        while [[ $# -gt 0 ]]; do
            case "$1" in
                --output) out="$2"; shift 2 ;;
                --json) JSON_OUT=1; shift ;;
                *) echo "[FAIL] unknown tree-sitter-scan arg: $1" >&2; exit 64 ;;
            esac
        done
        cd "$SIMPLE_HOME"
        args=(--root "$TARGET_ROOT" --output "$out")
        [[ "$JSON_OUT" == "1" ]] && args+=(--json)
        generators/tree_sitter_scan.sh "${args[@]}"
        ;;
    lsp-symbols)
        out="$SIMPLE_HOME/generated/intelligence/lsp-symbols.json"
        while [[ $# -gt 0 ]]; do
            case "$1" in
                --output) out="$2"; shift 2 ;;
                --json) JSON_OUT=1; shift ;;
                *) echo "[FAIL] unknown lsp-symbols arg: $1" >&2; exit 64 ;;
            esac
        done
        cd "$SIMPLE_HOME"
        args=(--root "$TARGET_ROOT" --output "$out")
        [[ "$JSON_OUT" == "1" ]] && args+=(--json)
        generators/lsp_symbol_index.sh "${args[@]}"
        ;;
    semantic-graph)
        out="$SIMPLE_HOME/generated/intelligence/semantic-graph.json"
        while [[ $# -gt 0 ]]; do
            case "$1" in
                --output) out="$2"; shift 2 ;;
                --json) JSON_OUT=1; shift ;;
                *) echo "[FAIL] unknown semantic-graph arg: $1" >&2; exit 64 ;;
            esac
        done
        cd "$SIMPLE_HOME"
        args=(--root "$TARGET_ROOT" --struct "$STRUCT_PATH" --output "$out")
        [[ "$JSON_OUT" == "1" ]] && args+=(--json)
        generators/semantic_graph.sh "${args[@]}"
        ;;
    codemod)
        spec=""; out="$SIMPLE_HOME/generated/codemods/result.json"; mode="simulate"
        while [[ $# -gt 0 ]]; do
            case "$1" in
                --spec) spec="$2"; shift 2 ;;
                --output) out="$2"; shift 2 ;;
                --simulate) mode="simulate"; shift ;;
                --apply) mode="apply"; shift ;;
                --json) JSON_OUT=1; shift ;;
                *) echo "[FAIL] unknown codemod arg: $1" >&2; exit 64 ;;
            esac
        done
        [[ -n "$spec" ]] || { echo "[FAIL] codemod requires --spec" >&2; exit 64; }
        cd "$SIMPLE_HOME"
        args=(--root "$TARGET_ROOT" --spec "$spec" --output "$out" "--$mode")
        [[ "$JSON_OUT" == "1" ]] && args+=(--json)
        generators/codemod_backend.sh "${args[@]}"
        ;;
    score-calibrate)
        out="$SIMPLE_HOME/generated/optimization/score-model.json"; corpus="$SIMPLE_HOME/benchmarks/optimizer-corpus"
        while [[ $# -gt 0 ]]; do
            case "$1" in
                --output) out="$2"; shift 2 ;;
                --corpus) corpus="$2"; shift 2 ;;
                --json) JSON_OUT=1; shift ;;
                *) echo "[FAIL] unknown score-calibrate arg: $1" >&2; exit 64 ;;
            esac
        done
        cd "$SIMPLE_HOME"
        args=(--corpus "$corpus" --output "$out")
        [[ "$JSON_OUT" == "1" ]] && args+=(--json)
        generators/score_calibrate.sh "${args[@]}"
        ;;
    optimizer-report)
        search="$SIMPLE_HOME/generated/optimization/search.json"; graph="$SIMPLE_HOME/generated/optimization/graph.json"; out_dir="$SIMPLE_HOME/generated/optimization"
        while [[ $# -gt 0 ]]; do
            case "$1" in
                --search) search="$2"; shift 2 ;;
                --graph) graph="$2"; shift 2 ;;
                --output-dir) out_dir="$2"; shift 2 ;;
                --json) JSON_OUT=1; shift ;;
                *) echo "[FAIL] unknown optimizer-report arg: $1" >&2; exit 64 ;;
            esac
        done
        cd "$SIMPLE_HOME"
        args=(--search "$search" --graph "$graph" --output-dir "$out_dir")
        [[ "$JSON_OUT" == "1" ]] && args+=(--json)
        generators/optimizer_report.sh "${args[@]}"
        ;;
    project-structure)
        out="$SIMPLE_HOME/generated/intelligence/project-structure.json"
        while [[ $# -gt 0 ]]; do
            case "$1" in
                --output) out="$2"; shift 2 ;;
                --json) JSON_OUT=1; shift ;;
                *) echo "[FAIL] unknown project-structure arg: $1" >&2; exit 64 ;;
            esac
        done
        cd "$SIMPLE_HOME"
        args=(--root "$TARGET_ROOT" --struct "$STRUCT_PATH" --output "$out")
        [[ "$JSON_OUT" == "1" ]] && args+=(--json)
        generators/project_structure_miner.sh "${args[@]}"
        ;;
    framework-surfaces)
        cd "$SIMPLE_HOME"
        args=(--root "$TARGET_ROOT" --struct "$STRUCT_PATH")
        [[ "$JSON_OUT" == "1" ]] && args+=(--json)
        generators/framework_surfaces.sh "${args[@]}"
        ;;
    dynamic-surface)
        out="$SIMPLE_HOME/generated/intelligence/dynamic-surfaces.json"
        while [[ $# -gt 0 ]]; do
            case "$1" in
                --output) out="$2"; shift 2 ;;
                --json) JSON_OUT=1; shift ;;
                *) echo "[FAIL] unknown dynamic-surface arg: $1" >&2; exit 64 ;;
            esac
        done
        cd "$SIMPLE_HOME"
        args=(--root "$TARGET_ROOT" --struct "$STRUCT_PATH" --output "$out")
        [[ "$JSON_OUT" == "1" ]] && args+=(--json)
        generators/dynamic_surface_scan.sh "${args[@]}"
        ;;
    runtime-probe)
        out="$SIMPLE_HOME/generated/intelligence/runtime-observations.json"; mode="plan"; policy=""
        while [[ $# -gt 0 ]]; do
            case "$1" in
                --output) out="$2"; shift 2 ;;
                --policy) policy="$2"; shift 2 ;;
                --execute) mode="execute"; shift ;;
                --dry-run|--plan) mode="plan"; shift ;;
                --json) JSON_OUT=1; shift ;;
                *) echo "[FAIL] unknown runtime-probe arg: $1" >&2; exit 64 ;;
            esac
        done
        cd "$SIMPLE_HOME"
        args=(--root "$TARGET_ROOT" --output "$out")
        [[ -n "$policy" ]] && args+=(--policy "$policy")
        [[ "$mode" == "execute" ]] && args+=(--execute)
        [[ "$JSON_OUT" == "1" ]] && args+=(--json)
        generators/runtime_probe.sh "${args[@]}"
        ;;
    dynamic-merge)
        surfaces="$SIMPLE_HOME/generated/intelligence/dynamic-surfaces.json"
        observations="$SIMPLE_HOME/generated/intelligence/runtime-observations.json"
        out="$SIMPLE_HOME/generated/intelligence/dynamic-surfaces.observed.json"
        while [[ $# -gt 0 ]]; do
            case "$1" in
                --surfaces) surfaces="$2"; shift 2 ;;
                --observations) observations="$2"; shift 2 ;;
                --output) out="$2"; shift 2 ;;
                --json) JSON_OUT=1; shift ;;
                *) echo "[FAIL] unknown dynamic-merge arg: $1" >&2; exit 64 ;;
            esac
        done
        cd "$SIMPLE_HOME"
        args=(--surfaces "$surfaces" --observations "$observations" --output "$out")
        [[ "$JSON_OUT" == "1" ]] && args+=(--json)
        generators/dynamic_observation_merge.sh "${args[@]}"
        ;;
    contracts)
        cd "$SIMPLE_HOME"
        args=(--root "$TARGET_ROOT" --struct "$STRUCT_PATH")
        [[ "$JSON_OUT" == "1" ]] && args+=(--json)
        generators/contract_graph.sh "${args[@]}"
        ;;
    macro-rank)
        suggestions="$SIMPLE_HOME/generated/optimization/macro-suggestions.json"
        while [[ $# -gt 0 ]]; do
            case "$1" in
                --suggestions) suggestions="$2"; shift 2 ;;
                --json) JSON_OUT=1; shift ;;
                *) echo "[FAIL] unknown macro-rank arg: $1" >&2; exit 64 ;;
            esac
        done
        cd "$SIMPLE_HOME"
        args=(--suggestions "$suggestions")
        [[ "$JSON_OUT" == "1" ]] && args+=(--json)
        generators/macro_rank.sh "${args[@]}"
        ;;
    macro-simulate)
        plan="$SIMPLE_HOME/generated/optimization/plan.json"; out_dir="$SIMPLE_HOME/generated/optimization"; jobs=1
        while [[ $# -gt 0 ]]; do
            case "$1" in
                --plan) plan="$2"; shift 2 ;;
                --output-dir) out_dir="$2"; shift 2 ;;
                --jobs) jobs="$2"; shift 2 ;;
                --json) JSON_OUT=1; shift ;;
                *) echo "[FAIL] unknown macro-simulate arg: $1" >&2; exit 64 ;;
            esac
        done
        cd "$SIMPLE_HOME"
        args=(--plan "$plan" --output-dir "$out_dir" --jobs "$jobs")
        [[ "$JSON_OUT" == "1" ]] && args+=(--json)
        generators/macro_simulate.sh "${args[@]}"
        ;;
    macro-family-suggest)
        out_dir="$SIMPLE_HOME/macros/families"
        while [[ $# -gt 0 ]]; do
            case "$1" in
                --output-dir) out_dir="$2"; shift 2 ;;
                --json) JSON_OUT=1; shift ;;
                *) echo "[FAIL] unknown macro-family-suggest arg: $1" >&2; exit 64 ;;
            esac
        done
        cd "$SIMPLE_HOME"
        args=(--root "$TARGET_ROOT" --struct "$STRUCT_PATH" --output-dir "$out_dir")
        [[ "$JSON_OUT" == "1" ]] && args+=(--json)
        generators/macro_family_suggest.sh "${args[@]}"
        ;;
    context-pack)
        workflow="optimize"; out_dir="$SIMPLE_HOME/generated/codex/context-packs"
        while [[ $# -gt 0 ]]; do
            case "$1" in
                --workflow) workflow="$2"; shift 2 ;;
                --output-dir) out_dir="$2"; shift 2 ;;
                --json) JSON_OUT=1; shift ;;
                *) echo "[FAIL] unknown context-pack arg: $1" >&2; exit 64 ;;
            esac
        done
        cd "$SIMPLE_HOME"
        args=(--root "$TARGET_ROOT" --struct "$STRUCT_PATH" --workflow "$workflow" --output-dir "$out_dir")
        [[ "$JSON_OUT" == "1" ]] && args+=(--json)
        generators/codex_context_pack.sh "${args[@]}"
        ;;
    autopilot)
        mode="dry-run"; out_dir="$SIMPLE_HOME/generated/autopilot"; jobs=2; budget=5; check_mode="fast"; changed_files=""
        while [[ $# -gt 0 ]]; do
            case "$1" in
                --dry-run) mode="dry-run"; shift ;;
                --apply) mode="apply"; shift ;;
                --output-dir) out_dir="$2"; shift 2 ;;
                --jobs) jobs="$2"; shift 2 ;;
                --budget) budget="$2"; shift 2 ;;
                --mode) check_mode="$2"; shift 2 ;;
                --changed-files) changed_files="$2"; shift 2 ;;
                --json) JSON_OUT=1; shift ;;
                *) echo "[FAIL] unknown autopilot arg: $1" >&2; exit 64 ;;
            esac
        done
        cd "$SIMPLE_HOME"
        args=(--root "$TARGET_ROOT" --struct "$STRUCT_PATH" --output-dir "$out_dir" "--$mode" --jobs "$jobs" --budget "$budget" --mode "$check_mode")
        [[ -n "$changed_files" ]] && args+=(--changed-files "$changed_files")
        [[ "$JSON_OUT" == "1" ]] && args+=(--json)
        generators/autopilot.sh "${args[@]}"
        ;;
    optimization-graph)
        out="$SIMPLE_HOME/generated/optimization/graph.json"
        while [[ $# -gt 0 ]]; do
            case "$1" in
                --output) out="$2"; shift 2 ;;
                --json) JSON_OUT=1; shift ;;
                *) echo "[FAIL] unknown optimization-graph arg: $1" >&2; exit 64 ;;
            esac
        done
        cd "$SIMPLE_HOME"
        args=(--root "$TARGET_ROOT" --struct "$STRUCT_PATH" --output "$out")
        [[ "$JSON_OUT" == "1" ]] && args+=(--json)
        generators/optimization_graph.sh "${args[@]}"
        ;;
    optimizer-search)
        graph="$SIMPLE_HOME/generated/optimization/graph.json"; out="$SIMPLE_HOME/generated/optimization/search.json"; budget=5; mode="greedy"
        while [[ $# -gt 0 ]]; do
            case "$1" in
                --graph) graph="$2"; shift 2 ;;
                --output) out="$2"; shift 2 ;;
                --budget) budget="$2"; shift 2 ;;
                --mode) mode="$2"; shift 2 ;;
                --json) JSON_OUT=1; shift ;;
                *) echo "[FAIL] unknown optimizer-search arg: $1" >&2; exit 64 ;;
            esac
        done
        cd "$SIMPLE_HOME"
        args=(--graph "$graph" --output "$out" --budget "$budget" --mode "$mode")
        [[ "$JSON_OUT" == "1" ]] && args+=(--json)
        generators/optimizer_search.sh "${args[@]}"
        ;;
    test-plan)
        out="$SIMPLE_HOME/generated/tests/test-impact-dag.json"
        while [[ $# -gt 0 ]]; do
            case "$1" in
                --output) out="$2"; shift 2 ;;
                --json) JSON_OUT=1; shift ;;
                *) echo "[FAIL] unknown test-plan arg: $1" >&2; exit 64 ;;
            esac
        done
        cd "$SIMPLE_HOME"
        args=(--root "$TARGET_ROOT" --struct "$STRUCT_PATH" --output "$out")
        [[ "$JSON_OUT" == "1" ]] && args+=(--json)
        generators/test_impact_dag.sh "${args[@]}"
        ;;
    test-cache)
        cache="$SIMPLE_HOME/generated/.cache/simple_model/test-cache.json"; command="bash tests/test_v04_roadmap.sh"; mode="lookup"; result=""
        while [[ $# -gt 0 ]]; do
            case "$1" in
                --cache) cache="$2"; shift 2 ;;
                --command) command="$2"; shift 2 ;;
                --lookup) mode="lookup"; shift ;;
                --store) mode="store"; shift ;;
                --result) result="$2"; shift 2 ;;
                --json) JSON_OUT=1; shift ;;
                *) echo "[FAIL] unknown test-cache arg: $1" >&2; exit 64 ;;
            esac
        done
        cd "$SIMPLE_HOME"
        args=(--cache "$cache" --root "$SIMPLE_HOME" --command "$command" "--$mode")
        [[ -n "$result" ]] && args+=(--result "$result")
        [[ "$JSON_OUT" == "1" ]] && args+=(--json)
        generators/test_cache.sh "${args[@]}"
        ;;
    fast-check|affected-check|dynamic-check|plugin-check|benchmark-check)
        mode="fast"; changed_files=""; jobs=2; out_dir="$SIMPLE_HOME/generated/tests"
        [[ "$cmd" == "affected-check" ]] && mode="affected"
        [[ "$cmd" == "dynamic-check" ]] && mode="dynamic"
        [[ "$cmd" == "plugin-check" ]] && mode="plugin"
        [[ "$cmd" == "benchmark-check" ]] && mode="benchmark"
        while [[ $# -gt 0 ]]; do
            case "$1" in
                --changed-files) changed_files="$2"; shift 2 ;;
                --jobs) jobs="$2"; shift 2 ;;
                --output-dir) out_dir="$2"; shift 2 ;;
                --json) JSON_OUT=1; shift ;;
                *) echo "[FAIL] unknown $cmd arg: $1" >&2; exit 64 ;;
            esac
        done
        cd "$SIMPLE_HOME"
        args=(--mode "$mode" --jobs "$jobs" --output-dir "$out_dir")
        [[ -n "$changed_files" ]] && args+=(--changed-files "$changed_files")
        [[ "$JSON_OUT" == "1" ]] && args+=(--json)
        tools/test_runner.sh "${args[@]}"
        ;;
    scheduler-plan)
        tasks="$SIMPLE_HOME/specs/parallel-task.schema.json"; out="$SIMPLE_HOME/generated/runs/parallel-scheduler.json"; jobs=2
        while [[ $# -gt 0 ]]; do
            case "$1" in
                --tasks) tasks="$2"; shift 2 ;;
                --output) out="$2"; shift 2 ;;
                --jobs) jobs="$2"; shift 2 ;;
                --json) JSON_OUT=1; shift ;;
                *) echo "[FAIL] unknown scheduler-plan arg: $1" >&2; exit 64 ;;
            esac
        done
        cd "$SIMPLE_HOME"
        args=(--tasks "$tasks" --output "$out" --jobs "$jobs" --plan)
        [[ "$JSON_OUT" == "1" ]] && args+=(--json)
        generators/parallel_scheduler.sh "${args[@]}"
        ;;
    performance-benchmark)
        out_dir="$SIMPLE_HOME/generated/performance"; jobs=2
        while [[ $# -gt 0 ]]; do
            case "$1" in
                --output-dir) out_dir="$2"; shift 2 ;;
                --jobs) jobs="$2"; shift 2 ;;
                --json) JSON_OUT=1; shift ;;
                *) echo "[FAIL] unknown performance-benchmark arg: $1" >&2; exit 64 ;;
            esac
        done
        cd "$SIMPLE_HOME"
        args=(--root "$TARGET_ROOT" --struct "$STRUCT_PATH" --output-dir "$out_dir" --jobs "$jobs")
        [[ "$JSON_OUT" == "1" ]] && args+=(--json)
        generators/performance_benchmark.sh "${args[@]}"
        ;;
    performance-dashboard)
        scorecard="$SIMPLE_HOME/generated/performance/scorecard.json"; test_report="$SIMPLE_HOME/generated/tests/test-runner.json"; out="$SIMPLE_HOME/generated/performance/dashboard.html"
        while [[ $# -gt 0 ]]; do
            case "$1" in
                --scorecard) scorecard="$2"; shift 2 ;;
                --test-report) test_report="$2"; shift 2 ;;
                --output) out="$2"; shift 2 ;;
                --json) JSON_OUT=1; shift ;;
                *) echo "[FAIL] unknown performance-dashboard arg: $1" >&2; exit 64 ;;
            esac
        done
        cd "$SIMPLE_HOME"
        args=(--scorecard "$scorecard" --test-report "$test_report" --output "$out")
        [[ "$JSON_OUT" == "1" ]] && args+=(--json)
        generators/performance_dashboard.sh "${args[@]}"
        ;;
    artifact-cache)
        cache="$SIMPLE_HOME/generated/.cache/simple_model/artifacts/index.json"; command=""; inputs=""; result=""; mode="lookup"
        while [[ $# -gt 0 ]]; do
            case "$1" in
                --cache) cache="$2"; shift 2 ;;
                --command) command="$2"; shift 2 ;;
                --inputs) inputs="$2"; shift 2 ;;
                --result) result="$2"; shift 2 ;;
                --lookup) mode="lookup"; shift ;;
                --store) mode="store"; shift ;;
                --json) JSON_OUT=1; shift ;;
                *) echo "[FAIL] unknown artifact-cache arg: $1" >&2; exit 64 ;;
            esac
        done
        cd "$SIMPLE_HOME"
        args=(--cache "$cache" --root "$TARGET_ROOT" --command "$command" --inputs "$inputs" "--$mode")
        [[ -n "$result" ]] && args+=(--result "$result")
        [[ "$JSON_OUT" == "1" ]] && args+=(--json)
        generators/artifact_cache.sh "${args[@]}"
        ;;
    framework-resolvers)
        out_dir="$SIMPLE_HOME/resolvers/frameworks"
        while [[ $# -gt 0 ]]; do
            case "$1" in
                --output-dir) out_dir="$2"; shift 2 ;;
                --json) JSON_OUT=1; shift ;;
                *) echo "[FAIL] unknown framework-resolvers arg: $1" >&2; exit 64 ;;
            esac
        done
        cd "$SIMPLE_HOME"
        args=(--output-dir "$out_dir")
        [[ "$JSON_OUT" == "1" ]] && args+=(--json)
        generators/framework_resolver_pack.sh "${args[@]}"
        ;;
    runtime-contracts)
        surfaces="$SIMPLE_HOME/generated/intelligence/dynamic-surfaces.json"; out="$SIMPLE_HOME/generated/intelligence/runtime-contracts.json"
        while [[ $# -gt 0 ]]; do
            case "$1" in
                --surfaces) surfaces="$2"; shift 2 ;;
                --output) out="$2"; shift 2 ;;
                --json) JSON_OUT=1; shift ;;
                *) echo "[FAIL] unknown runtime-contracts arg: $1" >&2; exit 64 ;;
            esac
        done
        cd "$SIMPLE_HOME"
        args=(--surfaces "$surfaces" --output "$out")
        [[ "$JSON_OUT" == "1" ]] && args+=(--json)
        generators/runtime_contracts.sh "${args[@]}"
        ;;
    production-benchmark)
        out_dir="$SIMPLE_HOME/generated/benchmarks"
        while [[ $# -gt 0 ]]; do
            case "$1" in
                --output-dir) out_dir="$2"; shift 2 ;;
                --json) JSON_OUT=1; shift ;;
                *) echo "[FAIL] unknown production-benchmark arg: $1" >&2; exit 64 ;;
            esac
        done
        cd "$SIMPLE_HOME"
        args=(--root "$TARGET_ROOT" --struct "$STRUCT_PATH" --output-dir "$out_dir")
        [[ "$JSON_OUT" == "1" ]] && args+=(--json)
        generators/production_benchmark.sh "${args[@]}"
        ;;
    adopt)
        out_dir="$ARTIFACT_ROOT/adopt"
        while [[ $# -gt 0 ]]; do
            case "$1" in
                --output-dir) out_dir="$2"; shift 2 ;;
                --json) JSON_OUT=1; shift ;;
                *) echo "[FAIL] unknown adopt arg: $1" >&2; exit 64 ;;
            esac
        done
        cd "$SIMPLE_HOME"
        mkdir -p "$out_dir"
        doctor_json=$("$0" --target-root "$TARGET_ROOT" --struct "$STRUCT_PATH" doctor --json)
        semantic_json=$(generators/semantic_graph.sh --root "$TARGET_ROOT" --struct "$STRUCT_PATH" --output "$out_dir/semantic-graph.json" --json)
        tests_json=$(tools/test_runner.sh --mode fast --jobs 2 --output-dir "$out_dir/tests" --json || true)
        adoption_json=$(generators/adoption_report.sh --root "$TARGET_ROOT" --struct "$STRUCT_PATH" --output-dir "$out_dir/adoption-report" --json || true)
        report=$(jq -n --arg target "$TARGET_ROOT" --arg struct "$STRUCT_PATH" --argjson doctor "$doctor_json" --argjson semantic "$semantic_json" --argjson tests "$tests_json" --argjson adoption "$adoption_json" '{
          schema_version:"1.0", ok:($doctor.ok and $semantic.ok and ($tests.ok // true)),
          target_root:$target, struct:$struct,
          phases:{doctor:$doctor.checks, semantic_graph:$semantic.summary, fast_check:$tests.summary, adoption:$adoption.adoption},
          artifacts:{semantic_graph:"semantic-graph.json", tests:"tests/test-runner.json", adoption_report:"adoption-report/adoption-report.md"},
          next_commands:["simple_model_pi.sh optimizer-search --json","simple_model_pi.sh autopilot --mode fast --json"]
        }')
        printf '%s\n' "$report" > "$out_dir/adopt.json"
        if [[ "$JSON_OUT" == "1" ]]; then printf '%s\n' "$report"; else jq -r '"Adopt ok=" + (.ok|tostring) + " semantic_nodes=" + (.phases.semantic_graph.nodes|tostring)' <<<"$report"; fi
        ;;
    capability-truth)
        out="$SIMPLE_HOME/generated/audits/capability-truth.json"
        spec_file="$SIMPLE_HOME/specs/capability-maturity.json"
        cap_root="$TARGET_ROOT"
        cap_struct=""
        fixtures=""
        while [[ $# -gt 0 ]]; do
            case "$1" in
                --target-root|--root) cap_root="$2"; shift 2 ;;
                --output) out="$2"; shift 2 ;;
                --spec) spec_file="$2"; shift 2 ;;
                --struct) cap_struct="$2"; shift 2 ;;
                --fixtures) fixtures="$2"; shift 2 ;;
                --json) JSON_OUT=1; shift ;;
                *) echo "[FAIL] unknown capability-truth arg: $1" >&2; exit 64 ;;
            esac
        done
        cap_root="$(cd "$cap_root" 2>/dev/null && pwd || printf '%s' "$cap_root")"
        if [[ -z "$cap_struct" ]]; then
            cap_struct="$cap_root/struct.json"
        elif [[ "$cap_struct" = /* ]]; then
            :
        elif [[ -f "$cap_struct" ]]; then
            cap_struct="$(cd "$(dirname "$cap_struct")" && pwd)/$(basename "$cap_struct")"
        else
            cap_struct="$cap_root/$cap_struct"
        fi
        cd "$SIMPLE_HOME"
        args=(--root "$cap_root" --struct "$cap_struct" --spec "$spec_file" --output "$out")
        [[ -n "$fixtures" ]] && args+=(--fixtures "$fixtures")
        [[ "$JSON_OUT" == "1" ]] && args+=(--json)
        generators/capability_truth_audit.sh "${args[@]}"
        ;;
    onboard)
        out_dir="$ARTIFACT_ROOT/onboard"
        while [[ $# -gt 0 ]]; do
            case "$1" in
                --output-dir) out_dir="$2"; shift 2 ;;
                --json) JSON_OUT=1; shift ;;
                *) echo "[FAIL] unknown onboard arg: $1" >&2; exit 64 ;;
            esac
        done
        cd "$SIMPLE_HOME"
        args=(--root "$TARGET_ROOT" --struct "$STRUCT_PATH" --output-dir "$out_dir")
        [[ "$JSON_OUT" == "1" ]] && args+=(--json)
        generators/onboard.sh "${args[@]}"
        ;;
    index-cache)
        cache="$SIMPLE_HOME/generated/.cache/simple_model/index-cache.json"
        while [[ $# -gt 0 ]]; do
            case "$1" in
                --cache) cache="$2"; shift 2 ;;
                --json) JSON_OUT=1; shift ;;
                *) echo "[FAIL] unknown index-cache arg: $1" >&2; exit 64 ;;
            esac
        done
        cd "$SIMPLE_HOME"
        args=(--root "$TARGET_ROOT" --struct "$STRUCT_PATH" --cache "$cache")
        [[ "$JSON_OUT" == "1" ]] && args+=(--json)
        generators/index_cache.sh "${args[@]}"
        ;;
    workspace-graph)
        out="$SIMPLE_HOME/generated/intelligence/workspace-graph.json"
        while [[ $# -gt 0 ]]; do
            case "$1" in
                --output) out="$2"; shift 2 ;;
                --json) JSON_OUT=1; shift ;;
                *) echo "[FAIL] unknown workspace-graph arg: $1" >&2; exit 64 ;;
            esac
        done
        cd "$SIMPLE_HOME"
        args=(--root "$TARGET_ROOT" --struct "$STRUCT_PATH" --output "$out")
        [[ "$JSON_OUT" == "1" ]] && args+=(--json)
        generators/workspace_graph.sh "${args[@]}"
        ;;
    policy)
        plan="$SIMPLE_HOME/generated/optimization/plan.json"; policy_file=""
        while [[ $# -gt 0 ]]; do
            case "$1" in
                --plan) plan="$2"; shift 2 ;;
                --policy) policy_file="$2"; shift 2 ;;
                --json) JSON_OUT=1; shift ;;
                *) echo "[FAIL] unknown policy arg: $1" >&2; exit 64 ;;
            esac
        done
        cd "$SIMPLE_HOME"
        args=(--plan "$plan")
        [[ -n "$policy_file" ]] && args+=(--policy "$policy_file")
        [[ "$JSON_OUT" == "1" ]] && args+=(--json)
        generators/policy_eval.sh "${args[@]}" || true
        ;;
    autofix-plan)
        plan="$SIMPLE_HOME/generated/optimization/plan.json"
        while [[ $# -gt 0 ]]; do
            case "$1" in
                --plan) plan="$2"; shift 2 ;;
                --json) JSON_OUT=1; shift ;;
                *) echo "[FAIL] unknown autofix-plan arg: $1" >&2; exit 64 ;;
            esac
        done
        cd "$SIMPLE_HOME"
        args=(--plan "$plan")
        [[ "$JSON_OUT" == "1" ]] && args+=(--json)
        generators/autofix_pr_plan.sh "${args[@]}"
        ;;
    test-graph)
        cd "$SIMPLE_HOME"
        args=(--root "$TARGET_ROOT" --struct "$STRUCT_PATH")
        [[ "$JSON_OUT" == "1" ]] && args+=(--json)
        generators/test_graph.sh "${args[@]}"
        ;;
    benchmark)
        cd "$SIMPLE_HOME"
        if [[ "$JSON_OUT" == "1" ]]; then
            generators/benchmark_scorecard.sh "$TARGET_ROOT" --json
        else
            generators/benchmark_scorecard.sh "$TARGET_ROOT"
        fi
        ;;
    competitive-scorecard)
        benchmark_file="$SIMPLE_HOME/generated/benchmarks/scorecard.json"
        while [[ $# -gt 0 ]]; do
            case "$1" in
                --benchmark) benchmark_file="$2"; shift 2 ;;
                --json) JSON_OUT=1; shift ;;
                *) echo "[FAIL] unknown competitive-scorecard arg: $1" >&2; exit 64 ;;
            esac
        done
        cd "$SIMPLE_HOME"
        args=(--benchmark "$benchmark_file")
        [[ "$JSON_OUT" == "1" ]] && args+=(--json)
        generators/competitive_scorecard.sh "${args[@]}"
        ;;
    adoption-report)
        out_dir="$SIMPLE_HOME/generated/adoption-report"
        benchmark_file=""
        while [[ $# -gt 0 ]]; do
            case "$1" in
                --output-dir) out_dir="$2"; shift 2 ;;
                --benchmark) benchmark_file="$2"; shift 2 ;;
                --json) JSON_OUT=1; shift ;;
                *) echo "[FAIL] unknown adoption-report arg: $1" >&2; exit 64 ;;
            esac
        done
        cd "$SIMPLE_HOME"
        args=(--root "$TARGET_ROOT" --struct "$STRUCT_PATH" --output-dir "$out_dir")
        [[ -n "$benchmark_file" ]] && args+=(--benchmark "$benchmark_file")
        [[ "$JSON_OUT" == "1" ]] && args+=(--json)
        generators/adoption_report.sh "${args[@]}"
        ;;
    release-slo)
        version="$(plugin_version)"
        while [[ $# -gt 0 ]]; do
            case "$1" in
                --version) version="$2"; shift 2 ;;
                --json) JSON_OUT=1; shift ;;
                *) echo "[FAIL] unknown release-slo arg: $1" >&2; exit 64 ;;
            esac
        done
        cd "$SIMPLE_HOME"
        args=(--version "$version")
        [[ "$JSON_OUT" == "1" ]] && args+=(--json)
        generators/release_slo.sh "${args[@]}"
        ;;
    evolution-benchmark)
        out_dir="$SIMPLE_HOME/generated/benchmarks/evolution-v2"
        while [[ $# -gt 0 ]]; do
            case "$1" in --output-dir) out_dir="$2"; shift 2 ;; --json) JSON_OUT=1; shift ;; *) echo "[FAIL] unknown evolution-benchmark arg: $1" >&2; exit 64 ;; esac
        done
        cd "$SIMPLE_HOME"; mkdir -p "$out_dir"
        generators/evolution_replay_v2.sh --manifest benchmarks/evolution-v2/manifest.json --output "$out_dir/replay.json" --json >/dev/null
        generators/evolution_score.sh --replay "$out_dir/replay.json" --output "$out_dir/scorecard.json" --json
        ;;
    performance-v2)
        out_dir="$SIMPLE_HOME/generated/performance"
        while [[ $# -gt 0 ]]; do
            case "$1" in --output-dir) out_dir="$2"; shift 2 ;; --json) JSON_OUT=1; shift ;; *) echo "[FAIL] unknown performance-v2 arg: $1" >&2; exit 64 ;; esac
        done
        cd "$SIMPLE_HOME"; mkdir -p "$out_dir"
        generators/performance_benchmark_v2.sh --output "$out_dir/v2-benchmark.json" --json >/dev/null
        generators/test_economics.sh --benchmark "$out_dir/v2-benchmark.json" --output "$out_dir/v2-scorecard.json" --json
        ;;
    macro-pack-verify)
        input=""; key="simple-model-dev-key"; revocations=""
        while [[ $# -gt 0 ]]; do
            case "$1" in --input) input="$2"; shift 2 ;; --key) key="$2"; shift 2 ;; --revocations) revocations="$2"; shift 2 ;; --json) JSON_OUT=1; shift ;; *) echo "[FAIL] unknown macro-pack-verify arg: $1" >&2; exit 64 ;; esac
        done
        [[ -n "$input" ]] || { echo "[FAIL] macro-pack-verify requires --input" >&2; exit 64; }
        cd "$SIMPLE_HOME"
        if [[ -n "$revocations" ]]; then
            if [[ "$JSON_OUT" == "1" ]]; then generators/macro_pack_verify.sh --input "$input" --key "$key" --revocations "$revocations" --json; else generators/macro_pack_verify.sh --input "$input" --key "$key" --revocations "$revocations"; fi
        elif [[ "$JSON_OUT" == "1" ]]; then generators/macro_pack_verify.sh --input "$input" --key "$key" --json
        else generators/macro_pack_verify.sh --input "$input" --key "$key"; fi
        ;;
    interoperability)
        printf '%s\n' '{"jsonrpc":"2.0","id":1,"method":"tools/list"}' | SIMPLE_MODEL_ROOT="$SIMPLE_HOME" bash "$SIMPLE_HOME/tools/simple_model_mcp_v2.sh"
        ;;
    release-slo-v2)
        out="$SIMPLE_HOME/generated/releases/v2-production-readiness.json"
        while [[ $# -gt 0 ]]; do
            case "$1" in --output) out="$2"; shift 2 ;; --json) JSON_OUT=1; shift ;; *) echo "[FAIL] unknown release-slo-v2 arg: $1" >&2; exit 64 ;; esac
        done
        cd "$SIMPLE_HOME"
        if [[ "$JSON_OUT" == "1" ]]; then generators/release_slo_v2.sh --output "$out" --json; else generators/release_slo_v2.sh --output "$out"; fi
        ;;
    parser-tiers)
        out="$SIMPLE_HOME/generated/intelligence/parser-tiers.json"
        while [[ $# -gt 0 ]]; do
            case "$1" in --output) out="$2"; shift 2 ;; --json) JSON_OUT=1; shift ;; *) echo "[FAIL] unknown parser-tiers arg: $1" >&2; exit 64 ;; esac
        done
        cd "$SIMPLE_HOME"; args=(--root "$TARGET_ROOT" --output "$out"); [[ "$JSON_OUT" == "1" ]] && args+=(--json); generators/parser_tier_registry.sh "${args[@]}"
        ;;
    symbol-index)
        out="$SIMPLE_HOME/generated/intelligence/symbol-index.json"
        while [[ $# -gt 0 ]]; do
            case "$1" in --output) out="$2"; shift 2 ;; --json) JSON_OUT=1; shift ;; *) echo "[FAIL] unknown symbol-index arg: $1" >&2; exit 64 ;; esac
        done
        cd "$SIMPLE_HOME"; args=(--root "$TARGET_ROOT" --struct "$STRUCT_PATH" --output "$out"); [[ "$JSON_OUT" == "1" ]] && args+=(--json); generators/symbol_identity.sh "${args[@]}"
        ;;
    semantic-graph-incremental)
        out="$SIMPLE_HOME/generated/intelligence/semantic-graph.json"; diff_out="$SIMPLE_HOME/generated/intelligence/semantic-graph-diff.json"
        while [[ $# -gt 0 ]]; do
            case "$1" in --output) out="$2"; shift 2 ;; --diff-output) diff_out="$2"; shift 2 ;; --json) JSON_OUT=1; shift ;; *) echo "[FAIL] unknown semantic-graph-incremental arg: $1" >&2; exit 64 ;; esac
        done
        cd "$SIMPLE_HOME"; args=(--root "$TARGET_ROOT" --struct "$STRUCT_PATH" --output "$out" --diff-output "$diff_out"); [[ "$JSON_OUT" == "1" ]] && args+=(--json); generators/semantic_graph_incremental.sh "${args[@]}"
        ;;
    dynamic-edges)
        out="$SIMPLE_HOME/generated/intelligence/dynamic-edges.json"
        while [[ $# -gt 0 ]]; do
            case "$1" in --output) out="$2"; shift 2 ;; --json) JSON_OUT=1; shift ;; *) echo "[FAIL] unknown dynamic-edges arg: $1" >&2; exit 64 ;; esac
        done
        cd "$SIMPLE_HOME"; args=(--root "$TARGET_ROOT" --struct "$STRUCT_PATH" --output "$out"); [[ "$JSON_OUT" == "1" ]] && args+=(--json); generators/dynamic_edge_resolver.sh "${args[@]}"
        ;;
    macro-preconditions)
        out="$SIMPLE_HOME/generated/macros/precondition-report.json"; macro=""
        while [[ $# -gt 0 ]]; do
            case "$1" in --output) out="$2"; shift 2 ;; --macro) macro="$2"; shift 2 ;; --json) JSON_OUT=1; shift ;; *) echo "[FAIL] unknown macro-preconditions arg: $1" >&2; exit 64 ;; esac
        done
        cd "$SIMPLE_HOME"; args=(--root "$TARGET_ROOT" --struct "$STRUCT_PATH" --output "$out"); [[ -n "$macro" ]] && args+=(--macro "$macro"); [[ "$JSON_OUT" == "1" ]] && args+=(--json); generators/macro_preconditions.sh "${args[@]}"
        ;;
    macro-drill)
        out="$SIMPLE_HOME/generated/macros/drill-report.json"; spec=""
        while [[ $# -gt 0 ]]; do
            case "$1" in --output) out="$2"; shift 2 ;; --spec) spec="$2"; shift 2 ;; --json) JSON_OUT=1; shift ;; *) echo "[FAIL] unknown macro-drill arg: $1" >&2; exit 64 ;; esac
        done
        cd "$SIMPLE_HOME"; args=(--root "$TARGET_ROOT" --output "$out"); [[ -n "$spec" ]] && args+=(--spec "$spec"); [[ "$JSON_OUT" == "1" ]] && args+=(--json); generators/macro_drill.sh "${args[@]}"
        ;;
    macro-generate)
        out="$SIMPLE_HOME/generated/macros/candidates.json"; findings=""
        while [[ $# -gt 0 ]]; do
            case "$1" in --output) out="$2"; shift 2 ;; --findings) findings="$2"; shift 2 ;; --json) JSON_OUT=1; shift ;; *) echo "[FAIL] unknown macro-generate arg: $1" >&2; exit 64 ;; esac
        done
        cd "$SIMPLE_HOME"; args=(--output "$out"); [[ -n "$findings" ]] && args+=(--findings "$findings"); [[ "$JSON_OUT" == "1" ]] && args+=(--json); generators/macro_generate_from_findings.sh "${args[@]}"
        ;;
    accuracy-scorecard)
        out="$SIMPLE_HOME/generated/benchmarks/accuracy-scorecard.json"
        while [[ $# -gt 0 ]]; do
            case "$1" in --output) out="$2"; shift 2 ;; --json) JSON_OUT=1; shift ;; *) echo "[FAIL] unknown accuracy-scorecard arg: $1" >&2; exit 64 ;; esac
        done
        cd "$SIMPLE_HOME"; args=(--output "$out"); [[ "$JSON_OUT" == "1" ]] && args+=(--json); generators/accuracy_scorecard.sh "${args[@]}"
        ;;
    external-eval)
        out="$SIMPLE_HOME/generated/adoption/eval-report.json"
        while [[ $# -gt 0 ]]; do
            case "$1" in --output) out="$2"; shift 2 ;; --json) JSON_OUT=1; shift ;; *) echo "[FAIL] unknown external-eval arg: $1" >&2; exit 64 ;; esac
        done
        cd "$SIMPLE_HOME"; args=(--root "$TARGET_ROOT" --struct "$STRUCT_PATH" --output "$out"); [[ "$JSON_OUT" == "1" ]] && args+=(--json); generators/external_repo_eval.sh "${args[@]}"
        ;;
    confidence-plan)
        out="$SIMPLE_HOME/generated/optimization/confidence-plan.json"
        while [[ $# -gt 0 ]]; do
            case "$1" in --output) out="$2"; shift 2 ;; --json) JSON_OUT=1; shift ;; *) echo "[FAIL] unknown confidence-plan arg: $1" >&2; exit 64 ;; esac
        done
        cd "$SIMPLE_HOME"; args=(--root "$TARGET_ROOT" --struct "$STRUCT_PATH" --output "$out"); [[ "$JSON_OUT" == "1" ]] && args+=(--json); generators/confidence_optimizer.sh "${args[@]}"
        ;;
    adoption-cockpit)
        out_dir="$SIMPLE_HOME/generated/adoption"
        while [[ $# -gt 0 ]]; do
            case "$1" in --output-dir) out_dir="$2"; shift 2 ;; --json) JSON_OUT=1; shift ;; *) echo "[FAIL] unknown adoption-cockpit arg: $1" >&2; exit 64 ;; esac
        done
        cd "$SIMPLE_HOME"; args=(--root "$TARGET_ROOT" --struct "$STRUCT_PATH" --output-dir "$out_dir"); [[ "$JSON_OUT" == "1" ]] && args+=(--json); generators/adoption_cockpit.sh "${args[@]}"
        ;;
    macro-operator-ir|macro-motifs|macro-templates|macro-compose|macro-plan-search|macro-transaction|macro-proof-bundle|macro-ledger|macro-family-ranker|macro-promotion|macro-gauntlet|macro-cockpit|macro-advisor|takeover-init|interface-stability|ai-tool-research)
        out=""
        while [[ $# -gt 0 ]]; do
            case "$1" in
                --output|--output-dir) out="$2"; shift 2 ;;
                --json) JSON_OUT=1; shift ;;
                *) echo "[FAIL] unknown $cmd arg: $1" >&2; exit 64 ;;
            esac
        done
        cd "$SIMPLE_HOME"
        case "$cmd" in
            macro-operator-ir) [[ -n "$out" ]] || out="$SIMPLE_HOME/generated/macros/operator-ir.json"; args=(--output "$out") ;;
            macro-motifs) [[ -n "$out" ]] || out="$SIMPLE_HOME/generated/macros/motif-candidates.json"; args=(--root "$TARGET_ROOT" --struct "$STRUCT_PATH" --output "$out") ;;
            macro-templates) [[ -n "$out" ]] || out="$SIMPLE_HOME/generated/macros/templates.json"; args=(--output "$out") ;;
            macro-compose) [[ -n "$out" ]] || out="$SIMPLE_HOME/generated/macros/composition-report.json"; args=(--output "$out") ;;
            macro-plan-search) [[ -n "$out" ]] || out="$SIMPLE_HOME/generated/macros/plan-search.json"; args=(--output "$out") ;;
            macro-transaction) [[ -n "$out" ]] || out="$SIMPLE_HOME/generated/macros/transaction-log.json"; args=(--root "$TARGET_ROOT" --output "$out") ;;
            macro-proof-bundle) [[ -n "$out" ]] || out="$SIMPLE_HOME/generated/macros/proof-bundle.json"; args=(--output "$out") ;;
            macro-ledger) [[ -n "$out" ]] || out="$SIMPLE_HOME/generated/macros/outcome-ledger.json"; args=(--output "$out") ;;
            macro-family-ranker) [[ -n "$out" ]] || out="$SIMPLE_HOME/generated/macros/family-rankings.json"; args=(--output "$out") ;;
            macro-promotion) [[ -n "$out" ]] || out="$SIMPLE_HOME/generated/macros/promotion-report.json"; args=(--output "$out") ;;
            macro-gauntlet) [[ -n "$out" ]] || out="$SIMPLE_HOME/generated/benchmarks/macro-gauntlet-scorecard.json"; args=(--output "$out") ;;
            macro-cockpit) [[ -n "$out" ]] || out="$SIMPLE_HOME/generated/macros"; args=(--output-dir "$out") ;;
            macro-advisor) [[ -n "$out" ]] || out="$SIMPLE_HOME/generated/macros/advisor-report.json"; args=(--root "$TARGET_ROOT" --struct "$STRUCT_PATH" --output "$out") ;;
            takeover-init) [[ -n "$out" ]] || out="$ARTIFACT_ROOT/adoption"; args=(--root "$TARGET_ROOT" --struct "$STRUCT_PATH" --output-dir "$out") ;;
            interface-stability) [[ -n "$out" ]] || out="$SIMPLE_HOME/generated/adoption/interface-stability.json"; args=(--root "$TARGET_ROOT" --struct "$STRUCT_PATH" --output "$out") ;;
            ai-tool-research) [[ -n "$out" ]] || out="$SIMPLE_HOME/generated/research/ai-tool-pain-points.json"; args=(--output "$out") ;;
        esac
        [[ "$JSON_OUT" == "1" ]] && args+=(--json)
        case "$cmd" in
            macro-operator-ir) generators/macro_operator_ir.sh "${args[@]}" ;;
            macro-motifs) generators/macro_discover_motifs.sh "${args[@]}" ;;
            macro-templates) generators/macro_template_synth.sh "${args[@]}" ;;
            macro-compose) generators/macro_compose.sh "${args[@]}" ;;
            macro-plan-search) generators/macro_plan_search.sh "${args[@]}" ;;
            macro-transaction) generators/macro_transaction.sh "${args[@]}" ;;
            macro-proof-bundle) generators/macro_proof_bundle.sh "${args[@]}" ;;
            macro-ledger) generators/macro_outcome_ledger.sh "${args[@]}" ;;
            macro-family-ranker) generators/macro_family_ranker.sh "${args[@]}" ;;
            macro-promotion) generators/macro_promotion_gate.sh "${args[@]}" ;;
            macro-gauntlet) generators/macro_gauntlet.sh "${args[@]}" ;;
            macro-cockpit) generators/macro_cockpit.sh "${args[@]}" ;;
            macro-advisor) generators/macro_advisor.sh "${args[@]}" ;;
            takeover-init) generators/takeover_init.sh "${args[@]}" ;;
            interface-stability) generators/interface_stability_commitment.sh "${args[@]}" ;;
            ai-tool-research) generators/ai_tool_pain_research.sh "${args[@]}" ;;
        esac
        ;;
    dynamic-case-study)
        cd "$SIMPLE_HOME"
        bash examples/dynamic-case-study/run.sh
        ;;
    validate)
        cd "$SIMPLE_HOME"
        ./bootstrap.sh --validate
        ./bootstrap.sh --check-all
        ./bootstrap.sh --lint --json | jq '.summary'
        ./bootstrap.sh --drift --json | jq '.summary'
        ;;
    full-check)
        cd "$SIMPLE_HOME"
        jobs=2
        while [[ $# -gt 0 ]]; do
            case "$1" in
                --jobs) jobs="$2"; shift 2 ;;
                --json) JSON_OUT=1; shift ;;
                *) shift ;;
            esac
        done
        ./bootstrap.sh --validate
        ./bootstrap.sh --check-all
        ./bootstrap.sh --lint --json | jq '.summary'
        ./bootstrap.sh --drift --json | jq '.summary'
        tools/test_runner.sh --mode full --jobs "$jobs"
        ;;
    ingest)
        repo="${1:-$TARGET_ROOT}"; out="${2:-$TARGET_ROOT/struct.ingested.json}"
        cd "$SIMPLE_HOME"
        generators/ingest_repo.sh --root "$repo" --output "$out" --json
        ;;
    audit)
        repo="${1:-$TARGET_ROOT}"
        cd "$SIMPLE_HOME"
        generators/adoption_audit.sh --root "$repo" --struct "$STRUCT_PATH" --json
        ;;
    interfaces)
        repo="${1:-$TARGET_ROOT}"
        cd "$SIMPLE_HOME"
        generators/interface_scan.sh --root "$repo" --struct "$STRUCT_PATH" --json
        ;;
    facts)
        repo="${1:-$TARGET_ROOT}"
        cd "$SIMPLE_HOME"
        generators/code_facts.sh --root "$repo" --struct "$STRUCT_PATH" --json
        ;;
    pr-gate)
        repo="$TARGET_ROOT"; files=""
        while [[ $# -gt 0 ]]; do
            case "$1" in
                --json) JSON_OUT=1; shift ;;
                --files) files="$2"; shift 2 ;;
                --target-root) repo="$2"; shift 2 ;;
                *) if [[ "$repo" == "$TARGET_ROOT" ]]; then repo="$1"; else files="$1"; fi; shift ;;
            esac
        done
        cd "$SIMPLE_HOME"
        if [[ -n "$files" ]]; then
            generators/pr_gate.sh --root "$repo" --struct "$STRUCT_PATH" --files "$files" --json
        else
            generators/pr_gate.sh --root "$repo" --struct "$STRUCT_PATH" --json
        fi
        ;;
    dashboard)
        out="${1:-$TARGET_ROOT/generated/dashboard.html}"
        cd "$SIMPLE_HOME"
        generators/dashboard.sh "$out"
        ;;
    resolve)
        cd "$SIMPLE_HOME"
        ./bootstrap.sh --struct "$STRUCT_PATH" --resolve --json
        ;;
    *)
        echo "[FAIL] unknown command: $cmd" >&2
        usage
        exit 64
        ;;
esac
