# Streamline catalog editing

**Goal:** Reduce interruptions while technicians build estimates and invoice drafts from the price book, preserving existing document capabilities and accurate save states.

**Design:** `docs/superpowers/specs/2026-10-29-estimate-workspace-storefront-design.md` and the Paper PYO/V97 builder. The technician keeps catalog context while adding items, can move directly back to the editable estimate, and can adjust the most recently added invoice line without losing search context. These are incremental improvements toward the full editable workspace.

**Constraints:** Keep estimate merging and invoice distinct-line semantics, tenant and session guards, explicit save/issue operations, existing actions and accessibility. Do not enable unsupported draft estimate saving or alter issued/approved documents. Keep user-authored text and existing work intact.

**Checks:** Exercise repeated catalog additions and direct editing of the exact invoice line, removal and context changes; exercise estimate return from catalog with items preserved and save restrictions intact. Build and run focused native tests; review the changes independently and verify a signed TestFlight build when qualified. Physical-device and full editable-canvas behavior remain separately qualified.
