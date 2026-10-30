# Inbox visual cues

Inbox notices now show a bell marker and explicit unread text. Read/unread comes from the existing notice, and every row still opens its own job; filters, mark-read, pagination, permission, errors and empty states are unchanged. The fixture contains synthetic read and unread notices only in the DEBUG preview transport. It does not represent live data.

The generic simulator build passed. On iPhone SE, the focused `InboxVisualUITests` check passed at `91b2fa2`: the unread label was exposed and tapping the notice opened its job. Dark and light preview screenshots were inspected. The prior pre-change run failed before its test started when CoreSimulator stopped, so it did not establish a red assertion. Live data, mark-read interactions, largest Dynamic Type, VoiceOver, iPad and RTL were not verified. No TestFlight upload is included in this work.
