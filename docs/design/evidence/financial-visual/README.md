# Financial document rows

Estimate, invoice and billing schedule list rows use the existing Thorbis brand surface and native symbols to identify document types. Amounts, customer and reference text, status words, navigation and calculations remain unchanged. Metadata wraps to preserve the full billing terms; at accessibility text sizes the amount moves beneath the identity instead of competing for horizontal space.

The job estimate and invoice Paper exports (`paper-R5C-0.json`, `paper-R7U-0.json`) supply document hierarchy and money treatment; the typed document markers are a native adaptation requested to make text-heavy pages more visual. No product or job photos are fabricated.

A generic iOS Simulator build passed. The final-source iPhone SE previews show light billing with full retainage and dark invoices at accessibility XXXL in the adjacent screenshots. Standard dark estimate and invoice screenshots were also captured before the final metadata wrapping change; they are not evidence for the exact final source. Row navigation, VoiceOver, iPad, and live data were not verified in this pass.

Follow-up: a long customer name with a $1,234,787.89 sample invoice exposed truncation at standard text size. The revised row places the amount below the identity when there is insufficient width and allows the name to wrap fully. The before/after images show the issue and fix on iPhone SE. A focused UI test passed (1 test), confirming the complete row label remains available and opens the invoice. The extra amount is a DEBUG-only fixture; it is not real customer data.
