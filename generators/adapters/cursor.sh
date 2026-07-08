#!/usr/bin/env bash
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AGENT_CMD="${CURSOR_CMD:-cursor-agent}" exec "$DIR/generic.sh" "$@"
