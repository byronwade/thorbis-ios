import UniformTypeIdentifiers
import XCTest
@testable import Thorbis

/// Working a job with nothing locked by its stage: what the bar and "Add to job" offer per status
/// and role, the create body's job rule, and the media pick's limits, order and retry.
final class JobFlowUnlockedTests: XCTestCase {
    private func line(_ cents: Int) -> FieldLine {
        FieldLine(id: UUID().uuidString, description: "Line", quantity: 1, unitPrice: FieldMoney(amount: cents, currency: "USD"), source: nil)
    }

    private func estimate(_ id: String, _ status: String) -> EstimateRecord {
        EstimateRecord(id: id, organizationId: "o", customerId: "c", createdByUserId: "u", locationId: nil, status: status,
                       currentRevisionNumber: 1, title: "AC repair", lines: [line(48_000)], options: nil,
                       createdAt: "2026-10-28T00:00:00Z", updatedAt: "2026-10-28T00:00:00Z",
                       sentAt: nil, approvedAt: nil, declinedAt: nil)
    }

    private func invoice(_ id: String, _ status: String, total: Int = 48_000, paid: Int = 0) -> InvoiceRecord {
        InvoiceRecord(id: id, organizationId: "o", customerId: "c", jobId: "j", createdByUserId: "u", locationId: nil, scheduleId: nil,
                      origin: "job_completion", sourceOperationKey: "k", sourceEstimateId: nil, sourceEstimateRevisionNumber: nil,
                      manualPhysicalServiceEvidence: nil, status: status, lines: [line(total)], linesRevision: 1, amountPaid: paid,
                      currency: "USD", issuedAt: nil, paidAt: nil, voidedAt: nil,
                      createdAt: "2026-10-28T00:00:00Z", updatedAt: "2026-10-28T00:00:00Z")
    }

    private let openStatuses = ["scheduled", "dispatched", "en_route", "arrived", "in_progress", "paused", "completed"]

    // MARK: The bar's side steps

    func testEstimateAndCollectRideBesideTheStatusStepAtEveryStage() {
        for status in openStatuses {
            let primary: TechJobStep? = status == "dispatched" ? .transition("en_route") : nil
            let steps = TechJobFlow.sideSteps(status: status, primary: primary, estimates: [],
                                              invoices: [invoice("i1", "issued", paid: 10_000)], can: .all)
            let onSite = !["scheduled", "dispatched", "en_route"].contains(status)
            let collect = TechJobStep.collect(invoiceID: "i1", due: 38_000, currency: "USD")
            XCTAssertEqual(steps, onSite ? [collect, .buildEstimate] : [collect], status)
        }
    }

    func testCanceledJobOffersNoSideSteps() {
        XCTAssertEqual(TechJobFlow.sideSteps(status: "canceled", primary: nil, estimates: [estimate("e1", "sent")],
                                             invoices: [invoice("i1", "issued")], can: .all), [])
    }

    func testSideStepsNeverRepeatTheBarsOwnStep() {
        let owed = TechJobStep.collect(invoiceID: "i1", due: 48_000, currency: "USD")
        XCTAssertEqual(TechJobFlow.sideSteps(status: "completed", primary: owed, estimates: [], invoices: [invoice("i1", "issued")], can: .all),
                       [.buildEstimate])
        XCTAssertEqual(TechJobFlow.sideSteps(status: "in_progress", primary: .buildEstimate, estimates: [], invoices: [], can: .all), [])
        XCTAssertEqual(TechJobFlow.sideSteps(status: "in_progress", primary: .presentEstimates, estimates: [estimate("e1", "sent")],
                                             invoices: [], can: .all), [])
    }

    func testEstimateSideStepShowsBeforeItBuilds() {
        XCTAssertEqual(TechJobFlow.sideSteps(status: "arrived", primary: .transition("in_progress"), estimates: [estimate("e1", "sent"), estimate("e2", "draft")],
                                             invoices: [], can: .all), [.presentEstimates])
        XCTAssertEqual(TechJobFlow.sideSteps(status: "arrived", primary: .transition("in_progress"), estimates: [estimate("e2", "draft")],
                                             invoices: [], can: .all), [.showEstimate(id: "e2")])
        // Approved or declined paper is not shown again; another estimate can still be started.
        XCTAssertEqual(TechJobFlow.sideSteps(status: "arrived", primary: .transition("in_progress"), estimates: [estimate("e3", "approved")],
                                             invoices: [], can: .all), [.buildEstimate])
        XCTAssertEqual(TechJobFlow.sideSteps(status: "en_route", primary: .transition("arrived"), estimates: [estimate("e3", "approved")],
                                             invoices: [], can: .all), [], "No estimate pill on the road; + still starts one")
    }

