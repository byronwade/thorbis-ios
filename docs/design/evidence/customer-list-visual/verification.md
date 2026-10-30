# Customer list visual pass

The customer-list row uses initials derived from the real name as its visual identity, and shows the relevant job's actual status in words alongside the status symbol. It keeps the existing customer link, context actions, count and visit selection. The shared Paper customer-list export is `docs/design/paper-VNB-0.json`; the visual adaptation uses the existing native typography and semantic brand tokens.

- Generic iOS Simulator build: passed, `/private/tmp/customer-list-visual-final-build.log`.
- Focused customer-row navigation and spoken status UI test: pre-change failed as expected, and post-change passed on iPhone SE, `/private/tmp/customer-list-visual-green.xcresult` (one test).
- Dark and light iPhone SE preview captures: `dark.png` and `light.png`; inspected with sample data.
- Largest Dynamic Type, VoiceOver, RTL, iPad and live workspace data were not verified by this pass. Preview screenshots do not establish production data behavior.
- The pre-change test process remained in Xcode's simulator diagnostic finalization after its failing case; that does not affect the separate completed green test.
