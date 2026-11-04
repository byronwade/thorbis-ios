# Job Money section jumps

The job Money page adds scroll-only Estimates and Invoices controls when both sections are accessible. They do not select or alter an invoice, amounts, payment, or permissions. The implementation uses the existing scroll reader and leaves all document actions in place.

Baseline UI case `testMoneySectionJumpsReachInvoicesAndEstimates` failed at the missing Invoices control on release source 2590c7f (`/tmp/thorbis-money-jump-red2.log`).

The first candidate run passed the normal-size jump and invoice-selection cases, but the largest-text test failed (`/tmp/thorbis-money-jump-green.log`). A diagnostic with explicit hierarchy and screenshot reproduced it (`/tmp/thorbis-money-jump-large-diagnostic.log`): the section heading and first invoice INV-2240 were visible, while the test had incorrectly required the second invoice INV-2209 to be immediately hittable. Evidence is in `/tmp/thorbis-money-jump-diagnostic-attachments/`. The test now checks the first invoice; the separate collection test still checks the selected INV-2209. The Estimates jump test additionally requires its estimate card to be hittable.

The corrected three-case iPhone simulator suite passed (`/tmp/thorbis-money-jump-final.log`): jumps in both directions, largest text, and selection retained through collection. Source hashes match before and after (`/tmp/thorbis-money-jump-final-before.sha`, `/tmp/thorbis-money-jump-final-after.sha`). Swift syntax parsing and `git diff --check` passed. No real device, iPad, VoiceOver, long-list fixture, or denied-permission UI test was run. The candidate must be integrated onto the current release and independently reviewed before release.
