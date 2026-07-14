#!/usr/bin/env bash
set -euo pipefail

TARGET_ROOT="${PWD}"
STRUCT_PATH=""
DRY_RUN=0
FORCE=0
JSON_OUT=0

usage() {
  cat <<'USAGE'
project_init.sh [--target-root PATH] [--struct PATH] [--dry-run] [--force] [--json]
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --target-root) TARGET_ROOT="$2"; shift 2 ;;
    --struct) STRUCT_PATH="$2"; shift 2 ;;
    --dry-run) DRY_RUN=1; shift ;;
    --force) FORCE=1; shift ;;
    --json) JSON_OUT=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "[FAIL] unknown init arg: $1" >&2; exit 64 ;;
  esac
done

TARGET_ROOT="$(cd "$TARGET_ROOT" 2>/dev/null && pwd || printf '%s' "$TARGET_ROOT")"
PI_DIR="$TARGET_ROOT/.projectIntelligence"
if [[ -z "$STRUCT_PATH" && -f "$TARGET_ROOT/struct.json" ]]; then
  STRUCT_PATH="$TARGET_ROOT/struct.json"
fi
struct_ref=""
if [[ -n "$STRUCT_PATH" && "$STRUCT_PATH" == "$TARGET_ROOT"/* ]]; then
  struct_ref="../${STRUCT_PATH#$TARGET_ROOT/}"
fi
paths=("$PI_DIR" "$PI_DIR/struct.modules" "$PI_DIR/policies" "$PI_DIR/artifacts" "$PI_DIR/state" "$PI_DIR/cache" "$PI_DIR/backups")
if [[ "$DRY_RUN" != "1" ]]; then
  if [[ -e "$PI_DIR/config.json" && "$FORCE" != "1" ]]; then
    if [[ "$JSON_OUT" == "1" ]]; then
      jq -n --arg project_root "$TARGET_ROOT" --arg control_plane "$PI_DIR" '{ok:true,project_root:$project_root,control_plane:$control_plane,existing:true,created:false}'
    else
      echo "[OK] reused existing $PI_DIR"
    fi
    exit 0
  fi
  mkdir -p "${paths[@]}"
  if [[ -n "$struct_ref" ]]; then
    jq -n --arg project_root "$TARGET_ROOT" --arg struct_path "$struct_ref" '{schema_version:"1.0",project_root:$project_root,struct_path:$struct_path,artifacts_dir:"artifacts",state_dir:"state",cache_dir:"cache",backups_dir:"backups"}' > "$PI_DIR/config.json"
  else
    jq -n --arg project_root "$TARGET_ROOT" '{schema_version:"1.0",project_root:$project_root,struct_path:null,artifacts_dir:"artifacts",state_dir:"state",cache_dir:"cache",backups_dir:"backups"}' > "$PI_DIR/config.json"
  fi
  printf '%s\n' '{"apply":false,"require_confirmation":true,"allowed_operations":["struct_include_split","export_normalization","import_sync"]}' > "$PI_DIR/policies/apply.json"
  printf '%s\n' '{"fail_on_missing":true,"allow_unresolved":false}' > "$PI_DIR/policies/interfaces.json"
  printf '%s\n' '{"mode":"affected","require_gate":true}' > "$PI_DIR/policies/tests.json"
  printf '%s\n' 'artifacts/' 'cache/' 'state/' 'backups/' '*.tmp' > "$PI_DIR/.gitignore"
fi
if [[ "$JSON_OUT" == "1" ]]; then
  dry=false; created=true
  [[ "$DRY_RUN" == "1" ]] && dry=true && created=false
  jq -n --arg project_root "$TARGET_ROOT" --arg control_plane "$PI_DIR" --arg struct_path "$struct_ref" --argjson dry_run "$dry" --argjson created "$created" '{ok:true,project_root:$project_root,control_plane:$control_plane,struct_path:($struct_path|if length==0 then null else . end),dry_run:$dry_run,created:$created}'
else
  [[ "$DRY_RUN" == "1" ]] && echo "[DRY-RUN] would initialize $PI_DIR" || echo "[OK] initialized $PI_DIR"
fi
