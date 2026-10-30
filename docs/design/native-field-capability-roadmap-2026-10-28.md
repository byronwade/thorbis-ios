# Native field capability roadmap — 28 October 2026

This is a research and sequencing document, not a feature activation or release certificate. The current job document/discount/payment TestFlight batch remains first. No runtime, tests, provider settings, permissions, Linear states, secrets, or release gates were changed for this roadmap.

Evidence: native checkout at `c011ca7` plus in-progress work, source reconnaissance, live Linear reads on 28 October, and official Apple documentation below. Existing means code was found, not that this pass executed device acceptance. Follow [golden rules](ios-golden-rules.md) and [implementation process](ios-implementation-process.md). The project deployment target is **iOS 18.0** (`project.yml`); framework introduction dates below do not lower it or certify every newer API in that framework. Check the installed SDK and runtime availability when implementing.

## Delivery order

1. **Finish and verify the current customer job document/payment batch.** Preserve invoice identity, revisions, discounts, payment reconciliation, explicit navigation, and customer hand-back.
2. **Make existing field work survive interruption:** scope and harden the local media queue, persist scanned documents, prove relaunch/retry/conflict behavior, and establish performance baselines.
3. **Make the existing native entry points trustworthy:** stale/redacted widgets and Live Activities, identity-safe cold links, contextual notification permission, useful haptic semantics.
4. **Add small native conveniences:** explicit Calendar export and user-reviewed email/text composition, followed by photo annotation and equipment-label OCR review.
5. **Qualify separately:** caller ID/VoIP, remote Live Activity updates, measurement, and payment/provider exposure. These are not a switch that enables every iPhone capability.

## Linear authority and readiness

