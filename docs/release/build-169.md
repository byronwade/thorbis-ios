# TestFlight upload 1.0 (169)

Xcode reported **Upload succeeded** and **Uploaded package is processing** on November 5, 2026. Processing and tester-group availability have not been independently verified because local browser access was disabled.

The signed archive is based on release merge `650a6e4124b7a22d227ca5315cab8c76c2b25c8e`. Its Git tree `bb435bbe1dd9452a0c964785085670c53fe52ddd` matches the qualified candidate for PR #318. The release aligns the native drawer with implemented web workspace navigation and adds device-local, freshly authorized job and customer favorites, while preserving the invoice-create and existing menu features. Web destinations not implemented in iOS are absent; page and financial-record favorites are not included.

The combined candidate passed 69 focused unit tests and 13 mounted iPhone UI tests. Two iPad-only UI tests were skipped; iPad UI, physical-device behavior and VoiceOver have not been independently verified. The simulator checkout used a checksum-verified local Stripe package override for testing only; the signed archive used the official Stripe Terminal 5.8.1 package.

The archive at `/private/tmp/thorbis-release169-sidebar-artifact/Thorbis.xcarchive` reports app build 169 and passes strict code-sign verification. The Tap to Pay build audit passed with Tap to Pay disabled. The upload reported a missing Stripe Terminal framework dSYM warning.