    func testSideStepsFollowTheRole() {
        var can = TechJobAbilities.all
        can.collectPayment = false
        can.createEstimate = false
        XCTAssertEqual(TechJobFlow.sideSteps(status: "arrived", primary: nil, estimates: [], invoices: [invoice("i1", "issued")], can: can), [])
        var viewOnly = TechJobAbilities.all
        viewOnly.approveEstimate = false
        XCTAssertEqual(TechJobFlow.sideSteps(status: "arrived", primary: nil, estimates: [estimate("e1", "sent")], invoices: [], can: viewOnly),
                       [.buildEstimate], "An estimate this role can't approve in person isn't handed over")
        var noInvoices = TechJobAbilities.all
        noInvoices.viewInvoice = false
        XCTAssertEqual(TechJobFlow.sideSteps(status: "arrived", primary: nil, estimates: [], invoices: [invoice("i1", "issued")], can: noInvoices),
                       [.buildEstimate])
    }

    func testSideStepsWaitForThePaperToLoad() {
        XCTAssertEqual(TechJobFlow.sideSteps(status: "arrived", primary: nil, estimates: nil, invoices: nil, can: .all), [])
        XCTAssertEqual(TechJobFlow.sideSteps(status: "arrived", primary: nil, estimates: [], invoices: nil, can: .all), [.buildEstimate])
    }

    func testPaidOrDraftInvoicesAreNotCollected() {
        XCTAssertEqual(TechJobFlow.sideSteps(status: "completed", primary: nil, estimates: [],
                                             invoices: [invoice("i1", "issued", paid: 48_000), invoice("i2", "draft"), invoice("i3", "void")], can: .all),
                       [.buildEstimate])
    }

    func testSideStepWordsAreShort() {
        XCTAssertEqual(TechJobStep.buildEstimate.sideTitle, "New estimate")
        XCTAssertEqual(TechJobStep.presentEstimates.sideTitle, "Show estimate")
        XCTAssertEqual(TechJobStep.showEstimate(id: "e").sideTitle, "Show estimate")
        XCTAssertEqual(TechJobStep.collect(invoiceID: "i", due: 34_000, currency: "USD").sideTitle, "Collect $340.00")
    }

    func testTheStatusStepStaysTheBarsOneStep() {
        // Adding side steps changed nothing about the order of the visit.
        XCTAssertEqual(TechJobFlow.nextStep(status: "dispatched", transitions: ["en_route"], estimates: [], invoices: [invoice("i1", "issued")], can: .all),
                       .transition("en_route"))
        XCTAssertEqual(TechJobFlow.nextStep(status: "arrived", transitions: ["in_progress"], estimates: [estimate("e1", "sent")], invoices: [], can: .all),
                       .transition("in_progress"))
    }

    // MARK: Paid stage and wrap up

    func testPaidStageNeedsEverythingBilledAndPaid() {
        let paid = invoice("a", "issued", paid: 48_000)
        XCTAssertTrue(TechJobFlow.paidStage(status: "in_progress", completedAt: nil, invoices: [paid]))
        XCTAssertFalse(TechJobFlow.paidStage(status: "in_progress", completedAt: nil, invoices: [paid, invoice("b", "draft")]),
                       "New unbilled work keeps the job on Working")
        XCTAssertFalse(TechJobFlow.paidStage(status: "in_progress", completedAt: nil, invoices: [paid, invoice("b", "issued")]),
                       "New unpaid work keeps the job on Working")
        XCTAssertFalse(TechJobFlow.paidStage(status: "in_progress", completedAt: "2026-11-20T15:40:00Z", invoices: [paid]),
                       "A reopened job opens on Working, not on Paid")
        XCTAssertTrue(TechJobFlow.paidStage(status: "completed", completedAt: "2026-11-20T15:40:00Z", invoices: [paid]))
        XCTAssertFalse(TechJobFlow.paidStage(status: "in_progress", completedAt: nil, invoices: [invoice("a", "issued")]))
    }

