# Read-only document hand-back

**Goal:** Preserve protected technician hand-back if an estimate or invoice becomes read-only between book browsing and the fresh decision read.

**Approach:** Route the existing read-only paper hand-back through the same `beginHandBack` destination reset already used by the interactive estimate and invoice screens. Keep the customer-mode owner-authentication boundary unchanged. DEBUG-only local transport controls simulate a sent estimate becoming approved and an issued invoice becoming void after the book is opened.

**Verification:** Reproduce both status-change routes before the change, then rerun them and the affected customer document-book suite; confirm technician unlock, unchanged job scoping and owner-authenticated exit. Run release-note tests. Capture simulator evidence and report untested real-network, iPad and VoiceOver scenarios. Do not describe a navigation fix as financial approval or payment work.
