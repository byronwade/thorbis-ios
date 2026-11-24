# Build 274

Uploaded to TestFlight from `paper-v2-tokens` at ea1449be on 2026-11-18 (PR #563).

- Job screen opens at once (owner feedback: "it takes several seconds before I see any details, the wrap up buttons"). Before, the screen drew a placeholder until the server returned the job, then read addresses, contacts, notes, follow-ups, photo count, visit history, booking call, member pricing, equipment, closeout, invoices and estimates one after another. Now the job shows immediately from the phone's last full copy or the list row (this business only), and the remaining reads run together.
- Invoices, estimates and the wrap-up checklist still come only from the server; they are not shown from a saved copy. If the server refuses the job or no longer has it, the phone's copy is taken down and the error is shown.

Checks: 1,385 unit tests pass (1 skipped); stock-control lint 0; job overview, documents, customer locations, on-site shortcut and Today stop card UI classes: 62 run, 0 failures (4 skipped). The full UI suite on build 272's code with the on-screen keyboard: 446 run, 1 failure (SavedWorkReview landscape test; the simulator did not rotate, not re-run), 11 skipped. Load time was not measured against a real server; the preview's data is local. Not tried on a real phone or account.
