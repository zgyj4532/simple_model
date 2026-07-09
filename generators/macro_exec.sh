#!/usr/bin/env bash
set -euo pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLAN="generated/optimization/plan.json"
MODE="dry-run"
OUT_DIR="generated/optimization"
JSON_OUT=0
ONLY_MACRO=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --plan) PLAN="$2"; shift 2 ;;
        --dry-run) MODE="dry-run"; shift ;;
        --apply) MODE="apply"; shift ;;
        --output-dir) OUT_DIR="$2"; shift 2 ;;
        --macro) ONLY_MACRO="$2"; shift 2 ;;
        --json) JSON_OUT=1; shift ;;
        -h|--help)
            echo "macro_exec.sh --plan generated/optimization/plan.json [--dry-run|--apply] [--macro <id>] [--json]"
            exit 0
            ;;
        *) echo "unknown arg: $1" >&2; exit 64 ;;
    esac
done

command -v jq >/dev/null 2>&1 || { echo "[FAIL] missing jq" >&2; exit 2; }
[[ -f "$PLAN" ]] || { echo "[FAIL] plan not found: $PLAN" >&2; exit 2; }
jq empty "$PLAN"
mkdir -p "$OUT_DIR/patches" "$OUT_DIR/backups"

ROOT="$(jq -r '.root' "$PLAN")"
STRUCT="$(jq -r '.struct' "$PLAN")"
[[ -d "$ROOT" ]] || { echo "[FAIL] root not found: $ROOT" >&2; exit 2; }
[[ -f "$STRUCT" ]] || { echo "[FAIL] struct not found: $STRUCT" >&2; exit 2; }

hash_file() {
    if command -v sha256sum >/dev/null 2>&1; then
        sha256sum "$1" | awk '{print $1}'
    else
        shasum -a 256 "$1" | awk '{print $1}'
    fi
}

backup_file() {
    local file="$1"
    local rel safe dest
    rel="$(realpath_rel "$file")"
    safe="$(printf '%s' "$rel" | tr '/ ' '__')"
    dest="$OUT_DIR/backups/$safe"
    mkdir -p "$(dirname "$dest")"
    cp "$file" "$dest"
    printf '%s\n' "$dest"
}