| Current work | Observed state / owner | Meaning for this roadmap |
| --- | --- | --- |
| [BYR-409 — Field mobile delivery](https://linear.app/byronwade/issue/BYR-409) | Backlog; Byron Wade | Field app remains distinct from Network. Coordinated public MGP release is a larger gate than one TestFlight batch. |
| [BYR-414 — MGP mobile parity](https://linear.app/byronwade/issue/BYR-414) | Backlog; Byron Wade | Owning umbrella for job-native conveniences and parity; dependencies remain unresolved. |
| [BYR-418 — Field release certification](https://linear.app/byronwade/issue/BYR-418) | Backlog; Byron Wade | Requires physical-device, offline, privacy, provider, and release evidence; cannot infer certification from source presence. |
| [BYR-416 — offline, push, deep links](https://linear.app/byronwade/issue/BYR-416) | Backlog; Byron Wade | Primary owner for isolation, durable queues, media, lock-screen privacy, and interruption coverage. |
| [BYR-1551 — APNs foundation](https://linear.app/byronwade/issue/BYR-1551) | Merged; Byron Wade | Description still says dark until configured and proven. Merge is not a live-delivery proof. |
| [BYR-1552 — booking call recordings](https://linear.app/byronwade/issue/BYR-1552) | In Progress; no assignee returned | Twilio/provider configuration, staged migration and recording notice are explicit prerequisites. Not caller ID or access to arbitrary phone calls. |
| [BYR-436 — Tap to Pay qualification](https://linear.app/byronwade/issue/BYR-436) | Backlog; Byron Wade | Latest note reports development-only approval, not distribution approval. Keep runtime policy false until exact entitlement/provider/device/merchant gates pass. |
| [BYR-473 — follow-up booking](https://linear.app/byronwade/issue/BYR-473) | Merged; Byron Wade | Canonical booked/office-review/rejected contract; source-complete does not prove mobile exposure. Apple Calendar cannot replace this authority. |
| [BYR-50](https://linear.app/byronwade/issue/BYR-50), [BYR-55](https://linear.app/byronwade/issue/BYR-55) — old Live Activity work/smoke | Canceled; Byron Wade | Historical Expo-pivot tickets. Do not reopen or claim them as current approval merely because this native repo contains ActivityKit. Link new scoped acceptance under current Field owners. |

The Linear context helper was attempted once and returned `Tool get_agent_context not found`; targeted issue reads succeeded. Calendar search found no dedicated current EventKit delivery issue. New narrow children/owners need normal planning, not guessed issue substitutions. Preserve held, not-released, not-entitled, and post-stage decisions; in particular this document does not unlock BYR-138-gated domains or BYR-861. Do not transition blocked work from this roadmap.

## Capability decisions

### Existing: Live Activities, Dynamic Island, widgets and Siri entry points

`JobLiveActivity.swift` starts one activity for en-route/arrived/in-progress/paused work, updates local state, ends the previous job, and carries waiting-to-sync state. `ThorbisWidgets/JobLiveActivityWidget.swift` renders Lock Screen and Dynamic Island layouts. `TodayJobsWidget.swift` reads a saved snapshot for small/medium/accessory widgets; refresh timing is system-controlled. `ThorbisIntents.swift` exposes **Open my next job** and **Show my schedule** through App Shortcuts. These open existing routes; they do not silently advance work or collect money.

**Next:** after a technician marks On my way, show the current job, truthful elapsed state, and a tap back to that job. Add deliberate stale/freshness semantics, privacy-minimized text, and sign-out/workspace-change cleanup proof before richer actions. Current activity content uses `staleDate: nil`; the widget and activity can display customer/job/place information. Review what is safe while locked, including expanded Dynamic Island. Verify cached snapshot age and denial/disabled recovery. Keep meaningful information in-app when the system hides the surface.

**Requires qualification:** remote updates require ActivityKit-specific APNs configuration, tokens, authorized backend updates and lifecycle handling; ordinary notification registration is not sufficient. No continuous networking or location entitlement is granted by ActivityKit. App Intents mutations, if later justified, must reuse canonical commands and explicit confirmation for consequential actions. Voice/shortcut access must not disclose another workspace's data.

**Support:** ActivityKit begins iOS 16.1, App Intents iOS 16, WidgetKit iOS 14; this app stays iOS 18+. Dynamic Island needs a supporting device; retain Lock Screen/in-app alternatives. User settings and system budgets apply. Keep activity data small (combined static/dynamic content up to 4 KB); do not treat a Live Activity as an all-day durable work record. Local UI can update offline while explicitly pending; authoritative remote changes cannot be guaranteed without connectivity. [Apple ActivityKit](https://developer.apple.com/documentation/activitykit/displaying-live-data-with-live-activities), [App Intents](https://developer.apple.com/documentation/appintents), [WidgetKit](https://developer.apple.com/documentation/widgetkit).

### Next: Calendar export, with deliberate consent

No EventKit integration was found in the source search. Start with **Add this confirmed visit to Calendar** on the job: prefill title, confirmed time, timezone, minimal place, and an authorized app link; let the person choose/edit/save in native `EKEventEditViewController`. Do not invent a duration when the canonical record lacks it. Label this as a personal calendar copy, with no promise of automatic rescheduling or team capacity reservation.

On iOS 17+, EventKitUI can present this editor without broad Calendar access. Direct saves require write-only authorization and its purpose string; reading calendars requires full access and a separate justified workflow. Cancellation/denial must leave Thorbis unchanged. Calendar storage may work locally, but downstream calendar-account sync is outside Thorbis confirmation. Later synchronization needs an explicit dedupe/update/removal policy and privacy review. Owner: BYR-414 convenience scope; actual booking remains BYR-473/canonical scheduling. [Apple EventKit access guidance](https://developer.apple.com/documentation/technotes/tn3153-adopting-api-changes-for-eventkit-in-ios-macos-and-watchos).

### Existing handoff / Next: native mail and message composition

`JobBrief.swift`, `PaperComponents.swift` and customer views contain `tel:`, `sms:` and `mailto:` handoffs. No `MFMailComposeViewController` or `MFMessageComposeViewController` integration was found. Next narrow delivery: **Share this issued document** or **Text this job contact**, with a reviewed recipient, approved content/link and native composer. Check `canSendMail`/`canSendText`, retain cancel, and provide a copy/share fallback when unavailable. No mailbox-reading permission is needed for composition; do not request Contacts merely to use a known authorized job contact.

The person sends explicitly. Composer completion is not delivery, read receipt, canonical invoice-issued state, or organization-owned communications audit. Mail may queue in the person's Mail outbox while offline. Provider-managed transactional sends remain a distinct server capability. Use the existing app baseline (iOS 18+) and current MessageUI availability; no new dependency is needed. [Apple MessageUI](https://developer.apple.com/documentation/messageui), [mail composer delivery boundary](https://developer.apple.com/documentation/messageui/mfmailcomposeviewcontroller).

### Requires qualification: CallKit and caller ID

No CallKit/Call Directory extension was found. Existing `BookingCall.swift` is job-linked playback/server data, and BYR-1552 owns Twilio recording. **CallKit provides system UI for an app's VoIP service; it does not provide a phone carrier service or permission to record arbitrary cellular calls.** Keep simple Call contact direct.

Possible later increment: opt-in identification of an authorized customer number on an incoming call. A local Call Directory extension (iOS 10+) needs explicit user enablement, normalized phone data, bounded exports and revocation/tenant-switch deletion rules. It can use a preloaded local directory offline; it must not dump the CRM into shared storage or infer company authority from a phone number.

Live Caller ID Lookup is a separate iOS 18-era integration: server-maintained data, privacy-preserving lookup, Apple relay endpoint validation, extension configuration and user enablement. Exact symbol/runtime support must be checked before implementation. A private multi-tenant CRM needs a justified disclosure/authorization design before any server qualification request. VoIP calling additionally needs a real provider/signaling/media stack, appropriate microphone permission and genuine-call push handling. No such provider or Apple actions are authorized by this document. [Apple CallKit](https://developer.apple.com/documentation/callkit), [Call Directory](https://developer.apple.com/documentation/callkit/cxcalldirectoryprovider), [Live Caller ID requirements](https://developer.apple.com/documentation/identitylookup/getting-up-to-date-calling-and-blocking-information-for-your-app).

### Existing capture / Next annotation and OCR / Qualified measurement

`MediaView.swift` has a native camera, Photos picker, VisionKit multipage document scan to PDF, Quick Look preview, before/after tags and durable pending JPEG photos. Capture uses contextual camera permission; Photos selection should remain system-picker based rather than requesting full library access. Document camera starts iOS 13; check device support. Existing camera purpose text should cover actual scanning use before expansion.

**Next useful job workflow:** photograph a damaged part, retain the original, add a separate annotation derivative, confirm the note and upload state on the same job. PencilKit (iOS 13+) can capture finger/Pencil drawings, but a finished editor still needs crop/rotate/undo/cancel/accessibility and original-to-derivative provenance. Do not imply Quick Look automatically supplies a persistent full photo editor. A second small increment can recognize an equipment label using Vision text recognition (iOS 13+): suggest serial/model text with a review step; never silently change equipment or financial data. Bound image dimensions, process off the UI path and discard unneeded OCR intermediate data. On-device recognition can help offline; recognition confidence is not truth. [Apple VisionKit](https://developer.apple.com/documentation/visionkit), [PencilKit](https://developer.apple.com/documentation/pencilkit), [Vision text recognition](https://developer.apple.com/documentation/vision/vnrecognizetextrequest).

**Requires qualification:** an AR measurement flow needs a concrete trade use case and device/accuracy evidence. RoomPlan (iOS 16+) uses camera and LiDAR on supported devices, not every iPhone; ARKit configurations must check runtime support. Save approximate dimensions, units, capture provenance and technician confirmation, with manual entry available. Do not use scans as certified measurements or automatically price material quantities. Keep heavy capture short, support interruption/thermal limits and avoid continuous scene retention. No ARKit/RoomPlan implementation was found. [Apple RoomPlan requirements](https://developer.apple.com/augmented-reality/roomplan/).

### Existing: contextual haptics; Next consistency

Source already uses SwiftUI `sensoryFeedback` for selection/success in job, estimate and workspace flows; payment collection also uses `UINotificationFeedbackGenerator`. SwiftUI sensory feedback begins iOS 17, within the app baseline. No separate permission is needed, but hardware/settings determine whether feedback is felt.

Next: define a small shared mapping for selection, durable local save, server-confirmed success and rejection; check it across the current document workflow. A queued operation must not give a misleading payment-success cue. Keep visible words and accessible feedback; avoid haptics on scrolling/every background retry. Test on physical iPhone and with feedback unavailable. [Apple sensory feedback](https://developer.apple.com/documentation/swiftui/view/sensoryfeedback(_:trigger:)).

### Existing partial offline foundation; Next durable media and measured performance

`OfflineSupport.swift` persists actor/organization-scoped workspace jobs/customers and job detail/notes files. `FieldOutbox` and its tests cover progress/notes, stable envelopes, batch limits, rejection handling and reconnect behavior. This does not establish a complete transactional local database for every domain. Do not widen offline money/provider/signature semantics.

`PendingPhotoStore` saves JPEG bytes and metadata in two separate atomic writes; metadata contains job ID but no explicit actor/tenant/app/environment identity. Job detail cache keys are job IDs. These observations require lifecycle/isolation verification, not an unproven assertion of a leak. Scanned PDFs follow `selectedData`/direct upload rather than the durable photo queue. No background URLSession or MetricKit integration was found by targeted source search.

**First narrow deliverable:** persist one job-bound scanned PDF through force-close and offline retry; first establish explicit identity ownership, atomic commit/recovery, storage failures, original retention, dedupe and cleanup behavior for the media queue it uses. Recheck permission after reconnect. Local save, queued, sending, confirmed, conflict and failed remain distinct. Then add file-backed background transfer only where the current upload-grant/finalize contract supports reconnect and grant renewal. Background URLSession can transfer while suspended; file uploads are required after process exit. System scheduling, user force-quit and network conditions prevent a promise of exact timing. BGTaskScheduler (iOS 13+) is opportunistic housekeeping, not a constant sync daemon. [Apple background transfer model](https://developer.apple.com/documentation/foundation/downloading-files-in-the-background).

**Parallel measurement deliverable:** measure cached Today/job opening, thumbnail processing, scrolling, queue age and reconnection on a representative older supported physical iPhone with a large synthetic workspace. Add bounded signposts and MetricKit subscription using APIs available at iOS 18 (MetricKit begins iOS 13); availability-gate newer APIs rather than copying the newest documentation blindly. MetricKit's aggregated reports are delayed, not real-time UI latency instrumentation. Exclude names, addresses, notes, photo contents, tokens and provider identifiers from diagnostics. [Apple MetricKit](https://developer.apple.com/documentation/metrickit/monitoring-app-performance-with-metrickit).

## Acceptance for each next batch

Each proposed increment needs a small approved design/plan and current owning issue before runtime work. Reuse native shared controls and canonical commands. Collect success, denial/cancel, unsupported hardware, offline, relaunch, stale identity and large-text/VoiceOver evidence appropriate to the feature. Refresh server readiness immediately before exposure; never promote a provider because its SDK compiles.

The golden-rule targets—cached Today under 500 ms, cached job under 300 ms, local feedback/search under 100 ms, thumbnail feedback under 500 ms—are measurement goals, not results from this pass. Physical-device measurement, permission journeys, provider delivery and archive entitlement verification were **not run** for this documentation-only task. The immediate build must pass its own release process independently of this roadmap.
