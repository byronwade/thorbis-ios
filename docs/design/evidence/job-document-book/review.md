# Fresh whole-branch review

Base e7ce5cd93853ae590e172cc53ca21eba59171dbd; working tree after c011ca7.
One read-only review on gpt-6-astra xhigh. No source/index/branch changes by reviewer.

## Findings

- Important: stale→fresh unchanged estimate does not restart issued-term task; refresh can leave no terms or review action. Include freshness in task identity.
- Important: paid unsigned invoices lose existing signing entry. Restore signing eligibility for issued/paid, preserve issued+due payment gates.
- Minor (root regraded Important): failed estimate amount projection still renders unchecked line multiplication and omits totals. Canonical bounds exclude this fault, but explicit checked-money requirement must safely refuse malformed paper. Show unavailable state and no decision.
- Minor (root regraded Important): current-revision Signed by evidence label disappears in book. User requires feature retention; restore label.

No Critical findings. Root accepts all four for one regression/fix pass; readiness is with fixes until that pass qualifies.

## Declined to judge and root rulings

- Live signature/provider/biometric and TestFlight readiness require separate actual evidence; fixture/source review does not qualify them.
- Physical VoiceOver, device performance and representative large data remain untested in this review; phone/iPad simulator evidence is recorded separately.
- Quantity0/non-USD compatibility: canonical schema quantities1–100000 and USD verified in local TanStack domain schemas and native contract audit; stricter projection does not remove supported inputs.
- C1–C3 add-ons, persistent offline/native capability expansion remain required future work, not delivered by this book batch.
- Roadmap research is a sequencing document that activates nothing; exact platform/provider qualification remains future work.

## Root disposition after the single fix pass

All four accepted findings have native RED→GREEN evidence; final important suite95/95 and final iPad large-text1/1 pass, with172matchingSwift fingerprints. No deferred Minor remains. One additional shared-card large-type issue was reproduced and fixed through the same native regression process. This disposition is verification by the implementer, not a second independent review.
