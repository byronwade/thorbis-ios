# Build 278

Uploaded to TestFlight from `paper-v2-tokens` at 1164681a on 2026-11-19 (PR #563).

- Menu panel corners (owner's phone screenshot: "Bottom left still clips?"): the panel sits 8 from the left and bottom edges, so its 30 radius was cut by the phone's own rounded corner. The bottom corners now use the screen's radius less the gap (47 on Dynamic Island phones, 36 on notched, 30 on square-cornered).

Checks: 1,388 unit tests pass (1 skipped); stock-control lint 0; menu UI class 12 run, 0 failures (2 skipped, iPad only). Checked in the simulator with the device's corner mask applied; not yet seen on the owner's phone.
