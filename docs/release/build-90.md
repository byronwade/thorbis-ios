# TestFlight 1.0 (90)

Uploaded 2026-10-30 from source `dccf42876c8c34f045bffcb1646ea670486d9725`. Apple processing completed and the build is assigned to the Internal Testers group (2 testers). [Open build 90](https://appstoreconnect.apple.com/teams/1f7ffdae-c53e-4d57-a97b-cc8cbc4760a8/apps/6827337706/testflight/ios/be4af788-a15a-4cba-b874-b3bd1a4cc845).

Customer and job screens have clearer headers, job selection and search, plus large-text adaptations. This build includes current main as well as the earlier price book release branch. Build 89 was uploaded independently; its source has not been identified.

Validation: merged simulator build, signed archive and artifact audit succeeded. Customer handoff and job-scoped document paging passed on the 17 Pro; large-text customer names and actions, customer location selection, and job payment-action checks passed on the SE. The large-text job section chooser and adaptive-control UI checks were not verified in the exact release build: simulator service failures and test setup failures interrupted the runs. Follow-up checks remain pending. The signed archive has Tap to Pay disabled; this build does not establish live Tap to Pay availability. Apple reported a missing Stripe Terminal dSYM on upload, which limits symbolication of crashes in that framework. The distribution export was not independently audited.
