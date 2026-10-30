# Build 97 — clearer price-book items

Runtime source: `535782b2c7344a36b8a81cdcd4c4a4b29d175d35`.

Price-book rows use material/service symbols, give item names their own space, and place prices beneath at accessibility text sizes. Existing descriptions, detail navigation, grouping, actions, and permission handling remain in place.

Seven selected UI tests passed on a clean integrated candidate on the iPhone SE simulator, including a long name and large price, largest text, stale multi-paragraph description, dark grouped list, detail navigation, and permission revocation. Consecutive screenshots in a separate run showed the sample long description from beginning to end. Independent source review found no definite data, navigation, or authority regression. The signed archive passed source fingerprint, signing, build, purpose-string, preview-exclusion and payment-gate checks.

Limits: this is a price-book increment, not an app-wide visual redesign. Exceptionally long currency strings, VoiceOver, RTL, iPad, and broader journeys remain unverified. The separate estimate review accessibility candidate is not included. Tap to Pay remains disabled pending qualification. The exported distribution artifact was not independently audited.