realpath_rel() {
    local file="$1"
    case "$file" in
        "$ROOT"/*) printf '%s\n' "${file#"$ROOT"/}" ;;
        *) printf '%s\n' "$file" ;;
    esac
}

atomic_write() {
    local target="$1" tmp
    tmp="$(mktemp)"
    cat > "$tmp"
    mv "$tmp" "$target"
}

plan_patch() {
    local name="$1" body="$2"
    printf '%s\n' "$body" > "$OUT_DIR/patches/$name.txt"
}

validate_struct() {
    jq empty "$STRUCT"
}

macro_split_struct_include() {
    local action="$1"
    local module_count includes_count module_dir patch backup before after wrote
    module_count=$(jq '.modules // [] | length' "$STRUCT")
    includes_count=$(jq '.includes // [] | length' "$STRUCT")
    if [[ "$includes_count" -gt 0 || "$module_count" -le 1 ]]; then
        jq -n --arg status "skipped" --arg reason "struct is already split or has one module" '{status:$status, reason:$reason, writes:[]}'
        return 0
    fi

    module_dir="$(dirname "$STRUCT")/struct.modules"
    patch="Create struct.modules/<module>.json fragments and replace root modules with includes."
    if [[ "$MODE" == "dry-run" ]]; then
        plan_patch "split_struct_include" "$patch"
        jq -n --arg status "dry-run" --arg patch "$OUT_DIR/patches/split_struct_include.txt" '{status:$status, patch:$patch, writes:[]}'
        return 0
    fi

    backup=$(backup_file "$STRUCT")
    before=$(hash_file "$STRUCT")
    mkdir -p "$module_dir"
    jq -c '.modules[]' "$STRUCT" | while IFS= read -r module; do
        name=$(jq -r '.name' <<<"$module")
        jq -n --argjson root "$(jq 'del(.modules, .includes, ._resolved)' "$STRUCT")" --argjson module "$module" '$root + {modules:[$module]}' \
          > "$module_dir/$name.json"
    done
    jq '. as $root | del(.modules, ._resolved) + {includes:(($root.modules // []) | map("struct.modules/" + .name + ".json"))}' "$STRUCT" | atomic_write "$STRUCT"
    validate_struct
    after=$(hash_file "$STRUCT")
    wrote=$(find "$module_dir" -maxdepth 1 -type f -name '*.json' | sort | sed "s#^$(dirname "$STRUCT")/##" | jq -R -s 'split("\n")[:-1]')
    jq -n --arg status "applied" --arg backup "$backup" --arg before "$before" --arg after "$after" --argjson writes "$wrote" '{status:$status, backup:$backup, before_sha256:$before, after_sha256:$after, writes:(["struct.json"] + $writes)}'
}

macro_normalize_component_exports() {
    local action="$1"
    local component exports patch backup before after
    component=$(jq -r '.target.component' <<<"$action")
    exports=$(jq -c '.evidence.discovered_exports // []' <<<"$action")
    patch="Set exports for component $component to discovered public interface symbols: $(jq -r 'join(",")' <<<"$exports")"
    if [[ "$MODE" == "dry-run" ]]; then
        plan_patch "normalize_component_exports_$component" "$patch"
        jq -n --arg status "dry-run" --arg patch "$OUT_DIR/patches/normalize_component_exports_$component.txt" '{status:$status, patch:$patch, writes:[]}'
        return 0
    fi
    backup=$(backup_file "$STRUCT")
    before=$(hash_file "$STRUCT")
    jq --arg comp "$component" --argjson exports "$exports" '
      .modules |= map(.components |= map(if .name == $comp then .exports = ($exports | unique) else . end))
    ' "$STRUCT" | atomic_write "$STRUCT"
    validate_struct
    after=$(hash_file "$STRUCT")
    jq -n --arg status "applied" --arg backup "$backup" --arg before "$before" --arg after "$after" '{status:$status, backup:$backup, before_sha256:$before, after_sha256:$after, writes:["struct.json"]}'
}

macro_sync_struct_imports_from_code_facts() {
    local action="$1"
    local component target imports patch backup before after
    component=$(jq -r '.target.component' <<<"$action")
    target=$(jq -r '.target.target' <<<"$action")
    imports=$(jq -c --arg comp "$component" --arg target "$target" '
      [.modules[].components[] | select(.name == $comp) | (.imports // [])][0] + [$target] | unique
    ' "$STRUCT")
    patch="Add missing struct import for component $component -> $target."
    if [[ "$MODE" == "dry-run" ]]; then
        plan_patch "sync_struct_imports_${component}_${target}" "$patch"
        jq -n --arg status "dry-run" --arg patch "$OUT_DIR/patches/sync_struct_imports_${component}_${target}.txt" '{status:$status, patch:$patch, writes:[]}'
        return 0
    fi
    backup=$(backup_file "$STRUCT")
    before=$(hash_file "$STRUCT")
    jq --arg comp "$component" --argjson imports "$imports" '
      .modules |= map(.components |= map(if .name == $comp then .imports = $imports else . end))
    ' "$STRUCT" | atomic_write "$STRUCT"
    validate_struct
    after=$(hash_file "$STRUCT")
    jq -n --arg status "applied" --arg backup "$backup" --arg before "$before" --arg after "$after" '{status:$status, backup:$backup, before_sha256:$before, after_sha256:$after, writes:["struct.json"]}'
}

run_action() {
    local action="$1" macro_id status result ok=true message=""
    macro_id=$(jq -r '.macro_id' <<<"$action")
    if [[ -n "$ONLY_MACRO" && "$macro_id" != "$ONLY_MACRO" ]]; then
        jq -n --arg macro_id "$macro_id" '{macro_id:$macro_id, ok:true, status:"skipped", reason:"filtered"}'
        return 0
    fi
    if [[ "$MODE" == "apply" ]] && [[ "$(jq -r '.auto_apply' <<<"$action")" != "true" ]]; then
        jq -n --arg macro_id "$macro_id" '{macro_id:$macro_id, ok:true, status:"skipped", reason:"macro is not auto_apply"}'
        return 0
    fi
    set +e
    case "$macro_id" in
        split_struct_include) result=$(macro_split_struct_include "$action" 2>&1); status=$? ;;
        normalize_component_exports) result=$(macro_normalize_component_exports "$action" 2>&1); status=$? ;;
        sync_struct_imports_from_code_facts) result=$(macro_sync_struct_imports_from_code_facts "$action" 2>&1); status=$? ;;
        *) result="unknown macro: $macro_id"; status=64 ;;
    esac
    set -e
    [[ $status -eq 0 ]] || ok=false
    if [[ "$ok" == "true" ]]; then
        jq -n --argjson action "$action" --argjson result "$result" '{macro_id:$action.macro_id, ok:true, status:$result.status, action:$action, result:$result}'
    else
        jq -n --argjson action "$action" --arg evidence "$result" --argjson exit_code "$status" '{macro_id:$action.macro_id, ok:false, status:"failed", action:$action, exit_code:$exit_code, evidence:$evidence}'
    fi
}

actions=$(jq -c '.actions[]?' "$PLAN")
results=()
while IFS= read -r action; do
    [[ -z "$action" ]] && continue
    results+=("$(run_action "$action")")
done <<<"$actions"

results_json="[]"
[[ ${#results[@]} -gt 0 ]] && results_json=$(printf '%s\n' "${results[@]}" | jq -s '.')
record=$(jq -n \
  --arg mode "$MODE" \
  --arg root "$ROOT" \
  --arg struct "$STRUCT" \
  --arg generated_at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --argjson results "$results_json" \
  '{
    schema_version:"1.0",
    ok:all($results[]; .ok),
    mode:$mode,
    generated_at:$generated_at,
    root:$root,
    struct:$struct,
    summary:{
      actions:($results|length),
      applied:($results|map(select(.status=="applied"))|length),
      dry_run:($results|map(select(.status=="dry-run"))|length),
      skipped:($results|map(select(.status=="skipped"))|length),
      failed:($results|map(select(.ok|not))|length)
    },
    results:$results,
    rollback:{
      backups:[$results[].result.backup?],
      manifest:"generated/optimization/rollback.json"
    }
  }')

printf '%s\n' "$record" > "$OUT_DIR/execution.json"
jq '{schema_version, generated_at, root, struct, backups:.rollback.backups, results:[.results[] | {macro_id,status,result}]}' <<<"$record" > "$OUT_DIR/rollback.json"
{
    echo "# Project Optimization Execution"
    echo
    jq -r '"- mode: " + .mode, "- ok: " + (.ok|tostring), "- actions: " + (.summary.actions|tostring), "- applied: " + (.summary.applied|tostring), "- dry_run: " + (.summary.dry_run|tostring), "- failed: " + (.summary.failed|tostring)' <<<"$record"
    echo
    echo "## Results"
    jq -r '.results[]? | "- " + .macro_id + " status=" + .status + " ok=" + (.ok|tostring)' <<<"$record"
} > "$OUT_DIR/execution.md"

if [[ "$JSON_OUT" == "1" ]]; then
    printf '%s\n' "$record"
else
    jq -r '"Project Optimization Execution\n\nMode: " + .mode + "\nOK: " + (.ok|tostring) + "\n\nResult:\n  actions: " + (.summary.actions|tostring) + "\n  applied: " + (.summary.applied|tostring) + "\n  dry-run: " + (.summary.dry_run|tostring) + "\n  skipped: " + (.summary.skipped|tostring) + "\n  failed: " + (.summary.failed|tostring) + "\n\nReport: generated/optimization/execution.md\nRollback: generated/optimization/rollback.json"' <<<"$record"
fi

jq -e '.ok == true' <<<"$record" >/dev/null
