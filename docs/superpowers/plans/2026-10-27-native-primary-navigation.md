# Native primary navigation plan

## Goal

Align the iPhone shell with the Thorbis native design contract: stable Jobs, Arrive, and Inbox destinations, with other workspace tools available from a More action. Keep the existing iPad Paper schedule split and preserve every screen's capability and feature gates.

## Acceptance criteria

- iPhone exposes Jobs, Arrive, and Inbox as stable, visibly labeled top-level destinations, including when a role cannot access a destination; unavailable content explains the required access.
- Jobs opens the full jobs workflow. Arrive reuses the existing My Day and on-the-way workflow.
- Inbox contains only the server-backed staff-notice feed, clearly labeled as staff notices; device-local message drafts remain under More and are not shown as conversations.
- Schedule remains reachable on iPhone, and iPad keeps the current PIM-0 schedule/sidebar/detail layout.
- More, workspace selection, settings, create-job, and search remain available with their existing capability checks.
- Switching tabs preserves each destination's navigation state.
- Tests cover stable destination mapping, permission-aware content, and Arrive's My Day mapping.

## Implementation sequence

1. Inspect the current shell and route contracts with CodeGraph before editing. **In progress.**
2. Add focused navigation policy tests and confirm they fail for the current shell.
3. Implement the three native destinations, per-destination navigation state, More action, and existing iPad path.
4. Keep the Inbox tab truthful by using the gated staff-notice feed and retaining local drafts under More.
5. Run focused tests, the full iPhone simulator suite, and an iPad build; inspect the shell at phone and tablet widths.
6. Review the diff and update design evidence and beta coverage.

## Out of scope

This shell change does not add a general messaging backend, SMS/email delivery, team chat, or new job/schedule APIs.
