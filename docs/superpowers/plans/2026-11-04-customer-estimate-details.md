# Customer estimate details before selection

**Goal:** Let a customer read each sent estimate's issued details before selecting work, without changing the selection or submitting an approval.

**Architecture:** The handoff opens a read-only native destination for a specific job estimate. A scoped live read confirms the current job, its estimate membership, and the issued revision before showing line items; current actor, workspace, origin, session, authority and estimate-view access must remain valid. Existing customer text, amount and description-reader components provide the presentation. Review and approval remain their existing independent flows.

**Acceptance:** With two sent estimates, open each before selection and read its own details and discounts, then return with the selection unchanged. Long descriptions open read-only and support accessible text. Changed job membership, revision, authority, session or API origin retires the destination or offers a truthful retry; failures never display stale terms as current. No extra approve/token/payment operation is sent. Preserve all existing actions and customer-mode owner unlock.

**Execution:** Add a mounted failing test before implementation, then focused authorization and late-response regressions and a green mounted test. Preserve simulator coordination. Review exact source independently, compare with existing customer presentation/Paper style, add What's New entry and document real versus untested coverage before release. No server or payment contract changes are included.
