# Build 268

Uploaded to TestFlight from `paper-v2-tokens` at ea540701 on 2026-11-18 (PR #563).

Fixes the app freezing on "Opening your workspace…" for a company with many jobs (reported from a real owner account; reproduced in the simulator with 3,000 sample jobs and customers via the new DEBUG launch option `--paper-preview-scale`).

- Schedule board (`DispatchBoardView`): today's and the waiting lists are computed once per change instead of once per row; the waiting queue is lazy.
- `JobFiltering.date` parses each timestamp once.
- `Store.customerName` uses a name index instead of walking the customer list.

With the large book, the owner's first screen went from about 40 s (or never settling) to about 6 s on a debug simulator build.

Checks: 1,352 unit tests pass (1 skipped); stock-control lint 0. UI classes for menus, the job page and the lists passed on the commit before this one (100 run, 0 failures). Not tried on a real account or phone.
