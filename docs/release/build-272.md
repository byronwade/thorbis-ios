# Build 272

Uploaded to TestFlight from `paper-v2-tokens` at ba6deea8 on 2026-11-18 (PR #563).

- One signature for several estimates (Paper 38C): in Customer view the customer picks estimates and approves them with one signature. Each estimate is approved separately and shows "Approved" only from the server's answer for that estimate and revision; a send that cannot be confirmed shows "needs checking" with a Check approval button; nothing is sent after the screen is left. Three independent reviews; the third said merge.
- Price book: the Done bar could sit behind the keyboard when the picker was opened right after another keyboard (a quantity number pad) was dismissed. The bar now follows the keyboard frame UIKit reports (`keyboardPinnedBar`).

Known, not fixed: an approval the server records just as the customer leaves shows "needs checking" until Check approval is tapped; hand-back or lock mid-send shows the true status only after the job refreshes; "Approve N" does nothing, without a message, in the moment after returning from a cancelled send.

Checks: 1,384 unit tests pass (1 skipped); stock-control lint 0; large-company launch check passes for owner and technician. Signature and customer-document UI classes: 108 of 108 on the merged code. Invoice, price-book and estimate-draft UI classes pass with the on-screen keyboard showing. The full UI suite with the on-screen keyboard was still running at upload; earlier full runs had the keyboard hidden. Not tried on a real phone or account.
