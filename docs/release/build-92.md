# Build 92 — inbox visual cues

- Runtime source: `4cf121cd9051be58473fffde62f93889155be664`.
- Adds an icon and explicit unread label to job notices while keeping their existing navigation and actions. It includes the visual changes from build 91.
- On the exact source, nine What's New unit tests and the focused iPhone SE inbox navigation UI test passed. Dark and light inbox screenshots are in `docs/design/evidence/inbox-visual/`. Live notice updates, VoiceOver and larger text have not been validated.
- The New Customer keyboard change was excluded after the Done control was absent in two simulator test runs. The catalog picker and Jobs list visual experiments are also excluded pending runtime validation.
- Signed archive passed `/private/tmp/thorbis-92-inbox-final/audit-release.py`; Tap to Pay remains disabled. The archive's signature and embedded profile were audited; the distribution export was not independently audited.
- Xcode reported upload success on 2026-10-30. Apple warned that the Stripe Terminal framework dSYM was missing, limiting symbolication for that framework. Build processing and group assignment must be verified in App Store Connect.