    private func closeout(notes: Bool, photos: Int, noteCount: Int = 0) -> FieldCloseout {
        func rule(_ kind: String, asked: Bool, met: Bool) -> FieldCloseoutRequirement {
            FieldCloseoutRequirement(requirement: kind, kind: kind, outcome: !asked ? "not_required" : met ? "satisfied" : "blocked",
                                     detail: asked ? "company policy requires it" : "company policy does not require a job \(kind)",
                                     nextAction: asked && !met ? (kind == "notes" ? "add_job_note" : "add_job_photo") : nil, commercialSource: nil)
        }
        return FieldCloseout(
            policy: FieldCloseoutPolicy(organizationId: "o", requireNotes: notes, requiredPhotoCount: photos, requiredChecks: [], updatedByUserId: nil, updatedAt: nil),
            facts: FieldCloseoutFacts(noteCount: noteCount, photoCount: 0, acknowledgedCheckKeys: [],
                                      authorizationTarget: FieldCloseoutTarget(id: "j", organizationId: "o", customerId: "c", locationId: nil, estimateId: nil, estimateRevisionNumber: nil)),
            acknowledged: [],
            requirements: [rule("notes", asked: notes, met: noteCount > 0), rule("photos", asked: photos > 0, met: false)],
            unmet: [], completable: !notes && photos == 0)
    }

    func testWrapUpAsksOnlyForWhatThePolicyRequires() {
        // No note, no photo, no signature required: nothing sends the tech to the camera.
        let free = WrapUpList.rows(.init(beforePhotos: 0, afterPhotos: 0, estimates: [], invoices: [invoice("a", "issued", paid: 48_000)],
                                         closeout: closeout(notes: false, photos: 0)))
        XCTAssertEqual(free.map(\.step), [.payment], "Rows the policy does not ask for are not shown")
        XCTAssertNil(WrapUpList.next(free))
        XCTAssertEqual(WrapUpList.left(free), 0)
        XCTAssertTrue(CloseoutChecklist.items(closeout(notes: false, photos: 0)).isEmpty, "No 'does not require' rows")

        // A required note and photo are asked for; the photo rule is the server's own row.
        let strict = WrapUpList.rows(.init(beforePhotos: 0, afterPhotos: 0, estimates: [], invoices: nil, closeout: closeout(notes: true, photos: 2)))
        XCTAssertEqual(WrapUpList.next(strict)?.step, .diagnosisNote)
        XCTAssertEqual(WrapUpList.left(strict), 2)
        XCTAssertFalse(strict.first { $0.step == .beforePhotos }?.required ?? true, "Before photos are never what Wrap up opens")

        // A photo already taken still shows as done, and counts.
        let taken = WrapUpList.rows(.init(beforePhotos: 2, afterPhotos: 0, estimates: [], invoices: nil, closeout: closeout(notes: false, photos: 0)))
        XCTAssertEqual(taken.map(\.step), [.beforePhotos])
        XCTAssertEqual(WrapUpList.progress(taken).done, 1)
    }

    // MARK: Add to job

    private var everything: JobAddOffer.Inputs {
        JobAddOffer.Inputs(status: "scheduled", canCreateEstimate: true, canShowEstimates: true, canCreateInvoice: true, canOpenInvoice: false,
                           canCollect: true, canAddMedia: true, canAddNote: true, canAddContact: true)
    }

    func testAddOffersTheSameRowsAtEveryOpenStage() {
        for status in openStatuses {
            var inputs = everything
            inputs.status = status
            let rows = JobAddOffer.rows(inputs)
            XCTAssertEqual(rows.billing, [.estimate, .showEstimate, .invoice, .payment], status)
            XCTAssertEqual(rows.onTheJob, [.photo, .checklist, .note, .contact], status)
        }
    }

    func testCanceledJobKeepsOnlyNotesAndContacts() {
        var inputs = everything
        inputs.status = "canceled"
        let rows = JobAddOffer.rows(inputs)
        XCTAssertEqual(rows.billing, [])
        XCTAssertEqual(rows.onTheJob, [.note, .contact])
    }

