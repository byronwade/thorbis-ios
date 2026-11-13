# Customer estimate detail navigation

The customer can read each verified estimate for the current job from the existing overview. Add previous and next controls and interior horizontal swipes to the read-only detail destination without changing selections, consent, approvals, or technician editing.

Use only loaded records for which the existing current-job, scope, freshness, and authority predicates pass. Each page uses the existing issued-revision loader and read-only description controls. Do not wrap around, infer unavailable membership, or navigate after authority retirement. Preserve UIKit edge-back and vertical scrolling; accessible controls must work without swipe.

Verification: start with the failing customer swipe regression; add focused tests for accessible controls, unchanged selection, long descriptions, unavailable/current authority, first/last boundaries and protected back navigation. Confirm each newly shown estimate reloads its own revision and that stale or failed loads never show another estimate's terms. Run focused iPhone tests and independent review before integration.
