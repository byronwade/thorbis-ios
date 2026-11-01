# Build 123 — redesign phase 2

Runtime source: `32514bd` (`release/104-integration`). Build 122 was rejected by App Store Connect as already used (an upload not recorded here), so this is 123.

- **Job detail** (PR #202): job number eyebrow, 30pt street, wrapping property chips (status → status menu, time → schedule, tech → assign, membership, amount → Money), text tabs, grouped wells with headers and counts, amber "Before you go in" on site, Activity timeline with per-kind glyphs, "+ Note" / camera / ink action bottom bar (now also on completed and canceled jobs).
- **Lists** (PR #203): Jobs grouped In progress / Scheduled / Unscheduled / Done with status-glyph rows, tech avatars and "Late"; Customers with initials avatars and letter sections; Customer detail with avatar, chips and grouped wells ("Dogs on site" as a warning callout); Search results grouped by type with glyphs and "Recently viewed".

**Tests run: touched unit suites only (38 for lists, 4 suites for job); UI suite compiled, not run, at the owner's request.** The stock-control lint passed (0), the Release archive succeeded, and Xcode reported **Upload succeeded** on 31 October 2026.

Not verified: UI suite (one CustomerClarityUITests case already expects removed "Customer details"/"Records"), iPad split layouts, VoiceOver on device.

**Processing, tester groups and What to Test are not verified.**
