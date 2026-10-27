# Job detail action contracts

Source of truth: `Thorbis-TanStack/services/api/openapi.json` for route permission/feature metadata; `services/api/src/app.ts` for response wrappers; `domains/jobs/src/{schemas,commands,queries,closeout,workflow}.ts`, `domains/media/src/{schemas,commands,queries,ports}.ts`, and `domains/scheduling/src/{schemas,booking}.ts` for actual input and output. OpenAPI marks most success responses simply `2XX Success`, so the response shapes below come from handlers/domain return values.

| Endpoint | Capability / feature | Request JSON | Success response |
|---|---|---|---|
| `POST /v1/jobs/{id}/assign` | `job.assign` / `jobs` | `{userId:uuid, expectedAssigneeId?:uuid\|null}` | updated `Job` |
| `POST /v1/jobs/{id}/schedule` | `job.assign` / `jobs` | `{scheduledFor:ISO8601, timeZone?:IANA, arrivalWindowEndsAt?:ISO8601\|null, expectedPriorScheduledFor?:ISO8601\|null}` | updated `Job` |
| `POST /v1/jobs/{id}/reschedule/undo` | `job.assign` / `job_schedule_cycle_undo` | `{sourceAuditId:uuid}` from server Activity action | updated `Job` |
| `POST /v1/jobs/{id}/complete` | `job.complete` / `jobs`; `job.edit` also required when `unpaidDisposition` present | empty object or `{notes?:string, unpaidDisposition?:{reasonCode,reason,followUpNextAction}}` | updated `Job` |
| `POST /v1/jobs/{id}/cancel` | `job.cancel` / `jobs` | empty or `{}` only | updated `Job` |
| `GET /v1/jobs/closeout-policy` | `job.view` / `jobs` | — | persisted `CloseoutPolicy`, or `{organizationId,requireNotes:false,requiredPhotoCount:0,requiredChecks:[]}` |
| `GET /v1/jobs/{id}/closeout` | `job.view` / `jobs` | — | closeout view described below |
| `POST /v1/jobs/{id}/checks` | `job.edit` / `jobs` | `{checkKey:string}` | `CloseoutCheck` with 201 |
| `GET /v1/jobs/{id}/followups` | `job.view` / `jobs` | — | `{items:JobFollowUpView[]}` |
| `POST /v1/jobs/{id}/followups` | `job.edit` / `jobs` | `{kind:"office_scheduling"\|"notify_office",reason:string,nextAction:string,ownerUserId?:uuid,requestedFor?:ISO8601}` | `JobFollowUp` with 201 |
| `POST /v1/jobs/{id}/followups/{followUpId}/resolve` | `job.assign` / `jobs` | empty or `{}` only | updated `JobFollowUp` |
| `POST /v1/jobs/{id}/followups/{followUpId}/book` | `job.book.followup` / `jobs` | `{intentId:uuid,requestedWindow:{startsAt,endsAt},timeZone:IANA,serviceNeed:string,requiredTraitIds:string[]}` | `{outcome:"booked",decision,appointment}` or `{outcome:"office_review_required",decision,officeReview}` with 201 |

`assign` does **not** start work. An unchanged assignee is an idempotent replay; when `expectedAssigneeId` is supplied and stale, 409 `dispatch_changed`. Scheduling requires a real instant. `arrivalWindowEndsAt` must follow `scheduledFor` by at most 12 hours. An unchanged schedule is a no-op; a stale `expectedPriorScheduledFor` returns 409 `dispatch_changed`. The Job uses `scheduledFor`, not `scheduledAt`.

The job detail response serves `allowedTransitions`; `complete` and `cancel` are separate commands despite those states appearing in the list. `complete` refuses nonterminal illegal transitions and any unmet closeout requirement with a 409 whose detail names each requirement and its `nextAction`. It is idempotent for a previously accepted exact intent. `unpaidDisposition.reasonCode` is `customer_will_pay_later|office_collection_required|payment_attempt_failed|other`; `reason` and `followUpNextAction` trim to 1–2000 characters. It is accepted only when a configured `payment_or_unpaid_disposition` check has `allowUnpaidDisposition:true`, and the server creates an office follow-up with actor ownership. Never synthesize payment or a booked follow-up from this request.

