# Native workspace slice report

Implemented typed API and standalone SwiftUI surfaces for staff notices, a live revenue report, and Price Book list/detail. Source files: `thorbis-ios/Thorbis/Sources/WorkspaceAPI.swift`, `thorbis-ios/Thorbis/Sources/WorkspaceViews.swift`; tests: `thorbis-ios/ThorbisTests/WorkspaceAPITests.swift`. Added safe `queryItems: [URLQueryItem]` arguments to the existing `APIClient.send` overloads in `Thorbis/Sources/API.swift` so query resource parameters are encoded as actual URL query items.

The views for More integration are `WorkspaceNoticesView(api:available:)`, `WorkspaceRevenueView(api:available:)`, and `WorkspacePriceBookView(api:canList:canViewDetail:)`. The root caller supplies availability after obtaining effective capabilities/features; the API remains the final authority. Methods are `staffNotices(limit:cursor:)`, `markStaffNoticesRead(limit:cursor:)`, `revenueReport()`, `priceBookItems(limit:cursor:)`, and `priceBookItem(_:)`.

Gate mapping, from `services/api/src/routes/manifest.ts` and the query resource registry:

| Surface | Canonical route | Feature | Capability |
|---|---|---|---|
| Staff feed/read sweep | `GET /v1/staff/notices`, `POST /v1/staff/notices/read` | `job_booking_notices` | `job.view` |
| Revenue | `GET /v1/reports/revenue` | `invoicing`; handler additionally opens `payments` feature | `invoice.view` |
| Price Book list | `GET /v1/query?resourceId=price_book_items&purpose=collection` | `price_book` (per-resource extra feature) | `pricebook.view` permission projection |
| Price Book detail | `GET /v1/price-book/items/{id}` | `price_book` | `organization.settings.edit` |

There is no dedicated GET Price Book items route. The list consumes the registered complete collection projection, validates resource/purpose/schema/local mode, keeps `nextCursor`, and shows a Load more control instead of inventing a total count. Detail reads the current immutable revision. Price and report money remain integer cents until display formatting. The revenue view hides totals when the server marks the report `truncated`; the server's scan cap is 1,000 invoices. Notice `unreadState:"unknown"` stays visibly distinct from `none`; the read action acknowledges one bounded sweep page and preserves its opaque continuation.

Only the revenue report is in this slice. Other canonical reports remain: payment activity, customer/location activity, schedule utilization, and operations, plus XLSX exports. No report availability should be claimed before the live route responds for the signed-in tenant and role.

TDD/verification: the new request-level tests were written before implementation. `outputs/workspace-red.log` records the expected missing `APIClient` methods. After implementation, `xcodebuild build-for-testing` for generic iOS Simulator passed with Swift 6 strict concurrency and `ONLY_ACTIVE_ARCH=YES ARCHS=arm64`; `outputs/workspace-green-final.log` has no errors/warnings. `git diff --check` passed. Simulator test execution is reserved for the root agent's serial suite; these new tests have compiled but have not yet been executed by this agent. No commit was created.