    func testAddRowsFollowTheRoleAndWhatTheJobHas() {
        var inputs = JobAddOffer.Inputs(status: "en_route", canAddNote: true)
        XCTAssertEqual(JobAddOffer.rows(inputs).billing, [])
        XCTAssertEqual(JobAddOffer.rows(inputs).onTheJob, [.checklist, .note], "A checklist can be started at every open stage")
        // An invoice that exists is opened, never made twice.
        inputs.canOpenInvoice = true
        XCTAssertEqual(JobAddOffer.rows(inputs).billing, [.openInvoice])
        inputs.canCreateInvoice = true
        XCTAssertEqual(JobAddOffer.rows(inputs).billing, [.invoice])
        inputs.canCollect = true
        inputs.canAddMedia = true
        XCTAssertEqual(JobAddOffer.rows(inputs).billing, [.invoice, .payment])
        XCTAssertEqual(JobAddOffer.rows(inputs).onTheJob, [.photo, .checklist, .note])
    }

    // MARK: Running late and Can't start

    func testRunningLateIsOfferedUntilArrival() {
        for status in ["scheduled", "dispatched", "en_route"] {
            XCTAssertTrue(JobVisitGates.canSendRunningLate(status: status, hasSchedule: true), status)
            XCTAssertFalse(JobVisitGates.canSendRunningLate(status: status, hasSchedule: false), status)
        }
        for status in ["arrived", "in_progress", "paused", "completed", "canceled"] {
            XCTAssertFalse(JobVisitGates.canSendRunningLate(status: status, hasSchedule: true), status)
        }
    }

    func testCantStartIsOfferedAnyTimeBeforeTheWorkStarts() {
        for status in ["scheduled", "dispatched", "en_route", "arrived"] {
            XCTAssertTrue(JobVisitGates.canReportCantStart(status: status, canEditJob: true), status)
            XCTAssertFalse(JobVisitGates.canReportCantStart(status: status, canEditJob: false), status)
        }
        for status in ["in_progress", "paused", "completed", "canceled"] {
            XCTAssertFalse(JobVisitGates.canReportCantStart(status: status, canEditJob: true), status)
        }
    }

    func testLongDescriptionsFold() {
        XCTAssertFalse(JobDescriptionFold.isLong("AC not cooling. Customer says it started Tuesday."))
        XCTAssertTrue(JobDescriptionFold.isLong(String(repeating: "word ", count: 60)))
        XCTAssertTrue(JobDescriptionFold.isLong("one\ntwo\nthree\nfour\nfive"))
        XCTAssertFalse(JobDescriptionFold.isLong("one\ntwo\nthree\nfour"))
    }

    // MARK: The estimate create body

    private let jobID = "00000000-0000-4000-8000-000000000001"
    private let customerID = "00000000-0000-4000-8000-000000000003"
    private let locationID = "00000000-0000-4000-8000-000000000007"

    func testJobIsNamedOnlyForItsOwnCustomerWithoutOptions() {
        XCTAssertEqual(FieldEstimateCreate.linkedJobID(jobID: jobID, customerID: customerID, jobCustomerID: customerID, hasOptions: false), jobID)
        XCTAssertEqual(FieldEstimateCreate.linkedJobID(jobID: jobID, customerID: customerID.uppercased(), jobCustomerID: customerID, hasOptions: false), jobID)
        XCTAssertNil(FieldEstimateCreate.linkedJobID(jobID: jobID, customerID: customerID, jobCustomerID: customerID, hasOptions: true),
                     "options and jobId never travel together")
        XCTAssertNil(FieldEstimateCreate.linkedJobID(jobID: jobID, customerID: "00000000-0000-4000-8000-000000000099", jobCustomerID: customerID, hasOptions: false))
        XCTAssertNil(FieldEstimateCreate.linkedJobID(jobID: nil, customerID: customerID, jobCustomerID: customerID, hasOptions: false))
        XCTAssertNil(FieldEstimateCreate.linkedJobID(jobID: jobID, customerID: customerID, jobCustomerID: nil, hasOptions: false))
        XCTAssertNil(FieldEstimateCreate.linkedJobID(jobID: "", customerID: customerID, jobCustomerID: customerID, hasOptions: false))
    }

