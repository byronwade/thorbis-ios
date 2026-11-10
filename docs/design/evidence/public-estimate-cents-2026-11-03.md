# Public estimate amount correction (held candidate)

The public signing API sends USD integer minor units. The public estimate screen previously formatted these values as dollars. This candidate validates the wire amounts and quantities before conversion, displays exact USD cents including discounts, and prevents approval when an amount or currency cannot be verified. A decimal JSON representation of an integral amount remains supported.

This is staged, not a TestFlight release. Rendered UI, shared handoff/review compatibility and iOS test results must be recorded against the final source before release. Issued HTML is rendered separately; this change does not alter the server's issued paper or add customer shopping functionality.

Foundation `JSONDecoder` parses numbers into a finite-precision Decimal: exceptionally long fractional numeric tokens may round before validation. The existing server contract emits bounded integer amounts and quantities; this candidate does not claim arbitrary untrusted JSON-token precision. Client validation is defense in depth, not a substitute for that contract.

## Verification on 2026-11-03

The release-base fixture run (`/private/tmp/thorbis-public-estimate-cents-red.log`) reproduced the wrong `$9,500.00` display for a $95 estimate and the wrong option/approval amount, as well as rejection-test failures. On source `7985e7b`, 44 focused unit tests passed: customer review (12), public action (16), money (3), wire amounts (4), and What's New (9). The first UI run failed because the total identifier appeared on both the combined accessibility element and its child, and the footer exposed the enclosing identifier. The result-bundle hierarchy confirmed the disabled footer and explanation existed; no UI success is claimed from that run.

On source `add9c08ba8e3824f3bede067f6c59f515e40f9d5`, a selector-only follow-up matched the exact total or footer label and retained the explanation assertions. The targeted simulator run (`/private/tmp/thorbis-public-cents-rerun.log`, result bundle `/tmp/thorbis-public-estimate-cents-derived/Logs/Test/Test-Thorbis-2026.11.03_20-39-58--0500.xcresult`) passed 26 job handoff tests and all 4 UI cases: USD total and option, discount, unsupported signed currency, and unsupported plain-approval currency. SHA-256 manifests before and after the rerun match (`/private/tmp/thorbis-public-cents-rerun-before.sha` and `/private/tmp/thorbis-public-cents-rerun-after.sha`); the previous unit-run manifests also match. The follow-up changed test selectors only, not production behavior.

These are simulator and fixture checks; live server documents, physical-device rendering and VoiceOver were not verified. The server's bounded integer USD contract and the Decimal parsing limit above remain material assumptions. No TestFlight upload or availability is implied by this evidence.
