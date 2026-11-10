# Open the new invoice from the job

The job's empty invoice state creates a verified completion draft but leaves the technician on the job. Reuse the existing next-step action, which opens the exact invoice returned by the scoped, idempotent creation request. Keep the existing create permissions, loading/error handling, scope checks, and draft state. Test the mounted empty-state path using local preview responses, including a valid draft, a failure or foreign invoice, and a repeated tap while the first request is pending; no payment or live write is involved.
