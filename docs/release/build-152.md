# Build 152

Uploaded to App Store Connect on 3 November 2026 from the source tree of
`release/104-integration` merge `e2008ff2980035a43eca6244f7ec95dcf235e80a`
([PR #270](https://github.com/byronwade/thorbis-ios/pull/270)). Xcode reported
that the upload succeeded and the package was processing. Processing completion
and tester-group availability have not been verified.

Customer records for several jobs now load with at most four job requests in
flight, preserving job order, scoped document checks and explicit partial
failures. Authority is checked between pages and before results are published.
This is bounded concurrency, not demand paging: the current service still loads
all jobs and returns unbounded notes, legacy photos, contacts and locations.
No physical-device benchmark has been run.

After regenerating the checkout's Xcode project, the combined release source
passed 38 focused customer-compilation and What's New tests. A separate run on
the combined source passed two job-document UI journeys and 29 existing unit
tests, but omitted the new concurrency class because the generated project was
stale; it is not counted as coverage of that class. The merged tree matched the
tested source. Independent source review found no new concrete blocker; an
existing in-flight saved-copy write can precede the post-response authority
check. See [customer loading evidence](../design/evidence/customer-records-bounded-reads-2026-11-03.md).

The signed archive reported build 152 and passed the Tap to Pay audit with the
feature disabled. Xcode reported the existing missing Stripe Terminal framework
dSYM warning; see [build 148](build-148.md#stripe-terminal-symbol-investigation).
Build 151's estimate cards are included. Durable draft recovery, paragraph-length
server storage, customer-selectable add-ons and qualified on-site payment methods
remain separate work.
