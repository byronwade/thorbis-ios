# Job document shortcuts — additional qualification

The release change merged as PR #475 and was included in the uploaded build 249. The additional scenarios on this branch have **not been built or run**. Their purpose is to check a 16-estimate job and both fully and partially denied document-view capabilities. The denied-state assertion waits for the restricted screen before checking that document rows and shortcuts are absent; the partial-denial checks also require the permitted document type to remain accessible.

On this continuation, `swiftc -frontend -parse` on the changed preview and UI-test files and `git diff --check` completed successfully. This is syntax/whitespace evidence only, not a compile or simulator result. No iPad, VoiceOver, hundreds-of-records performance, or real server authorization is established by these fixtures.

Simulator execution was deferred: another iPad test was active and the machine's available disk fell below 1 GiB before recovering to approximately 4 GiB. Its process exited after termination for disk pressure. The job-document scenarios were not started. Existing local `project.yml` Stripe override is excluded from these commits.
