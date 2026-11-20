# Build 275

Uploaded to TestFlight from `paper-v2-tokens` at 30917cf9 on 2026-11-18 (PR #563).

- Menu slide (owner feedback: "needs a much better animation"): opening is a quicker spring with a small settle (0.36 s, was 0.4 s with none); closing is faster with no bounce (0.26 s). The panel grows the last 4% and fades in as it arrives, the place behind shifts 14 pt for depth, and a swipe released mid-way carries its speed into the spring. Reduce Motion keeps the plain fade.

Checks: 1,385 unit tests pass (1 skipped); stock-control lint 0; drawer and tab bar UI classes 21 run, 0 failures (2 skipped). The open and closed states were checked in the simulator; the motion itself was not reviewed frame by frame or on a real phone.
