# Native Payments collection

The web Work → Payments destination reads `/v1/query` with `resourceId=payments` and `viewId=payments.all`, newest first, and offers all/card-and-ACH/cash/refunded views. It is an online-only projection under `invoice.view`; organization-wide query scope can be narrower than a technician's invoice access. Do not equate a scoped empty result with no company payments, aggregate partial pages into a total, substitute merchant setup for the Payments list, or expose a navigation item until the list and its record route are qualified.

First implement and test a fresh, paginated collection contract with strict identity and money validation, source-context cancellation and no offline cache. Then implement a bounded/lazy native list with honest loading, error, empty and pagination states, supported filters and a selectable invoice destination. Verify permission/tenant changes, refunds, pagination and accessibility before enabling the route.
