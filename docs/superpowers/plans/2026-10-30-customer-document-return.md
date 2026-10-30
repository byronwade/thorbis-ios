# Return to job documents after reviewing an estimate

**Goal:** Let a customer return from an estimate decision to the job's document book, including after approval, without leaving customer mode or needing to hand back the phone.

**Architecture:** Add an optional return-to-documents callback to the existing customer estimate presentation, available only when opened from the job document book. The existing hand-back remains a separate action. Returning first marks job estimates stale and invalidates earlier reads, closes only the nested estimate destination, and refreshes estimates in the background under existing session/workspace/capability checks. Old records stay visibly stale and non-actionable; the customer can still browse other documents or hand back the phone even if the read never completes. No approval, signature, revision, amount or permission code changes.

**Checks:** A focused UI journey enters customer mode, opens a job estimate, returns to the same document book and opens the next job estimate. Cover the completed approval path when the fixture permits, the retained hand-back, and existing handoff behavior. Run release-note tests and relevant job document UI tests after the simulator is available. Verify identity/session cancellation and loading failure behavior by code review. Never claim batch consent or billing support.
