# Public estimate amount correction (held candidate)

The public signing API sends USD integer minor units. The public estimate screen previously formatted these values as dollars. This candidate validates the wire amounts and quantities before conversion, displays exact USD cents including discounts, and prevents approval when an amount or currency cannot be verified. A decimal JSON representation of an integral amount remains supported.

This is staged, not a TestFlight release. Rendered UI, shared handoff/review compatibility and iOS test results must be recorded against the final source before release. Issued HTML is rendered separately; this change does not alter the server's issued paper or add customer shopping functionality.

Foundation `JSONDecoder` parses numbers into a finite-precision Decimal: exceptionally long fractional numeric tokens may round before validation. The existing server contract emits bounded integer amounts and quantities; this candidate does not claim arbitrary untrusted JSON-token precision. Client validation is defense in depth, not a substitute for that contract.
