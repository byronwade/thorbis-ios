# List performance staging evidence

The staged app source at `a748d45` combines customer list rendering and price-book search caching with the existing job/document staging branch. This is not release approval.

- Focused iPhone SE simulator run: 45 unit tests and one customer-list UI test passed (`/private/tmp/thorbis-list-performance-staging.xcresult`). It covered `JobFilteringTests`, `PriceBookSearchTests`, `WhatsNewTests`, and the customer-row navigation test.
- The customer grouping regression includes 600 customers and 1,200 jobs. It checks completeness and grouping, not real-device scrolling speed.
- The price-book benchmark documented separately measures repeated identical synthetic searches on a macOS host; it is not a device, network, or first-query measurement.
- The user-visible release note was added after that run; `WhatsNewTests` passed against the updated source (`/private/tmp/thorbis-list-performance-notes.xcresult`).
- This change does not page customer/job network loading or the estimate/invoice price-book catalog. Media pagination, image derivatives, device profiling, and the previously documented invoice navigation issues remain separate and unresolved.
