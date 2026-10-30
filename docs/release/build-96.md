# Build 96 — customer hand-back at large text sizes

Runtime source: `9193fa5d61ed435d874f669f527955249f7a2026`.

The customer hand-back action can grow and wrap its label at large Dynamic Type sizes, preserving the customer touch target and protected hand-back behavior.

Clean-source qualification: 9 release-note unit tests and 5 selected customer hand-back UI tests passed on the iPhone SE simulator. An independent review covered the four call sites. The signed archive passed source fingerprint, build number, code signing, privacy description, preview exclusion and payment-gate checks. Xcode uploaded the build to App Store Connect on October 30, 2026. Apple processing and tester availability must be verified separately.

Known limits: this does not fix the separate estimate review footer clipping at the largest text size. Physical-device, iPad and VoiceOver testing remain outstanding. Tap to Pay remains disabled pending qualification. The upload reported a missing StripeTerminal dSYM; the distribution export was not independently audited.

App Store Connect subsequently showed build 96 processing complete, assigned to Internal Testers (2), with its What to Test note saved. Build page: https://appstoreconnect.apple.com/teams/1f7ffdae-c53e-4d57-a97b-cc8cbc4760a8/apps/6827337706/testflight/ios/606403b9-9de5-4eb0-9366-28790bf754f8
