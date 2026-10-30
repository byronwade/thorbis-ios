#!/usr/bin/env bash
# Prevent stock controls from spreading beyond the exact existing baseline.
set -euo pipefail
cd "$(dirname "$0")/.."
exec python3 scripts/lint_stock_controls.py
