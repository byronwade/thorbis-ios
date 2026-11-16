#!/bin/bash
set -euo pipefail
: "${THORBIS_WEB_ROOT:?Set THORBIS_WEB_ROOT to the checked-out Thorbis TanStack repository}"
root="$(cd "$(dirname "$0")/../../.." && pwd)"
probe_dir="$(mktemp -d "${TMPDIR:-/tmp}/invoice-contract.XXXXXXXX")"
trap 'rm -rf "$probe_dir"' EXIT
export INVOICE_PROBE_DIR="$probe_dir"
python3 "$root/scripts/tests/invoice-command-contract/extract.py" "$root" "$probe_dir"
swiftc -swift-version 6 "$probe_dir/models.swift" "$root/Thorbis/Sources/InvoiceLineEditorState.swift" "$root/Thorbis/Sources/InvoiceDraftRecovery.swift" "$root/scripts/tests/invoice-command-contract/probe.swift" -o "$probe_dir/probe"
"$probe_dir/probe"
"$THORBIS_WEB_ROOT/node_modules/.bin/tsx" "$root/scripts/tests/invoice-command-contract/validate.ts"
