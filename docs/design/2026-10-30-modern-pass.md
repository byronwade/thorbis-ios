# Modern pass (2026-10-30)

Goal: every screen is simple to use and simple to look at. Nothing overlaps, one main action per screen, and the first thing a tech reads is the thing they came for.

## References

- **Housecall Pro** rebuilt its mobile app in 2026 around "faster, cleaner" ([May 2026 updates](https://www.housecallpro.com/resources/may-2026-product-updates/), [Spring Summit redesign](https://www.landscapemanagement.net/housecall-pro-to-unveil-platform-redesign-at-built-to-last-spring-summit-2026/)).
- **ServiceTitan Field**: the job header collapses on scroll, and the status steps (Dispatch, Arrive, Closeout) sit in a fixed bottom bar ([job details in FMA](https://help.servicetitan.com/docs/explore-job-details-and-actions-in-fma)).
- **Jobber**: Day, List and Map schedule; a visit opens on client, title and address with Get directions, and a camera button replaces quick-create on visits ([jobs in the Jobber app](https://help.getjobber.com/en/articles/jobs-in-the-jobber-app/)).
- **ChatGPT / Claude mobile**: almost no chrome, one type family, soft neutral fills instead of boxes, and actions at the bottom under the thumb.

## Rules

1. **One type family.** Inter everywhere, including money, times and record numbers, with tabular digits so columns line up. No typewriter face.
2. **Titles start at the top.** A tab root is a title, a one-line subtitle, and at most one circle button on the title's own line. No near-empty row above it.
3. **One pill per row.** Only something you can tap or that carries state (status) is a pill. Facts like time and technician are plain text with a small icon.
4. **One amount per side.** A row puts the label and supporting line on the left and one amount on the right. Never stack two amounts on the right.
5. **Say it once.** One banner per condition. If the offline banner shows, connection errors don't repeat it.
6. **One main action at the bottom.** The commit is the ink button at the bottom; everything else is a quiet row or the ••• menu.
7. **Words match the app.** The bar is "bottom bar" and the list is "the menu"; nothing refers to tabs or More.

## Pass 1 (this change)

- Money, times and record numbers moved from Geist Mono to Inter with tabular digits (`Theme.monoFont`, `Theme.moneyFont`).
- `PaperHeader`: on iPhone the filter circle joins the title row; the empty top row is gone.
- Job header: only status is a pill; time and technician are plain facts; the five-step progress bar is removed (status names the step, the bottom button names the next one).
- Offline job: the "No connection" banner no longer repeats the offline banner.
- Money: month rows carry one amount each side.
- Customize menu: bottom bar and menu wording.
- Preview banner takes its own room at the top instead of covering titles (DEBUG only).

## Next passes

- Job: collapse the header on scroll like ServiceTitan; move Member into the customer line; four tabs (fold Estimates into Invoice as "Money").
- Customer: three actions (Call, Text, Directions) with Email in •••; details as a quiet list.
- Estimates and Invoices lists: search moves into the bottom search drawer; group headers carry totals.
- Forms (new customer, follow-ups, assignment): one column, labels above fields, the save button always reachable above the keyboard.
- Customer-facing estimate: larger option cards with the price first.
