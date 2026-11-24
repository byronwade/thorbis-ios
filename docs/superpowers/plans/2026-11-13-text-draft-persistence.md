# Text draft persistence implementation plan

**Goal:** Never report a text draft saved unless its disk write succeeded, and preserve visible text when storage fails.

**Architecture:** Follow the existing mail draft atomic-write and uncertainty handling for text mutations. Keep the current composer text in memory, visibly report a storage failure, and provide a way to copy it. Do not overwrite an uncertain disk copy.

**Checks:** First run the two failed-write regressions against the existing code. Then implement the transaction and failure feedback; run those regressions and the existing inbox persistence tests. Verify the visible failure treatment where the simulator permits it. No message is transmitted by this flow.
