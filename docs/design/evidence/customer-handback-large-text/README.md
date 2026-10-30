# Customer hand-back at largest text size

On the dedicated iPhone SE simulator at the largest accessibility text size, the original fixed-height customer hand-back button truncated its label. The focused regression failed before the fix because the button remained 56 points tall (`/private/tmp/long-handback-red.log` and its result bundle). The adaptive button retains its minimum target height and permits its full label to wrap.

The focused post-fix run passed and produced `hand-back-largest.png`, showing the complete label. A subsequent standalone regression also passed, checking all four label bounds, hit testing, and the protected technician unlock and Go back paths. In the same broader run, interactive estimate, interactive invoice and read-only invoice hand-back tests passed, along with nine release-note tests. The read-only estimate test was interrupted by a runner signal TERM at launch, not an assertion (`/private/tmp/handback-separate-tests.log` and its result bundle); see the subsequent retry result below.

This evidence concerns the shared hand-back control. It does not qualify the separate estimate review footer or complete long-document visibility. Physical iPhone, landscape, iPad, VoiceOver and right-to-left layouts were not tested in these runs.

The read-only estimate case was retried on the same source and passed (`/private/tmp/handback-readonly-retry.log` and `/private/tmp/handback-readonly-retry.xcresult`). The earlier interrupted result remains preserved separately. An independent review found no definite functional regression and requested the four-sided bounds and hand-back checks included in the standalone test.
