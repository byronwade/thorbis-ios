# Setup check recovery

- Reproduce failed server reads using the session's real capability scope and API fixture.
- Distinguish server-confirmed completion, server-confirmed incomplete, and unavailable checks; team completion needs either positive result, while incomplete needs both negative results.
- Show unavailable checks and a retry without changing permitted setup routes or treating unknown as progress.
- Verify offline, partial, recovery, and authorization-scoped behavior; review independently before release.
