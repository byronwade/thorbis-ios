# Estimate revision and option packages

## Goal

Let a technician revise a sent or declined estimate into a replacement draft and edit its mutually exclusive option packages in the Thorbis Paper mobile style.

## Scope and server contract

- Expose revision only for sent or declined records, with `estimate.create` entitlement; approved estimates require a change order and existing drafts cannot be changed through this endpoint.
- Submit the exact reviewed `currentRevisionNumber`, a non-empty title and main line set, and up to eight uniquely identified options with 1–500 lines each.
- Preserve manual and Price Book source identity for every existing line; allow Price Book selection only with the existing feature and view capability. Block editing when an unknown source cannot be represented losslessly.
- Keep the revision editor open with its current text after API errors or stale-revision conflicts. Offer an explicit reload of the current estimate for conflict recovery.
- On success, return to the detail screen with the replacement draft adopted; do not send or approve it automatically.
- Use the actual Thorbis brand mark already verified against `Thorbis-TanStack/apps/showcase/public/logo-source.png` for brand surfaces; do not substitute a recreated symbol.

## Implementation steps

1. [x] Add failing model tests for source-preserving request encoding, option identity and line/option limits, exact money and quantity validation, changed-state detection, and supported statuses.
2. [x] Add an estimate line source request type and an editor state model that maps server snapshots without losing Price Book identity, including explicit unsupported-source handling.
3. [x] Build a native revision/options editor with main lines, add/remove/reorder controls, up to eight option packages, and current-revision submission.
4. [x] Connect estimate detail actions to the editor under the canonical entitlement/status gates; preserve edits on errors and support explicit fresh-record recovery.
5. [x] Add preview fixture coverage for the Paper estimate revision editor and verify accessible controls and the brand asset.
6. [ ] Run focused tests, the complete iPhone simulator suite, Release build, design preview inspection, and independent review; update parity and beta coverage evidence.

## Acceptance

- Requests match the canonical `/v1/estimates/:id/revise` body and preserve source identity for each line in the main estimate and all options.
- Invalid limits, empty values, unsupported sources, or unauthorized statuses cannot be submitted from the UI.
- A stale revision never triggers an automatic retry or silently drops the user's edits.
- The revised estimate becomes a draft only after the server confirms success.
- The existing Thorbis logo asset remains the verified source mark in the app icon and sign-in surface.
