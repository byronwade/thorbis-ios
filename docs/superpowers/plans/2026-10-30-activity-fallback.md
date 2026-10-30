# Activity fallback detail implementation plan

**Goal:** Allow a technician to select activity entries without a verified record destination and read their existing feed information, without inventing a link.

**Architecture:** Preserve existing `ActivityDestination` mapping and concrete record routes. Give `ActivityLink` a read-only fallback for its feed-provided title, body and timestamp. Bind the snapshot to the current organization, session generation, authority revision and relevant viewing capability; hide it on scope or permission changes. Apply it to the job, customer and invoice call sites, including compiled customer records.

**Constraints:** Preserve links, privacy, queued-note state, full long text, native back navigation, and no new network requests or fake record targets. Screens use SwiftUI and existing Thorbis styles.

**Checks:** First reproduce an unselectable customer payment history entry using the existing preview; then verify the fallback opens complete text and time. Verify known destination navigation is unchanged, the fallback disappears on authority changes, large content scrolls, and customer/job/invoice call sites compile. Review with another agent before delivery.
