# Build 276

Uploaded to TestFlight from `paper-v2-tokens` at 53241c0f on 2026-11-19 (PR #563).

- Estimates and invoices open at once (owner: "Yes, show saved copy"): the screen shows the copy this phone last read, under "Saved on this phone · checking for changes", until the live read lands. The saved copy is display only: the menu, Edit, the payments section and the bottom action all wait for the live record. It is shown only for the same document in the same company (and, opened from a job, the same job and customer); a refused read takes it down.
- Bottom bar in Shopify's layout (owner's instruction, Mobbin reference): a round Search button, an icon-only pill of the role's four places ending in the menu, and a round account button (initials) that opens Settings. Words are no longer drawn under the icons; each item still names itself to VoiceOver and on a long press. The menu tab still opens the slide-out menu.

Checks: 1,387 unit tests pass (1 skipped); stock-control lint 0; tab bar and menu UI classes 22 run, 0 failures (2 skipped, iPad only); estimate and invoice UI classes 101 run, 0 failures (run before the bar change). The bar was checked in the simulator in light and dark. Not checked: the saved-copy moment itself (preview data answers instantly), small phones, and a real phone.