    private func body(_ request: FieldEstimateCreate) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(request)) as? [String: Any])
    }

    func testCreateBodyCarriesTheJobAndItsLocation() throws {
        let lines = [FieldEstimateLineInput(description: "Valve", quantity: 1, unitPrice: .init(amount: 1200, currency: "USD"))]
        let fromJob = try body(FieldEstimateCreate(customerId: customerID, title: "Repair", lines: lines, locationId: locationID, jobId: jobID))
        XCTAssertEqual(fromJob["jobId"] as? String, jobID)
        XCTAssertEqual(fromJob["locationId"] as? String, locationID)
        XCTAssertEqual(fromJob["customerId"] as? String, customerID)
        XCTAssertNil(fromJob["options"], "The editor never sends options, so jobId is always safe beside its body")
        let standalone = try body(FieldEstimateCreate(customerId: customerID, title: "Repair", lines: lines))
        XCTAssertNil(standalone["jobId"], "An estimate made away from a job names none")
        XCTAssertFalse(standalone.keys.contains("jobId"))
    }

    func testRefusedCreateSaysTheOfficeTurnsItOn() {
        let refused = Problem(title: "Forbidden", status: 403, detail: "estimate.create")
        XCTAssertEqual(EstimateCreationRecovery.refusalMessage(refused, creating: true), EstimateCreationRecovery.createRefused)
        XCTAssertTrue(EstimateCreationRecovery.createRefused.contains("office"))
        // A 403 on a later step (the link, a recheck) keeps its own words.
        XCTAssertEqual(EstimateCreationRecovery.refusalMessage(refused, creating: false), refused.localizedDescription)
        let invalid = Problem(title: "Invalid", status: 400, detail: "title")
        XCTAssertEqual(EstimateCreationRecovery.refusalMessage(invalid, creating: true), invalid.localizedDescription)
    }

    // MARK: Media limits, order and retry

    func testAllowedTypesAreTheServers() {
        XCTAssertEqual(MediaLimits.kind(mime: "image/jpeg"), "photo")
        XCTAssertEqual(MediaLimits.kind(mime: "IMAGE/HEIC"), "photo")
        XCTAssertEqual(MediaLimits.kind(mime: "video/mp4"), "video")
        XCTAssertEqual(MediaLimits.kind(mime: "video/quicktime"), "video")
        XCTAssertEqual(MediaLimits.kind(mime: "application/pdf"), "document")
        XCTAssertNil(MediaLimits.kind(mime: "application/zip"))
        XCTAssertNil(MediaLimits.kind(mime: "image/gif"))
        XCTAssertEqual(MediaLimits.serverMaxBytes["photo"], 50 * 1024 * 1024)
        XCTAssertEqual(MediaLimits.serverMaxBytes["video"], 200 * 1024 * 1024)
        XCTAssertEqual(MediaLimits.serverMaxBytes["document"], 50 * 1024 * 1024)
    }

    /// A server that said within the last day that it can only take 8 MB keeps the old limit.
    func testFilesAreHeldToOneUploadWhileTheServerCannotTakeBigOnes() {
        let limit = MediaLimits.singleUploadBytes
        XCTAssertEqual(limit, 8 * 1024 * 1024)
        for mime in ["image/jpeg", "video/mp4", "application/pdf"] {
            XCTAssertNil(MediaLimits.check(mime: mime, bytes: 1, large: false), mime)
            XCTAssertNil(MediaLimits.check(mime: mime, bytes: limit, large: false), mime)
            XCTAssertEqual(MediaLimits.check(mime: mime, bytes: limit + 1, large: false), .tooLarge(limitBytes: limit), mime)
            XCTAssertEqual(MediaLimits.check(mime: mime, bytes: 0, large: false), .empty, mime)
        }
        XCTAssertEqual(MediaLimits.check(mime: "text/plain", bytes: 10), .unsupported)
        XCTAssertEqual(MediaLimits.message(.tooLarge(limitBytes: limit), name: "plans.pdf"), "plans.pdf is too big. Files can be up to 8 MB.")
        XCTAssertEqual(MediaLimits.message(.unsupported, name: "notes.txt"), "notes.txt isn\u{2019}t a photo, a video or a PDF.")
    }

    func testOnePhotoKeepsTheTagStepAndEverythingElseQueues() {
        XCTAssertEqual(MediaImportPlan.route([.photo]), .tagOne)
        XCTAssertEqual(MediaImportPlan.route([.video]), .queueAll)
        XCTAssertEqual(MediaImportPlan.route([.photo, .photo]), .queueAll)
        XCTAssertEqual(MediaImportPlan.route([.photo, .video, .photo]), .queueAll)
        XCTAssertEqual(MediaImportPlan.picked([.heic]), .photo)
        XCTAssertEqual(MediaImportPlan.picked([.quickTimeMovie]), .video)
        XCTAssertEqual(MediaImportPlan.picked([.mpeg4Movie, .jpeg]), .video)
        XCTAssertEqual(MediaImportPlan.picked([.pdf]), .other)
    }

    private func pending(_ id: String, at seconds: TimeInterval) -> PendingMedia {
        PendingMedia(id: id, jobID: "j", filename: "\(id).jpg", tags: [], capturedAt: Date(timeIntervalSince1970: seconds), kind: "photo", mime: "image/jpeg")
    }

    func testAPickUploadsInTheOrderItWasChosen() {
        let base = Date(timeIntervalSince1970: 1_800_000_000)
        // IDs are random, so the order must come from the stamps alone.
        let picked = ["c", "a", "d", "b"].enumerated().map { position, id in
            PendingMedia(id: id, jobID: "j", filename: MediaImportPlan.filename(position == 2 ? .video : .photo, stamp: "20261120T101500", position: position),
                         tags: [], capturedAt: MediaImportPlan.capturedAt(base: base, position: position), kind: "photo", mime: "image/jpeg")
        }
        XCTAssertEqual(picked.shuffled().sorted(by: MediaQueue.sendsBefore).map(\.id), ["c", "a", "d", "b"])
        XCTAssertEqual(picked.map(\.filename), ["photo-20261120T101500-1.jpg", "photo-20261120T101500-2.jpg",
                                               "clip-20261120T101500-3.mp4", "photo-20261120T101500-4.jpg"])
        // Earlier captures still go first, and equal stamps never shuffle.
        let earlier = pending("z", at: 1_700_000_000)
        XCTAssertEqual(([earlier] + picked).shuffled().sorted(by: MediaQueue.sendsBefore).first?.id, "z")
        XCTAssertEqual([pending("b", at: 5), pending("a", at: 5)].sorted(by: MediaQueue.sendsBefore).map(\.id), ["a", "b"])
    }

    func testOneFailedItemDoesNotHoldUpTheRest() {
        XCTAssertEqual(MediaQueue.afterFailure(cancelled: false, connectivity: false), .next)
        XCTAssertEqual(MediaQueue.afterFailure(cancelled: false, connectivity: true), .stop, "No signal: everything waits and is retried")
        XCTAssertEqual(MediaQueue.afterFailure(cancelled: true, connectivity: false), .stop)
    }

    func testQueueLineSaysWhichItemIsSending() {
        XCTAssertEqual(MediaQueue.line(waiting: ["a", "b", "c"], sendingID: "b", failed: 0, offline: false), "Sending 2 of 3\u{2026}")
        XCTAssertEqual(MediaQueue.line(waiting: ["a"], sendingID: "a", failed: 0, offline: false), "Sending now\u{2026}")
        XCTAssertEqual(MediaQueue.line(waiting: ["a", "b"], sendingID: "other-job", failed: 1, offline: false), "Sending now\u{2026}")
        XCTAssertEqual(MediaQueue.line(waiting: ["a", "b"], sendingID: nil, failed: 2, offline: true), "2 couldn\u{2019}t send. Tap one to see why.")
        XCTAssertEqual(MediaQueue.line(waiting: ["a"], sendingID: nil, failed: 0, offline: true), "They send by themselves when you\u{2019}re back online.")
        XCTAssertEqual(MediaQueue.line(waiting: ["a"], sendingID: nil, failed: 0, offline: false), "Waiting to send.")
    }

    func testImportWordsCountWhatHappened() {
        XCTAssertEqual(MediaImportPlan.progress(done: 0, total: 12), "Adding 1 of 12\u{2026}")
        XCTAssertEqual(MediaImportPlan.progress(done: 11, total: 12), "Adding 12 of 12\u{2026}")
        XCTAssertNil(MediaImportPlan.summary(added: 5, failed: 0, trimmed: 0))
        XCTAssertEqual(MediaImportPlan.summary(added: 4, failed: 1, trimmed: 0), "4 added. 1 couldn\u{2019}t be added.")
        XCTAssertEqual(MediaImportPlan.summary(added: 0, failed: 1, trimmed: 0), "That one couldn\u{2019}t be added.")
        XCTAssertEqual(MediaImportPlan.summary(added: 0, failed: 3, trimmed: 0), "None of the 3 could be added.")
        XCTAssertEqual(MediaImportPlan.summary(added: 2, failed: 0, trimmed: 1), "One video was long, so its first part was kept.")
        XCTAssertEqual(MediaImportPlan.summary(added: 3, failed: 1, trimmed: 2),
                       "3 added. 1 couldn\u{2019}t be added. 2 videos were long, so their first parts were kept.")
    }
}

