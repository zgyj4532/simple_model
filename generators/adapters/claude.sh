#!/usr/bin/env bash
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AGENT_CMD="${CLAUDE_CMD:-claude}" exec "$DIR/generic.sh" "$@"