`GET /v1/jobs/{id}/closeout` returns `{policy:{requireNotes,requiredPhotoCount,requiredChecks},facts:{noteCount,photoCount,acknowledgedCheckKeys,authorizationTarget,customerAuthorizationEvidence?},acknowledged:[{checkKey,acknowledgedByUserId,acknowledgedAt}],requirements:[CloseoutRequirementResult],unmet:[blocked result],completable:boolean}`. Each requirement has `requirement`, `kind` (`notes|photos|check|customer_authorization|payment_or_unpaid_disposition`), `outcome` (`not_required|satisfied|blocked`), `detail`, optional `nextAction` and optional `commercialSource:"schedule"`. The server intentionally strips invoice/payment evidence from this view; `job.view` does not grant `invoice.view`. `requiredChecks` contain `{key,label,kind?,allowUnpaidDisposition?}`. A normal check can be acknowledged; `customer_authorization` needs bound signed-estimate evidence and cannot be satisfied by `POST /checks` alone.

Follow-ups are durable office work. A `requestedFor` timestamp is desired review time, **not** proof of an appointment. Persisted rows include historical `technician_scheduled`, but new requests may only use `office_scheduling` or `notify_office`. Each row has `id,organizationId,jobId,kind,reason,nextAction,ownerUserId,status,createdByUserId,createdAt` plus optional `requestedFor,revision,resolvedAt,resolvedByUserId`. The list may add `scheduling` with `outcome:"booked"` and appointment or `outcome:"office_review_required"` and office review. Resolve is idempotent, but refuses while a canonical office review remains open. Booking is online-only; the server derives tenant/customer/location/assignee. Its requested window must end after start and span at most 24 hours; `serviceNeed` is 1–500 chars, traits at most 20. A booking attempt may legitimately return office review rather than an appointment.

## Media and photos

| Endpoint | Capability / feature | Request | Response |
|---|---|---|---|
| `POST /v1/jobs/{id}/media` | `job.edit` / `jobs` | JSON `{clientAssetId:uuid,kind:"photo"\|"video"\|"document"\|"scan",mime,sizeBytes,originalFilename,contentHash:64-lowercase-hex,capturedAt?,tags?,caption?}` | `{asset:MediaAsset,uploadTarget?}` or `{asset:MediaAsset,resumable?}` with 201 |
| `GET /v1/jobs/{id}/media` | `job.view` / `jobs` | `limit,cursor,tag,kind,includeArchived` query | `{items:MediaAsset[],nextCursor?,systemTags:string[]}` newest first |
| `GET /v1/media/{id}` | `job.view` / `jobs` | — | safe `MediaAssetView`, omitting uploader, content hash, and storage key |
| `POST /v1/media/{id}/confirm` | `job.edit` / `jobs` | body ignored by current HTTP handler; it forwards only `assetId` | updated `MediaAsset` |
| `GET /v1/media/{id}/download` | `job.view` / `jobs` | — | `{url,expiresAt}` for stored asset only |
| `POST /v1/media/{id}/tags` | `job.edit` / `jobs` | `{tags:string[] (max 20),caption?:string}` | updated `MediaAsset` |
| `POST /v1/media/{id}/archive` / `unarchive` | `job.edit` / `jobs` | no body | updated `MediaAsset` |
| `GET /v1/jobs/{id}/media/before-after` | `job.view` / `jobs` | — | `{items:BeforeAfterSet[]}` |
| `POST /v1/jobs/{id}/media/before-after` | `job.edit` / `jobs` | `{beforeAssetIds:uuid[] (1–10),afterAssetIds:uuid[] (0–10),caption?:string}` | `BeforeAfterSet` with 201 |
| `GET /v1/jobs/{id}/photos` | `job.view` / `jobs` | — | `{items:JobPhoto[]}` |
| `POST /v1/jobs/{id}/photos` | `job.note` / `jobs` | **raw image bytes**, MIME in `Content-Type` | `JobPhoto` with 201 |
| `GET /v1/jobs/{id}/photos/{photoId}` | `job.view` / `jobs` | — | raw image bytes |

The new media register response includes `uploadTarget:{url,method:"PUT",expiresAt,headers}` for <=8 MB; larger media gets `resumable:{uploadId,partSize,parts:[{partNumber,url,expiresAt}],expiresAt}`. After writing bytes to a single PUT target, call confirm; the server verifies size and SHA-256, and returns 400 if storage evidence does not match. Confirm is idempotent once `uploadState:"stored"`. **Current HTTP handler forwards only `assetId` to `confirmUpload`, so it cannot pass the domain's multipart completion payload. Do not offer >8 MB multipart upload as a working native flow until the API route is wired for it.** Photo MIME allowlist: JPEG/PNG/WebP/HEIC, max 50 MB in new media; legacy raw-photo upload has the same MIME list and 15 MB max. Video allows MP4/QuickTime and 200 MB; document PDF and scan PDF/JPEG/PNG allow 50 MB. `clientAssetId` is device-minted for offline idempotency. New media is archive-only and has structured Before/After sets. A `GET /v1/media/{id}/download` URL is short lived and must not be stored as permanent asset identity.