/// The schedule's Now card offers directions only while there is still a drive.
final class ScheduleLeadStepTests: XCTestCase {
    func testAtTheJobTheCardNamesTheNextStepInsteadOfNavigate() {
        for status in ["scheduled", "dispatched", "en_route"] { XCTAssertNil(ScheduleLead.stepTitle(status: status), status) }
        XCTAssertEqual(ScheduleLead.stepTitle(status: "arrived"), "Start work")
        XCTAssertEqual(ScheduleLead.stepTitle(status: "in_progress"), "Continue job")
        XCTAssertEqual(ScheduleLead.stepTitle(status: "paused"), "Resume job")
    }
}

/// A refused optional read is not asked for again in the same sign-in.
final class RefusedReadsTests: XCTestCase {
    private let job = "00000000-0000-4000-8000-000000002214"

    func testOnlyTheOptionalReadsAreRemembered() {
        XCTAssertEqual(RefusedReads.key("/v1/jobs/\(job)/booking-call"), "/v1/jobs/{id}/booking-call")
        XCTAssertEqual(RefusedReads.key("/v1/customers/\(job)/history"), "/v1/customers/{id}/history")
        XCTAssertEqual(RefusedReads.key("/v1/activity/invoice/\(job)"), "/v1/activity/invoice/{id}")
        XCTAssertEqual(RefusedReads.key("/v1/organization/mobile-layout"), "/v1/organization/mobile-layout")
        XCTAssertNil(RefusedReads.key("/v1/jobs/\(job)"))
        XCTAssertNil(RefusedReads.key("/v1/invoices/\(job)"))
    }

