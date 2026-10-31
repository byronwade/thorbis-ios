# Build 121 — redesign phase 1

Runtime source: `e4c8309` (`release/104-integration`).

- **Redesign phase 1** (PR #200), after the owner called the app "bland and hard to navigate" and pointed at Linear mobile and Mobbin: neutral white/near-black palette, semibold titles and a 34pt display step, status hues with tinted chips; new `StatusGlyph`, `PropertyChip`, `InitialsAvatar`, `PlaceMark`, `Well`; floating labeled tab bar (Today · Jobs · Customers · More) with a separate search circle; a real More screen with coloured place marks, business switcher and bar editor; "+" moved to screen headers; Today grouped Now / Up next / Later today / Done with status glyph rows and tech avatars. Golden rules and DesignSystem README updated.
- **History polish** (PR #199): Activity shows estimates and the booking call; long notes fold with More; Customer › Jobs shows 4 then "Show N older jobs".

**Tests run: touched unit suites (37) and WhatsNewTests only; UI suite compiled, not run, at the owner's request.** Contrast script: 0 failures for text tokens. The stock-control lint passed (0), the Release archive succeeded, and Xcode reported **Upload succeeded** on 31 October 2026.

Not verified: "On site Xm" with real arrival times, tapping More inside rows, VoiceOver on device, amber/grey glyphs below 3:1 non-text contrast (words carry status).

**Processing, tester groups and What to Test are not verified.**
