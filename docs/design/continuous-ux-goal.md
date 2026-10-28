# Continuous UI and UX goal

Updated by the user on 28 October 2026.

Continuously improve the entire Thorbis iOS application so it feels as simple,
intuitive, and easy to use as Apple products, with beautiful presentation based
on [design.thorbis.com](https://design.thorbis.com). Preserve every existing
feature and capability.

## How to apply the goal

- Keep the information and primary action needed for the current task visible.
- Put secondary and advanced actions in clearly labelled, contextual menus or
  disclosures. Keep every existing action reachable and discoverable.
- Reduce the taps and decisions required for common work. Avoid adding a menu
  step to a frequent action simply to make a screen look emptier.
- Use the shared Thorbis tokens, type hierarchy, spacing, and components, along
  with native iOS navigation and interaction conventions.
- Use clear language and useful loading, empty, error, confirmation, and success
  states. Show the next useful action when a task cannot continue.
- Preserve permissions, feature gates, validation, drafts, offline recovery,
  and server authority while changing presentation.
- Keep Dynamic Type, VoiceOver, contrast, focus, and comfortable touch targets
  part of each improvement, including layouts on iPhone and iPad.

## Continuous review loop

Review complete user flows, choose a concrete source of friction, and make a
small, reviewable improvement. Record the before and after interaction, verify
that all existing features remain accessible, and check the affected visual
states and behavior before moving to the next flow. Prioritize frequent tasks,
unclear next steps, repeated information, crowded controls, and avoidable taps.

The Paper Thorbis Mobile artboards remain the layout reference. The current
design.thorbis.com rules and the user's simplification goal guide decisions
where an artboard is incomplete or a native interaction requires adaptation.

This is ongoing product work. A successful build or one polished screen does
not establish whole-application completion.

## Payment and delivery priorities

Continue researching and simplifying the invoice/payment flow, and add payment
methods supported by the canonical backend and connected provider. Distinguish
collecting funds from recording a payment taken elsewhere. Preserve accurate
pending, failed and confirmed states and all existing financial authority.

Upload a new TestFlight build after each verified, useful batch of user-visible
changes. Confirm processing and distribution to the intended testers, and keep
release notes current. Do not wait for whole-app perfection to deliver a scoped
beta for device testing. Keep unverified native behavior explicit.