    func testA403IsRememberedForTheSignInAndA404OnlyForAMissingRoute() {
        var reads = RefusedReads()
        let scope = UUID()
        reads.note("/v1/jobs/\(job)/booking-call", status: 404, scope: scope)
        XCTAssertFalse(reads.isRefused("/v1/jobs/\(job)/booking-call", scope: scope), "No call on this job says nothing about the next")
        reads.note("/v1/jobs/\(job)/booking-call", status: 403, scope: scope)
        XCTAssertTrue(reads.isRefused("/v1/jobs/00000000-0000-4000-8000-000000002209/booking-call", scope: scope))
        reads.note("/v1/organization/mobile-layout", status: 404, scope: scope)
        XCTAssertTrue(reads.isRefused("/v1/organization/mobile-layout", scope: scope))
        reads.note("/v1/jobs/\(job)", status: 403, scope: scope)
        XCTAssertFalse(reads.isRefused("/v1/jobs/\(job)", scope: scope))
        XCTAssertFalse(reads.isRefused("/v1/organization/mobile-layout", scope: UUID()), "A new sign-in asks again")
    }
}

/// The job reads service-context first and only falls back where that route cannot answer.
final class JobServiceContextFallbackTests: XCTestCase {
    func testOnlyAMissingRouteOrNoAnswerFallsBack() {
        XCTAssertTrue(JobServiceContextLoader.fallsBackToCustomerReads(after: Problem(title: "Not found", status: 404, detail: nil)))
        XCTAssertTrue(JobServiceContextLoader.fallsBackToCustomerReads(after: URLError(.notConnectedToInternet)))
        XCTAssertFalse(JobServiceContextLoader.fallsBackToCustomerReads(after: Problem(title: "Forbidden", status: 403, detail: nil)))
        XCTAssertFalse(JobServiceContextLoader.fallsBackToCustomerReads(after: CancellationError()))
    }
}
