# Build 110 — more of the day works without signal

Runtime source: `01ef7a7` (`release/104-integration`).

- **Read offline** (PR #173): when Today loads with signal, up to 12 of today's jobs are read ahead (yours first): job, notes, past visits, follow-ups, estimates and invoices with lines, the customer's record, contacts, addresses, equipment and history. Offline, those screens show "Saved on this phone · <time>". Copies are per person and workspace, pruned after 14 days, cleared on sign-out.
- **Money safety:** saved estimates and invoices are never acted on; payments say they need a connection; signatures are never queued.
- **Act offline:** Notify office and return-visit requests wait on the phone and send later, checking first so nothing is sent twice.
- **Speed** (Debug, simulator): Today's sort over 300 jobs 1.27 s → 0.02 s; 17 → 1 requests across four tab switches (10-second reuse).
- Actions that need signal say so instead of failing silently.

**No tests were run, at the owner's request.** The stock-control lint passed (0), the Release archive succeeded, and Xcode reported **Upload succeeded** at 00:57 EDT on 31 October 2026.

Trade-off: read-ahead adds about 14 requests per job when Today loads. Not verified against a real server or on a device; tap paths not exercised.

**Processing, tester groups and What to Test are not verified.**
