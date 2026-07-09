#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION=""

usage() {
    cat <<'USAGE'
package_codex_plugin.sh --version <version>

Validates and packages plugins/simple-model-project-intelligence into dist/.
USAGE
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --version) VERSION="$2"; shift 2 ;;
        -h|--help) usage; exit 0 ;;
        *) echo "unknown arg: $1" >&2; usage; exit 64 ;;
    esac
done

[[ -n "$VERSION" ]] || { usage; exit 64; }

cd "$ROOT"
bash tools/sync_codex_plugin.sh --check >/dev/null
jq empty .agents/plugins/marketplace.json
jq -e --arg v "$VERSION" '.version == $v' plugins/simple-model-project-intelligence/.codex-plugin/plugin.json >/dev/null
jq empty plugins/simple-model-project-intelligence/skills/simple-model-project-intelligence/references/command-manifest.json
plugins/simple-model-project-intelligence/skills/simple-model-project-intelligence/scripts/simple_model_pi.sh commands --json >/dev/null

mkdir -p dist
out="dist/simple-model-project-intelligence-plugin-${VERSION}.zip"
rm -f "$out"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/simple-model-project-intelligence"
cp -R plugins/simple-model-project-intelligence/. "$tmp/simple-model-project-intelligence/"

hash_file() {
    if command -v sha256sum >/dev/null 2>&1; then
        sha256sum "$1" | awk '{print $1}'
    else
        shasum -a 256 "$1" | awk '{print $1}'
    fi
}

self_check_hash=""
if [[ -f generated/plugin-self-audit/latest.json ]]; then
    self_check_hash="$(hash_file generated/plugin-self-audit/latest.json)"
fi

files_json=$(
    cd "$tmp/simple-model-project-intelligence"
    find . -type f ! -name release-manifest.json | sort | while read -r f; do
        h=$(hash_file "$f")
        jq -cn --arg path "${f#./}" --arg sha256 "$h" '{path:$path, sha256:$sha256}'
    done | jq -s '.'
)

jq -n \
  --arg plugin "simple-model-project-intelligence" \
  --arg version "$VERSION" \
  --arg git_commit "$(git rev-parse HEAD 2>/dev/null || echo unknown)" \
  --arg created_at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --arg self_check_hash "$self_check_hash" \
  --argjson files "$files_json" \
  '{schema_version:"1.0", plugin:$plugin, version:$version, git_commit:$git_commit, created_at:$created_at, self_check:{hash:$self_check_hash}, files:$files}' \
  > "$tmp/simple-model-project-intelligence/release-manifest.json"

(cd "$tmp" && zip -qr "$ROOT/$out" simple-model-project-intelligence)
sum=$(hash_file "$out")
manifest_sum=$(hash_file "$tmp/simple-model-project-intelligence/release-manifest.json")
zipinfo -1 "$out" | grep -q '^simple-model-project-intelligence/release-manifest.json$'
jq -n --arg file "$out" --arg sha256 "$sum" --arg manifest_sha256 "$manifest_sum" --arg version "$VERSION" '{ok:true, file:$file, version:$version, sha256:$sha256, manifest:"release-manifest.json", manifest_sha256:$manifest_sha256}'
