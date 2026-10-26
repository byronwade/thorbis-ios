# Privacy inventory

Source of truth: `Thorbis/Resources/PrivacyInfo.xcprivacy`. Reconcile with App Store Connect answers.

| Data | Why | Linked to user | Tracking |
| --- | --- | --- | --- |
| Name, email | Sign-in and account | Yes | No |
| Phone, physical address | Customer records the user enters or views | Yes | No |
| User id | Session and job assignment | Yes | No |
| Photos | Job photos the user chooses to attach | Yes | No |
| Other user content | Job notes, estimates, invoices | Yes | No |

- No analytics, advertising or third-party SDKs. No tracking domains.
- Session cookie is stored in the Keychain (this device only, after first unlock). Appearance and
  chosen server are stored in UserDefaults (required-reason API CA92.1).
- Camera access is requested only when taking a job photo. The photo picker needs no library permission.
- Directions open Apple Maps with the address; no location permission is requested.
