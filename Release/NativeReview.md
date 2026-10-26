# Native design review

Against design.thorbis.com Native contract (HIG-001–022). "Pass in code" means the source follows the rule
and a device check is still owed; "Not tested" means it needs a simulator or device.

| Rule | Title | Status | Evidence |
| --- | --- | --- | --- |
| HIG-001 | Scope and source receipts | Pass | README and AGENTS cite design.thorbis.com and this matrix. |
| HIG-002 | Platform authority before desktop resemblance | Pass | TabView, NavigationStack, Lists, sheets; no web layout ported. |
| HIG-003 | Native components and system materials | Pass | System List, Form, Picker, Menu, confirmationDialog, PhotosPicker. |
| HIG-004 | Touch geometry | Pass in code | `Theme.minimumHit` 44pt on custom controls. Needs device check. |
| HIG-005 | Navigation is destinations | Pass | Five tabs, so the iPhone tab bar never folds into More; the inbox and account are toolbar destinations on every root screen. Actions live in toolbars and buttons. |
| HIG-006 | Sheets, dismissal, continuity | Pass in code | Dirty forms disable interactive dismiss; drafts kept until saved. |
| HIG-007 | Safe areas and keyboards | Not tested | Relies on system layout; verify on device with keyboard up. |
| HIG-008 | System text styles and Dynamic Type | Pass in code | Only system text styles; verify at AX5. |
| HIG-009 | Assistive interaction | Pass in code | Combined labels on rows and status; VoiceOver pass pending. |
| HIG-010 | Appearance, contrast, noncolor meaning | Pass in code | Light/Dark/high-contrast colour sets; status word + symbol. |
| HIG-011 | System motion and Reduce Motion | Pass | No custom animation beyond system transitions. |
| HIG-012 | Haptics complement feedback | Pass | sensoryFeedback on job progress and money actions, with visible state change. |
| HIG-013 | Native input, editing, recovery | Pass in code | Content types, keyboards, inline errors, retry. |
| HIG-014 | Permissions and private information | Pass | Camera asked in context; notices omit customer detail. |
| HIG-015 | Honest states and offline work | Pass in code | Loading, empty, error with retry; no optimistic server state. |
| HIG-016 | iPad is adaptive | Not tested | `.sidebarAdaptable` tabs; iPad walk-through pending. |
| HIG-017 | Symbols, language, direction | Pass in code | SF Symbols, plain verbs; RTL not tested. |
| HIG-018 | Measured device performance | Not tested | Needs Instruments run on device. |
| HIG-019 | Media and capture fit the task | Pass | JPEG long edge 2048, 15 MB cap, pending thumbnail while each photo uploads. |
| HIG-020 | Shared contracts, platform adapters | Pass | ThorbisCore mirrors the API contract; one OutboundLink adapter. |
| HIG-021 | Evidence before completion | Partial | Core tests pass; simulator/device evidence pending (Checklist). |
| HIG-022 | Review, maintenance, exceptions | Pass | No exceptions taken. |
