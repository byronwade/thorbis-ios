# Field API gaps

The iOS app does not invent records when the API has no route for them. A missing route is listed here, and a rejected request is shown as the server's error.

## Draft estimate lines

There is no separate route that replaces the lines of a draft estimate. `POST /v1/estimates` creates a draft. `POST /v1/estimates/{id}/revise` is the route the app uses to save line changes on a draft, a sent estimate, or a declined estimate. A never-issued draft sends `expectedRevisionNumber` 0. A draft that already has `currentRevisionNumber` sends that number. The revise response is the updated draft. If the server rejects a draft, the editor shows that error and does not treat the save as successful.

Approved estimates stay on the change-order path. Issued, paid, and void invoices do not accept line edits. Draft invoice lines still save through `POST /v2/invoices/{id}/lines`.
