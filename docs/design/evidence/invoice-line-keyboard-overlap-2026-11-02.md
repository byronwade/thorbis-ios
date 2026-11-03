# Invoice line actions with the keyboard open

The build-150 integrated direct-close retry failed its keyboard toolbar overlap assertion (`/private/tmp/thorbis-150-direct-retry.log`, xcresult `Test-Thorbis-2026.11.02_23-41-30--0500.xcresult`). Its screenshot showed the floating keyboard Done overlapping the lower-right edge of the invoice line Done pill. The test stopped before tapping it.

When an invoice keyboard is open, the line's Done and Remove actions now sit together at the leading side, separated by 24 points at standard text size and stacked with 16 points between at accessibility sizes. The destructive action's existing behavior and menu remain unchanged. The shared row retains its prior layout for other callers and when the invoice keyboard is hidden. The separate keyboard Done still dismisses the keyboard without closing the line.

The signed iPhone simulator run passed four focused UI tests (`/private/tmp/thorbis-keyboard-overlap-green.log`, xcresult `Test-Thorbis-2026.11.02_23-47-38--0500.xcresult`). The original direct-close case asserted the line Done and Remove did not intersect the keyboard or keyboard Done, verified their separation, tapped line Done, and confirmed the edited quantity remained. Additional cases verified focused-price formatting, separate keyboard dismissal while the line stays open, and largest-text line Done geometry and tap. The captured standard-size screenshot is `/private/tmp/thorbis-keyboard-overlap-green-attachments/221657EF-6708-46B8-BACE-CEA1CBF6E199.png`.

A physical device, iPad, floating/split keyboard, VoiceOver and larger text sizes on a smaller phone were not tested. No live invoice was changed.

After independent review, the largest-text case was strengthened to reveal Remove with the keyboard open, verify its separation from line Done and both keyboard surfaces, and then close the line. This updated test passed on the same production source (`/private/tmp/thorbis-keyboard-overlap-large-remove.log`, xcresult `Test-Thorbis-2026.11.02_23-54-25--0500.xcresult`).
