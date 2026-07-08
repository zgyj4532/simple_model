#!/usr/bin/env bash
set -euo pipefail
OUT="${1:-generated/dashboard.html}"
mkdir -p "$(dirname "$OUT")"
cat > "$OUT" <<'HTML'
<!doctype html><meta charset="utf-8"><title>simple_model dashboard</title>
<style>body{font-family:system-ui;margin:24px}table{border-collapse:collapse}td,th{border:1px solid #ccc;padding:4px 8px}</style>
<h1>simple_model Project Intelligence</h1>
<p>Static dashboard generated from deterministic reports.</p>
<table><tr><th>Surface</th><th>Status</th></tr><tr><td>Code facts</td><td>available</td></tr><tr><td>PR gate</td><td>available</td></tr></table>
HTML
echo "[OK] dashboard: $OUT"
