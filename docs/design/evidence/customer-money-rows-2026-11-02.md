# Customer Money rows — staged 2 November 2026

Customer Money keeps estimates and invoices grouped by job and keeps the existing document routes, including records not linked to a job. Rows use the shared staff document component to show a reference and status. A checked USD line total is labeled “Last known total”; it is not a balance. Estimates with options show their option count without combining alternative prices. Voided invoices and unverifiable totals have no amount.

The conservative freshness label is deliberate: the API may return saved copies for some pages while the compilation succeeds. The current compilation cannot reliably attribute freshness to every record, including mixed live and cached pagination. A later provenance-aware implementation may distinguish fresh data.

| Check | Status and evidence |
| --- | --- |
| Feature retention and authority | Existing grouped and off-job navigation values retained; document records continue to be filtered by customer and organization by the existing compilation. |
| Shared component | Uses `DocumentListRowContent` and existing status tokens. Updated rendered screenshots and direct Paper comparison are not yet available. |
| Financial | New focused tests cover options, partial payments, stale-copy wording, unsupported currency, voids and overflow; they have not run. No payment history or collection behavior changed. |
| Accessibility and navigation | Shared row supports accessibility-size reflow and combined labels. New UI test exists but has not run; route taps, large text, VoiceOver and iPad remain unverified. |
| Verification | `xcrun swiftc -frontend -parse` of changed Swift files and `git diff --check` passed. Before implementation, the focused UI test built the app and test targets, but the simulator runner failed to install or launch with an invalid device state and a CoreSimulator server-died error. No red assertion or post-change green build was observed. |
| Independent review | Source review identified saved-copy freshness as a risk; the design now labels every amount conservatively. No further definite financial correctness issue was identified in that review. |
| Release | Not qualified for merge or TestFlight until the changed build, unit tests, relevant UI navigation and accessibility-size tests, and visual checks run. |
