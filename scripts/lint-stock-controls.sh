#!/usr/bin/env bash
# Guards against stock SwiftUI controls in app screens. The design system (ThorbisMenu,
# ThorbisSheet, PaperCircleButton, PaperTabs, Chip, PrimaryButton) is the only place these
# are allowed. Files still mid-migration are listed in the allowlist below and removed as
# they are converted; when the allowlist is empty the guard is absolute.
#
# Usage: scripts/lint-stock-controls.sh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

ALLOWLIST_FILE="scripts/.stock-controls-allowlist"
SEARCH_DIR="Thorbis/Sources"

# Patterns that mean a stock control. ` Menu {` excludes `.contextMenu {` (a long-press
# affordance we keep) because the leading space is required before `Menu`.
PATTERNS='(^|[^.a-zA-Z])Menu \{| Picker\(|\.confirmationDialog\(|\.buttonStyle\(\.bordered|\.borderedProminent'

# Never flag the design system itself.
EXCLUDE_DIR="$SEARCH_DIR/DesignSystem"

allow=""
if [[ -f "$ALLOWLIST_FILE" ]]; then
  allow="$(grep -vE '^\s*(#|$)' "$ALLOWLIST_FILE" || true)"
fi

hits="$(grep -rnE "$PATTERNS" "$SEARCH_DIR" --include='*.swift' \
          | grep -v "^$EXCLUDE_DIR/" || true)"

violations=""
while IFS= read -r line; do
  [[ -z "$line" ]] && continue
  file="${line%%:*}"
  if grep -qxF "$file" <<<"$allow"; then
    continue
  fi
  violations+="$line"$'\n'
done <<<"$hits"

if [[ -n "${violations//[$'\n']/}" ]]; then
  echo "error: stock SwiftUI controls found outside the design system."
  echo "Use ThorbisMenu / ThorbisSheet / PaperCircleButton / PaperTabs / Chip instead."
  echo "If a file is mid-migration, add it to $ALLOWLIST_FILE (and shrink that list as you go)."
  echo
  printf '%s' "$violations"
  exit 1
fi

echo "ok: no stock controls outside the design system (allowlist: $(wc -w <<<"$allow" | tr -d ' ') file(s))."
