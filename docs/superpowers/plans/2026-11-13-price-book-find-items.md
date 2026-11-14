# Price book search across pages

> For agentic workers: execute and verify the tasks below in order.

**Goal:** Let technicians find matching price-book items without loading unrelated pages.
**Architecture:** Use the existing authorized collection query Filter AST and keyset pagination for typed searches, while keeping the current paged browse and clearly labelled loaded-item fallback if a search cannot reach the server. Bind requests and results to the current actor, organization, origin, authority and search text.
**Tech stack:** SwiftUI, existing Query Platform API and XCTest.

- [ ] Reproduce an item beyond the first browse page being unfindable; include escaped query text and pagination.
- [ ] Add a bounded, server-filtered search with cancellation and stale-response protection. Preserve detail, editing, offline fallback and filters.
- [ ] Verify the focused API and simulator journeys, including offline/error, cleared search and scope changes; independently review before release.
