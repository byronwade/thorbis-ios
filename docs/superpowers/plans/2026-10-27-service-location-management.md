# Service Location Management Plan

**Goal:** Bring Customer detail service-location management closer to Thorbis web by supporting full-field create/edit and confirmed removal in the native app.

**Contract:** `GET /v1/customers/{customerId}/locations` loads records. Create uses `POST /locations`. Update uses `POST /locations/{locationId}` with partial fields; nullable fields may be sent as `null` to clear them. Remove uses `POST /locations/{locationId}/remove` and returns `204`. API permissions remain authoritative; the native UI also gates writes with `customer.edit` and `core_crm`.

**Scope:** Preserve the Customer detail Paper layout. Add edit/remove actions to each location row and a Paper-styled location sheet with label, kind, address, notes, latitude/longitude, gate code, alarm code, parking, and dogs-on-site details. Validate coordinate pairs and geographic ranges. Keep server-refused edits visible in the form; only replace or remove local rows after successful server responses. No offline queue or undo mutation is added.

## Steps

1. Add failing tests for edit request path/body, explicit nulls for cleared nullable fields, remove path/body/204 handling, invalid IDs, and draft normalization/coordinate validation.
2. Implement Codable update and empty-body request models, validated API client update/remove methods, and a pure draft builder.
3. Add the Paper location editor, row actions, removal confirmation, capability gating, and success/error state handling.
4. Run focused tests and the full iPhone 17 Pro simulator suite; install the app, inspect Customer detail and both location sheet states, then run the independent review and record the release/parity status.

**Acceptance:** A saved location reloads with every supported field; clearing a pin or nullable access detail sends JSON `null`; a removed location disappears after server success and remains visible on refusal; users without `customer.edit` cannot open write actions; errors do not discard the in-progress edit.

## Execution Record

- Added validated request builders, UUID-checked update/remove paths, explicit `null` clearing, and no-body 204 removal handling.
- Added the full Paper-style create/edit sheet, row actions, confirmation, coordinate-aware Maps link, and server-refusal handling. Read-only simulator preview confirmed form values survive a rejected save and the location remains after a rejected removal.
- Full iPhone 17 Pro simulator suite: 131 passed, zero failed or skipped. Result: `/Users/byronwade/Library/Developer/Xcode/DerivedData/Thorbis-dmuwxdzkujtkngcfxjqjbnvsarbv/Logs/Test/Test-Thorbis-2026.10.27_00-20-11--0400.xcresult`.
- External TestFlight upload and independent code review are tracked separately from this implementation record.
