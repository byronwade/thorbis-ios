# Build 113 — friendlier screens for customers

Runtime source: `4cdb7ce` (`release/104-integration`).

- **Customer-facing states** (PR #181): estimate and invoice signing, the hand-off, the public estimate link, the document book, job customer documents and self-edit show one homeowner sentence in large type with at most one action (Try again / Close / Hand back to the technician) and a document-shaped placeholder while loading. Raw server error text no longer reaches customers. Self-edit Try again now retries.
- **Next stop**: "Turn on location to see drive time" when location is off, opening Settings; dismissible until the app is next opened.
- **Wording**: Inbox, Team, Needs attention, Search, Reports, Billing empty states follow the pattern; Team no longer shows two empty states at once.
- **Sweep**: leftover divider lines removed, trade-style times, What's new "Got it".

**No tests were run, at the owner's request.** The stock-control lint passed (0), the Release archive succeeded, and Xcode reported **Upload succeeded** at 02:21 EDT on 31 October 2026.

Not verified: location actually denied on a device; customer screens on iPad; the public link and document book screens themselves (components shown in the preview gallery).

**Processing, tester groups and What to Test are not verified.**
