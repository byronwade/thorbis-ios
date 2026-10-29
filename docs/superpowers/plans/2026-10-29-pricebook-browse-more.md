# Browse more price book matches

**Goal:** Let technicians reach loaded matching price book items beyond the first 50 in the shared estimate and invoice pickers.

**Approach:** Preserve the current filtering and ranking, then expose a bounded 50-item page and total count after excluding items already shown in Recent. Show clearly labeled next and previous actions; reset to the first page on query, category or catalog authority change. Counts describe locally loaded matches, not the remote total. Keep archived/currency filtering, existing add actions, errors and permission checks unchanged. A lazy list caused invoice selection regressions in simulator tests, so this design retains the existing row rendering while bounding its size.

**Checks:** Add behavioral tests for more than 50 ranked and blank-query matches, recent exclusion before paging, category filtering, and resetting visible count after changing query/category/context. Run focused simulator tests and a native picker journey. Check large-catalog responsiveness and report its scope. This work does not enable estimate draft saving or change pricing authority.
