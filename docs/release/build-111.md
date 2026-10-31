# Build 111 — owner Home, Book a job, dispatch Board

Runtime source: `e97b579` (`release/104-integration`).

- **Owner Home** (PR #175): "Sat, Oct 31 · 6 jobs · 2 techs out"; today's jobs by state; invoiced today, unpaid, estimates waiting, collected this month; Needs you with one action each; where every tech is. Owner's default bar (when the company has none): Home, Schedule, Money, Customers.
- **Book a job** (PR #176): "Who's calling?" search by name, phone or address; inline new customer; recent titles as quick picks; pick the service address (sent as the job's location); Not yet / Today / Tomorrow / Pick day with arrival times; tech with job counts and a "Suggested" label; one Book job button above the keyboard.
- **Board** (PR #176): for roles that assign jobs — Unscheduled, then each tech's day, then no tech yet; Schedule/Reschedule, Change tech, one-tap Move to <tech>, Open job.

**No tests were run, at the owner's request.** The stock-control lint passed (0), the Release archive succeeded, and Xcode reported **Upload succeeded** at 01:22 EDT on 31 October 2026.

Gaps: no daily collected figure (month so far shown), no job-type catalog, no tech availability, no incoming-calls feed. Booking, moving and assigning not tried against the live server. `NavigationByRoleTests` still expects the old owner bar.

**Processing, tester groups and What to Test are not verified.**
