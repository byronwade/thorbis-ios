# Customer invoice balance wording

**Goal:** Make the invoice's headline accurately distinguish a draft total, an unpaid amount, a zero balance and a paid invoice, without changing money, payment or signature behavior.

**Approach:** Use the existing server invoice status and verified minor-unit amounts. A draft displays its total as a draft; a fresh paid invoice with positive recorded aggregate payments and zero balance may say paid in full; other zero balances say no balance due. A stale job invoice is labeled as last known. Void keeps its existing presentation. Keep the detailed amount rows and payment/refund disclosure unchanged.

**Verification:** Use a DEBUG-only fixture for draft and zero-dollar issued documents, and the existing partial-payment and fully-paid deposit fixture. Verify that no claim of payment is made for a zero-dollar or draft invoice, that each headline and its amount are visible, and the discount/payment/refund and paging checks still pass. No payment mutation or derived settlement amount is added. Document accessibility and live-data limitations.
