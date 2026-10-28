# Thorbis 1.0 (1)

Source commit: `0b93ab3167a087c02c717ff42714a62ecca87da6`.
Bundle: `com.thorbis.field`; Apple team: `T677262U5B`; App Store Connect app: `6827337706`.

Built with Xcode 26.3 and Swift 6 language mode / complete strict concurrency for iOS 17 and later, iPhone and iPad.

## Verification

98 tests passed, zero failed or skipped, on iPad Pro 13-inch (M5), iOS 26.0. The final suite includes transport pagination, session authority and invalidation, field and financial request contracts, media lifecycle, document cleanup, workspace APIs, local partitioning and assignment pagination. Earlier Release-specific API run: 18 tests passed. Both iPhone and iPad login layouts launched successfully. Authenticated app workflows have not yet been verified against the live account.

Final result bundle: `/private/tmp/thorbis-all-tests-5.xcresult`.
Archive: `/private/tmp/Thorbis-upload.xcarchive`.
`codesign --verify --deep --strict` passed for the archived app.

## Upload

On 26 October 2026 at 19:50 EDT (23:50 UTC), `xcodebuild -exportArchive` reported `Upload succeeded`, `Uploaded Thorbis`, and `EXPORT SUCCEEDED`. The upload used the repository's `ExportOptions.plist` with automatic signing. An expired secondary Xcode account warning did not prevent successful upload.

Internal group `Internal Testers` (`32e003bb-3a52-47c2-b84c-2e7cd7459b01`) has the account owner added and automatic distribution enabled. Apple processing completed: App Store Connect displays build 1 under version 1.0, linked to Internal Testers. Build ID: `1dc4aad6-0b05-44e1-9f95-a4a0d55ace71`. The group shows 1 tester, 1 build and the account owner status Invited. External status is Ready to Submit; no external or public App Store review was submitted.

## Reproduction

Generate the project using `xcodegen generate`. Run `xcodebuild test` on an installed iOS Simulator with `CODE_SIGNING_ALLOWED=NO` and `-parallel-testing-enabled NO`. Use a derived-data path under `/private/tmp` on this host to avoid Documents FileProvider metadata interfering with signing.

Archive the `Thorbis` scheme in Release for `generic/platform=iOS`, with automatic signing and the configured team. Export with `xcodebuild -exportArchive -archivePath <archive> -exportOptionsPlist docs/release/ExportOptions.plist -exportPath <output> -allowProvisioningUpdates`.

Scope and remaining work: [beta-coverage.md](beta-coverage.md). This build is a staff beta, not a complete native port of every Thorbis product.
