# Native payment refunds

## Intent

Thorbis Field operators need to reverse an eligible recorded payment from the payment detail already shown on an invoice. Refunds move money or reverse a cash/check ledger entry, so the native flow must keep the upstream reason requirement, authorization boundary, and honest pending states.

## Source of truth

- Upstream web action: `Thorbis-TanStack/domains/payments/src/activity-actions.ts`. It exposes `Refund payment` only for a freshly loaded payment with status `recorded` and no prior refunded amount. It requires `invoice.refund`, an online command, a reason, and high-risk confirmation.
- Canonical API: `POST /v1/payments/{id}/refund`, `payments` feature, `invoice.refund` capability, body `{ "reason": string }` (trimmed 3–2000 characters). The server returns the canonical payment when complete or HTTP 202 with `outcome: "pending" | "reconciliation_required"` and the payment ID. The server remains authoritative for amount bounds, provider binding, idempotency, and ledger reversal.
- Provider workflow: `Thorbis-TanStack/domains/payments/src/commands.ts` and `services/api/src/composition/payment-workflows.ts`. Only full-payment refunds are offered by this action; a partially refunded payment is not eligible for another native refund. Existing cash/check records may reverse locally; a linked processor payment uses its original connected account.
- Native product reference: `Thorbis-TanStack/apps/web/src/features/activity-actions.tsx` and `apps/web/src/features/invoice-detail.tsx`.
- Thorbis design references consulted 2026-10-27: [iOS and iPadOS](https://design.thorbis.com/platforms/ios) and [Native contract D-025](https://design.thorbis.com/skills/native). The iOS page states that native tabs are destinations, system navigation owns bars/sheets, and the native contract owns the HIG rules. The app uses the invoice payment-detail sheet, standard iOS navigation and form controls, and the existing Thorbis semantic colors and spacing. There is no dedicated Paper refund artboard.
- Apple topics consulted 2026-10-27: [Alerts](https://developer.apple.com/design/human-interface-guidelines/alerts), [Action sheets](https://developer.apple.com/design/human-interface-guidelines/action-sheets), [Entering data](https://developer.apple.com/design/human-interface-guidelines/entering-data), and SwiftUI [confirmation dialogs](https://developer.apple.com/documentation/swiftui/view/confirmationdialog(_:ispresented:titlevisibility:actions:)).

## Platform scope and applicable native rules

App: Thorbis Field. Platforms: iOS and iPadOS. Supported OS: iOS/iPadOS 17 and later (`IPHONEOS_DEPLOYMENT_TARGET` 17.0). Affected surfaces: invoice payment history, payment detail, refund reason entry, review/confirmation, and post-action status.

Applicable Thorbis D-025 rules: HIG-001 through HIG-017, HIG-020 through HIG-022. HIG-018 (device performance) remains applicable to a mobile release and requires physical-device measurements, including a lower-performance supported device; those measurements are not available in this simulator-only implementation pass and remain a release gate. HIG-019 (media) is not applicable because this flow handles no media. The HIG-021 evidence matrix must cover all HIG-001–HIG-022 and record those distinctions.

## Required behavior

1. Show the refund entry only when the current workspace grants `invoice.refund` for the `payments` feature and the loaded payment is `recorded` with no prior refund. Hide it for refunded and partially refunded payments. The native capability/feature check is only a visibility hint: the local catalog has no payment-specific maximum-refund condition. The server alone decides the amount-specific authorization and final eligibility. Handle server 403/409 refusals without implying the action was authorized.
2. Require an online request and a trimmed reason of 3–2000 characters. Keep the reason in a Keychain item scoped to the actor, organization, and payment before submission. Use `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`; do not sync it to iCloud or store card/provider credentials. Retain the exact reason for pending, reconciliation-required, and uncertain network outcomes across app termination. Remove a draft by explicit user discard; an attempted but unresolved refund intent cannot be discarded because the exact reason is required to safely replay the same request. Remove a submitted intent only after canonical refund confirmation. Treat Keychain read/write failures as recoverable errors and fail closed: do not submit unless the exact intent was securely saved.
3. Display the exact original payment amount and state that this action refunds the full payment. Do not offer a partial amount field or imply that a refund is complete before canonical confirmation.
4. Require an explicit native destructive confirmation with a clear Cancel action. A commit sends only the validated reason to `/v1/payments/{paymentId}/refund`.
5. For a canonical payment response, refresh the invoice and complete payment history. Show full or partial refund state only from the server response or refreshed canonical record.
6. For HTTP 202, distinguish pending from reconciliation-required, persist the outcome and exact reason, and keep the payment unresolved. Provide an explicit `Check refund status` action that replays the identical payment ID and reason: the upstream workflow returns the pinned pending/reconciliation result without issuing a second provider refund, and returns canonical payment state once complete. This replay is a recovery command, not a read-only GET. Do not auto-retry or report a completed refund.
7. For a 4xx refusal or uncertain network failure, retain the exact reason, keep payment history as the source of truth, and show the error in context. An explicit retry must use the same reason. A reason may be discarded only while still a draft; an unresolved submitted request remains available for same-reason recovery so another refund cannot be started with a different reason. Never make a hidden or automatic retry of this online money action.
8. If the reason form is dismissed before submission, preserve its secure draft and restore it when reopened; provide an explicit discard action. Prevent interactive dismissal while a request is in flight. Verify keyboard/focus behavior and keep the primary action reachable above the keyboard.
9. Preserve standard iOS back, sheet dismissal, safe-area, VoiceOver, Dynamic Type, and iPad adaptive behavior. App-owned controls retain at least 44 × 44 pt hit areas.

## Non-goals

- Partial-refund amount entry, card entry, payment collection, customer-facing checkout, receipt delivery, email/SMS, or provider selection.
- Changes to server money logic, payment authorization, or feature configuration.
- Claiming a pending provider outcome is a refund, or using the invoice's aggregate `amountPaid` as proof that this specific refund completed.

## Acceptance evidence

- API contract tests prove the path, trimmed reason body, canonical 200 response, accepted 202 outcomes, and refusal behavior.
- Model/policy tests prove eligibility, visibility gating, no partial-refund action, secure intent retention/recovery, successful canonical refresh, and distinct pending/reconciliation/error states.
- iPhone 17 Pro simulator build/tests pass; invoice payment detail and reason/confirmation states are visually inspected with intercepted, read-only Paper fixtures.
- Release/design evidence carries an HIG-001–HIG-022 applicability matrix and reports any physical-device or accessibility checks not performed as not tested. Physical-device HIG-018 measurements remain a release gate. This slice does not establish whole-app parity or a release decision.
