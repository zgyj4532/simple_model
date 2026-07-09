#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MANIFEST_FILE="${SCRIPT_DIR}/../references/command-manifest.json"

usage() {
    cat <<'USAGE'
simple_model_pi.sh [--target-root PATH] [--struct PATH] <command> [args]

Global options:
  --target-root PATH       Repository to analyze. Defaults to current directory.
  --struct PATH            struct.json to use. Defaults to <target-root>/struct.json, then simple_model/struct.json.
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
SIMPLE_HOME="$(find_simple_model_home)"
TARGET_ROOT="$(cd "$TARGET_ROOT" 2>/dev/null && pwd || printf '%s' "$TARGET_ROOT")"
if [[ -z "$STRUCT_PATH" ]]; then
    if [[ -f "$TARGET_ROOT/struct.json" ]]; then
        STRUCT_PATH="$TARGET_ROOT/struct.json"
    else
        STRUCT_PATH="$SIMPLE_HOME/struct.json"
    fi
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
        out_dir="$SIMPLE_HOME/generated/optimization"
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
    validate)
        cd "$SIMPLE_HOME"
        ./bootstrap.sh --validate
        ./bootstrap.sh --check-all
        ./bootstrap.sh --lint --json | jq '.summary'
        ./bootstrap.sh --drift --json | jq '.summary'
        ;;
    full-check)
        cd "$SIMPLE_HOME"
        ./bootstrap.sh --validate
        ./bootstrap.sh --check-all
        ./bootstrap.sh --lint --json | jq '.summary'
        ./bootstrap.sh --drift --json | jq '.summary'
        for t in tests/test_*.sh; do bash "$t" || exit 1; done
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
        repo="${1:-$TARGET_ROOT}"; files="${2:-}"
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
