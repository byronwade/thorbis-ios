# Build 148

Uploaded to App Store Connect on 2 November 2026 from the source tree of
`release/104-integration` merge `21ecd7afd3365f67008e37395989ef56184c6192`
([PR #258](https://github.com/byronwade/thorbis-ios/pull/258)). Xcode reported
that the upload succeeded and the package was processing. Processing completion
and tester-group availability have not been verified.

- Price-book pickers show the first loaded items while the remaining catalog
  downloads, and label searches that cover only loaded items. A complete cached
  catalog remains available while it refreshes. The full catalog still downloads
  in the background; this is not server-side demand paging.
- The saved catalog is bound to verified actor, organization, policy, server
  scope and API origin. Legacy unscoped cache needs an online refresh before it
  can be used offline. Explicit denial blocks selection and invalidates the saved
  copy. If both the denial marker and cache deletion fail, the current process
  blocks access but cannot persist that denial across a restart.
- Routine same-scope revalidation preserves the invoice picker, its search,
  selection and page, and reuses an idle complete catalog. Changed authority and
  incomplete or in-flight requests retain stricter refresh behavior.
- Includes the previously merged Tap to Pay terms-acceptance guard; Tap to Pay
  remains disabled in the signed archive.

The combined signed simulator run passed 54 focused unit tests and two picker UI
journeys, including page position after revalidation. Release upload-script tests
passed. Independent source review covered catalog scope and revalidation. The
archive's Tap to Pay audit passed with the feature disabled.

Xcode warned that the Stripe Terminal framework's dSYM was not included, so
crash reports in that framework may lack symbols. Customer-selectable catalog
add-ons, server support for paragraph-length line descriptions, durable draft
recovery, atomic estimate compare-and-link and qualified on-site payment methods
remain separate work. Simulator results do not establish live payment behavior,
physical-device accessibility or TestFlight availability.
