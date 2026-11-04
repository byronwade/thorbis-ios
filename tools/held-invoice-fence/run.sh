#!/bin/bash
set -euo pipefail
root="$(cd "$(dirname "$0")/../.." && pwd -P)"
task_dir="$(mktemp -d /private/tmp/thorbis-invoice-fence-test-XXXXXX)"
trap 'rm -rf -- "$task_dir"' EXIT
swiftc "$root/Thorbis/Sources/InvoiceReadFence.swift" "$root/tools/held-invoice-fence/main.swift" -o "$task_dir/fence-tests"
"$task_dir/fence-tests"
