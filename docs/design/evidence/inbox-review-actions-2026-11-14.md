# Inbox draft action review fixes — 14 November 2026

Based on release `462ef5534741ab4f4adbf52745bdcbe77f481371`, this candidate addresses two automated PR 560 findings. A failed or blocked discard of a one-message email draft no longer closes its thread; the stored draft remains intact. When Inbox cannot start a text because local storage is blocked, the compose sheet explains the recovery path and keeps the entered phone number and name. Existing text conversations still use the prior recovery behavior. No message is transmitted.

Tested tracked diff SHA-256 before adding this evidence: `56f8c6ca2ac6f7aedbaac17968a1f2b02f7d9a5465ac2287747e9158537cf39e`.

- `/private/tmp/thorbis-inbox-review560-red-1114.xcresult`: 2 UI tests executed, both failed at the intended assertions: the failed discard closed the draft, and Start text failed without feedback. The test-only fixtures provide a one-message email draft and a previously blocked local store.
- `/private/tmp/thorbis-inbox-review560-green-1114.xcresult`: 15 tests executed, 15 passed. This included both UI regressions, failed and successful durable email-draft discard, Keychain recovery, the normal text-draft path, and What's New. The simulator app was ad-hoc signed using `CODE_SIGNING_ALLOWED=YES CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY=- DEVELOPMENT_TEAM= PROVISIONING_PROFILE_SPECIFIER= -jobs 2`.

The run used an iPhone SE simulator with iOS 26.3.1. It does not qualify the complete Inbox or prove physical-device or VoiceOver behavior. Storage-blocked recovery still requires copying unsaved work before restarting and checking what was saved. Provider-connected messaging and TestFlight delivery remain separate.

After the 15-test run, three verification-only UI tests were added; no production source changed. `/private/tmp/thorbis-inbox-review560-paths-1114.xcresult` executed 3 tests and passed 3: a successful single-draft discard closes the thread, a blocked store reopens an existing text for recovery, and the first failed write for a new text opens an in-memory composer with a visible warning and copy action. This last path is distinct from starting a new text after the store is already blocked, which remains in the compose sheet and shows the new error. The final tracked diff including these tests has SHA-256 `2ca0322d060b04c2646ae35cb07e2216846692988e0da0849bc3289cb0cb0fe6`.

Independent read-only review found no material regression and requested the first-write path check above. Physical-device and VoiceOver behavior remain unverified.
