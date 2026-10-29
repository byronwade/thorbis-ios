# API gaps

The iOS app only shows records the Thorbis API returns. Missing routes are listed here instead of filled with invented data.

## Activity

- There is no call thread and no message thread. A call or message row opens the job, or the contact, only when that row already names one. A row that names neither stays closed.
- Customer history payments do not include an invoice id, so those rows cannot open a payment or an invoice. A payment on an invoice's own activity does, because that screen already has both ids.
- Customer history does not include photos, notes, calls, or messages. Job activity is notes and status changes. A photo opens only when a row already names the job and the file.
