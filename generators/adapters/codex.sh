#!/usr/bin/env bash
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AGENT_CMD="${CODEX_CMD:-codex}" exec "$DIR/generic.sh" "$@"
