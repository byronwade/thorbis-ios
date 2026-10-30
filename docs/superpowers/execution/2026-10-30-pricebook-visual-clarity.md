# Price book visual follow-up: experimental

Base: `9193fa5`. This branch is not qualified for release.

The candidate adds decorative item-kind symbols and reflows the price below the name at accessibility text sizes. It retains the existing row actions, detail authority, context menus, category filters and full stale descriptions. No product photos were invented. The design is an adaptation of existing Thorbis tokens and native SF Symbols; an exact price-book Paper artboard has not been verified.

Evidence on the dedicated narrow iPhone simulator:

- Simulator build succeeded; `/private/tmp/pricebook-visual-followup-final-build.log`.
- Four focused UI cases passed; `/private/tmp/pricebook-visual-followup-final.log` and `/private/tmp/pricebook-visual-followup-final.xcresult`. These cover a large-text detail route, extreme amount, dark mixed catalog, and stale long description. They do not prove every pixel is readable.
- A prior largest-text title was visibly truncated despite an initial passing geometry test; `/private/tmp/pricebook-visual-followup-screens/F8C6A219-2CB1-4E52-A368-F38DD8806E2D.png`. The strengthened test failed before correction in `/private/tmp/pricebook-visual-followup-wrap-red.log`, and passed after removing the accessibility-size line limit. The corrected screenshot is `/private/tmp/pricebook-visual-followup-final-screens/8D9D48F5-247C-4C8F-947F-7ABC86F4C139.png`.
- **Open defect:** the extreme-price screenshot `/private/tmp/pricebook-visual-followup-final-screens/1F88DC72-91E6-4639-8733-C000C1F3EB90.png` shows the full amount but truncates the item title to “Commercial plumbing syste…”. The accessibility existence assertions do not catch this. Reflow this row and verify the full visible title and amount before integration.
- The end of a long stale description and full amount are shown in `/private/tmp/pricebook-visual-followup-final-screens/F2973ECA-A719-496E-A3F2-CC2FE55AE54F.png`; this single screenshot is not proof that every paragraph is rendered throughout scrolling.

VoiceOver, RTL, iPad, full standalone price-book regression, and final integrated-source tests have not been run. The older catalog-picker keyboard candidate is separate and remains unqualified.
