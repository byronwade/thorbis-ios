# Build 109 — iPad layout and a tidier visit

Runtime source: `ffde0cf` (`release/104-integration`).

- **iPad** (PR #171): sidebar with business switcher, Search (⌘F/⌘K), Create (+, ⌘N), every place, Settings and the current job; list beside detail for Schedule, Jobs, Customers, Estimates and Invoices; Week board; portrait slide-over sidebar; compact widths fall back to the phone layout. New estimate and New customer now open from Create on iPad.
- **Phone polish** (PR #170): Activity composer ground reaches the bottom edge, On site status line wraps cleanly, customer header collapses at accessibility sizes, Money's customer view is a quiet button (one ink commit), wrap-up checklist on one panel, pinned bars on the page ground in dark mode, long Approve labels shorten, payment method rows breathe.

**No tests were run, at the owner's request.** The stock-control lint passed (0), the Release archive succeeded, and Xcode reported **Upload succeeded** at 00:20 EDT on 31 October 2026.

Unverified: true device rotation (landscape shots were simulated), Split View resizing, hardware-keyboard shortcuts, the signature pad screenshot.

**Processing, tester groups and What to Test are not verified.**
