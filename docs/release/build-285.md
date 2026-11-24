# Build 285

Uploaded to TestFlight from `paper-v2-tokens` at 4128d140 on 2026-11-20 (PR #563).

Owner: standing goal to keep researching and improving. This build is the phone side of two server drafts; both stay on today's behaviour until the server ships.

- Large files: videos and PDFs over 8 MB are hashed and sent in 8 MiB parts from disk, resume from the parts already stored (also after an app restart), and show "Sending 2 of 5… 40%". The first big file probes whether the server takes them; a "no" is remembered for 24 hours and the 8 MB wording stays. Long clips keep an 8 MB copy so today's server still gets them. Photos still pass through the existing resize, so they do not exceed 8 MB.
- Checklists on the job (server feature `job_checklists`): templates from the company, answers saved to the job as you go with other people's answers shown by name, required steps named, runs listed on the job. Owners create, edit, put away and bring back checklists, and can add the four starter ones. Offline answers stay on the phone and send on reconnect. Flag off: unchanged.
- Location purpose string now mentions offering to mark arrival.

Checks: 1,532 unit tests pass (1 skipped), stock-control lint passes, 109 UI tests pass (job overview, media queue, documents, invoice revisions, on-site helpers, tab bar, commit direction, customer photos). Full UI suite not re-run. Not checked on a real phone, against real storage, or against a live server.

Server drafts this round (byronwade/Thorbis-TanStack, none merged or deployed): #1618 durable sign-in limits and per-account cool-off (migration 0156; extends one governance check, owner sign-off needed).

Still open
- Sign-in "too many tries" wording says "a minute"; the server cool-off can be 15 minutes.
- No end-to-end run of the app against the server with these drafts applied.
