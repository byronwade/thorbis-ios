# Customer at a glance implementation plan

**Goal:** Help a technician find the next visit, contacts, locations and full job history without repeating the same list across tabs.

**Design:** Adapt Paper Thorbis Mobile customer-detail artboard VQA-0 using the existing typography, tabs, call actions and grouped rows. Keep the next visit on Overview only and use the existing visible Jobs tab as the direct route to the full history. Remove the repeated full job history from Overview. Put the existing customer-account fields in a labelled disclosure while preserving contact, location, membership and equipment sections and all actions. Keep loading/error handling, permissions and customer/job authority unchanged.

**Validation:** Red/green UI journey: from Overview open account details, enter Jobs and verify next-visit summary is not repeated on other tabs; return and reach existing contact/location actions. Exercise large Dynamic Type and existing long-location tests. Confirm Records remains reachable. Do not infer full VoiceOver/device coverage or all page redesigns from this slice.
