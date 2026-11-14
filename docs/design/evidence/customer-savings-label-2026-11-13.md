# Customer savings label — 13 November 2026

The estimate and invoice customer views calculate a price-book markdown from
the captured original unit price and the charged unit price. The record does
not prove that a particular markdown came from a membership, and a customer's
current membership alone cannot establish that provenance. Label the existing
amount as “Savings” for all customers; keep the calculation and amount intact.

The new label regression failed on the release base because a member saw
“Member savings”. After the change, 20 customer-presentation and What's New
tests passed (`/private/tmp/thorbis-savings-label-green-fixed-1113.log`). The
first combined run also found an existing removed-option fixture whose total
did not match its empty lines; the fixture now supplies matching work and the
selection behavior test passes. No amounts or approval behavior were changed.

This does not establish verified membership discount provenance or fix the
separate held customer-invoice visibility issue. The generic savings amount is
still a comparison with the captured price-book amount, not a newly calculated
credit. Physical-device and VoiceOver behavior were not tested. Independent
review of this exact change remains pending.
