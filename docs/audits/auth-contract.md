# Native auth and authority contract — 2026-10-26

Use verified stable origin `https://app.thorbis.com` and append paths below. This describes the existing canonical web contract; fixture values are invented test data, never live credentials. Root verified signed-out GET session is JSON null. Authenticated fixtures are minimum decodable shapes, not a captured production response.

## HTTP calls

| Method/path | Request | Native handling |
|---|---|---|
| POST `/api/auth/sign-in/email` | `{ "email": "fixture@example.invalid", "password": "test-password" }` | Cookie-setting Better Auth endpoint. Check JSON/auth error before advancing. Then hydrate session and list memberships; sign-in success alone is not workspace readiness. |
| GET `/api/auth/get-session` | Session cookies | JSON `null` when signed out; otherwise user/session object below. |
| GET `/api/auth/organization/list` | Session cookies | JSON array of organizations; minimum fields id/name. SDK `organization.list()` unwraps this into `.data`. Reject non-array/HTML replies. |
| POST `/api/auth/organization/set-active` | `{ "organizationId": "019f0000-0000-7000-8000-000000000001" }` | Better Auth organization plugin; validate HTTP/auth result and re-fetch get-session. Response body need not become authority. |
| POST `/api/auth/sign-out` | JSON `{}` plus current cookies | Server session revocation; clear scoped local session/business state. Don't replace with global HTTPCookieStorage deletion. |
| GET `/v1/query/catalog` | Active session membership | Server-shaped capabilities, authority binding, authorized resources/views; never derive grants from a role name. |
| GET `/v1/features` | Active session membership | Organization-keyed release/entitlement decisions; independent of permissions. |

The list/set-active paths follow the installed Better Auth organization-client API used by the source; source explicitly pins `/organization/set-active` in `packages/auth/src/auth.ts`. List route was not independently authenticated/probed. Verify its response with an authorized test account before release. Auth endpoints are delegated by canonical `/api/auth/*`; not fully enumerated in OpenAPI.

The newer browser uses `/app/api/auth/...`, while native may consistently use the verified root compatibility paths. Do not mix cookie origins or arbitrarily rewrite hostnames. Use URLSession cookie handling; don't persist passwords or expose tokens in logs. Better Auth errors are not always RFC9457: decode optional `code` and `message` as well as business `title/detail/status`.

## Minimum session fixture

```json
{
  "user": {
    "id": "019f0000-0000-7000-8000-000000000011",
    "name": "Fixture technician",
    "email": "fixture@example.invalid",
    "emailVerified": true
  },
  "session": {
    "id": "fixture-session",
    "userId": "019f0000-0000-7000-8000-000000000011",
    "activeOrganizationId": "019f0000-0000-7000-8000-000000000001",
    "expiresAt": "2026-10-27T12:00:00.000Z"
  }
}
```

`activeOrganizationId` must be nullable/optional before membership activation. Unknown JSON fields remain forward-compatible. Session actor identity comes from `user.id`; verify consistency with `session.userId` where present. Expiry supports ISO8601 with/without fractional seconds.

Organization-list fixture:
```json
[{ "id": "019f0000-0000-7000-8000-000000000001", "name": "Fixture workspace" }]
```

Zero memberships => neutral no-workspace state. One => explicitly activate it. Multiple => explicit workspace picker. Never guess first tenant. Existing active organization still requires validated session and fresh authority before showing business data.

## Capability/feature fixtures

Minimal empty-resource catalog fixture, with sample capability strings:
```json
{
  "authority": {
    "actorId": "019f0000-0000-7000-8000-000000000011",
    "organizationId": "019f0000-0000-7000-8000-000000000001",
    "policyVersion": 1,
    "generation": "fixture-generation"
  },
  "capabilities": ["job.view", "customer.view"],
  "resources": [],
  "views": []
}
```

`authority.generation` is opaque server data. `policyVersion` is positive integer. Optional `authorityExpiresAt` is an exclusive hard deadline. Match actor/org and, when bound, policy/generation/deadline against active sync binding before publishing capabilities. `capabilities` is an explicit unique string list. A missing/invalid catalog is **unavailable authority**, not an empty policy or permission to show everything. Reject stale actor/workspace responses. The catalog does not expose per-capability scopes; do not fabricate effective scope decisions from it. The mobile registry's scope-sensitive admin projections require the relevant canonical effective-access projection before offering them.

```json
{
  "organizationId": "019f0000-0000-7000-8000-000000000001",
  "evaluatedAt": "2026-10-26T12:00:00.000Z",
  "features": {
    "jobs": { "enabled": true, "released": true, "entitled": true, "stage": "general" },
    "price_book": { "enabled": false, "released": false, "entitled": true, "stage": "internal", "reason": "not_released" }
  }
}
```

Feature decision fields: enabled/released/entitled Bool, optional stage/reason String. `features` is a string-keyed dictionary; unknown/missing required feature fails closed. Reason vocabulary: unknown_feature, not_released, held, retired, not_entitled. UI uses enabled; server remains authority. Never turn failed network feature lookup into all-features-enabled.

## Required state sequence

1. Startup: restoring -> get-session -> signed out OR session identity.
2. Sign-in: synchronously retire old business state before async auth; retain cookie only after success; hydrate session; list/choose/activate membership.
3. Ready: verified actor+organization -> query catalog/features -> atomically publish identity-bound workspace state. Do not use `/v1/me` (Network account projection) as this workspace proof.
4. Switch/sign-out/401: synchronously block admissions and hide old data, cancel requests, increment local identity generation, clear prior caches/drafts/authority; retire replica; then mutate auth. Queued commands remain bound to original actor/org and must never drain under new identity. Late replies from earlier generation are discarded.
5. On policy invalidation/deadline: withhold capabilities and replicated access until refreshed current authority. Backend authorization still applies to every action regardless of UI.

## Evidence

`apps/web/src/auth-client.ts`; `features/sign-in.tsx:141`; `organization-session.ts`; `command-availability.ts:97`; `query-catalog.ts:84,493`; `services/api/src/app.ts:1882,1910`; `packages/auth/src/auth.ts:180`; `packages/features/src/{snapshot,evaluate}.ts`; `apps/web/test/my-day.e2e.ts:17` (session fixture). No product code changed.
