# TestFlight 1.0 (83)

Uploaded October 29, 2026 at 4:30 p.m. EDT. Xcode reported upload succeeded and Apple began processing; tester availability is pending.

Runtime source: `d6cf65669e5e137c9149f73eab27b185e9faf4bc`. Technicians can review estimates from catalog search and edit the most recently added invoice line without leaving the price book. Estimate catalog additions respect the selected Work or Materials group. Larger-text invoice fields and actions stack, and long shared menus scroll.

Focused iPhone simulator checks covered repeated invoice additions, exact-line edits, price and quantity entry at normal and largest text, estimate search and option/group retention, and first/last selection in long and short menus. Independent source reviews found no blocking issues. iPad, compact landscape, VoiceOver and physical-device behavior are not certified by these runs. A prior merged run found an overlapping invoice action bar; the fix and focused reruns passed. Existing draft-estimate Save remains disabled pending a qualified and deployed server contract.

The Release archive passed signed app/widget identity, version, source-fingerprint, configuration and preview-exclusion checks. Archive and audit: `/private/tmp/thorbis-83-final.055eesnd/`. Tap to Pay remains disabled. Xcode reported a missing Stripe Terminal dSYM during upload, limiting symbolication for that framework.
