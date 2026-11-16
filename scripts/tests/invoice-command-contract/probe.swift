import Foundation
@main struct Probe {
 static func main() throws {
 let directory = ProcessInfo.processInfo.environment["INVOICE_PROBE_DIR"]!
 let id = "00000000-0000-4000-8000-000000000001"
 let t = "2026-11-12T12:00:00Z"
 let manual = FieldLineSource(kind: "manual")
 let estimate = FieldLineSource(kind: "estimate", estimateId: id, estimateRevisionNumber: 1, estimateLineId: id, estimateLineSource: FieldEstimateLineSourceSnapshot(kind: "manual", addedByUserId:id, capturedAt:t))
 let pricebook = FieldLineSource(kind: "price_book", priceBookItemId: id, priceBookRevision: 1, originalDescription: "Original", originalUnit: "each", originalUnitPrice: .init(amount: 200, currency: "USD"), originalTaxClassification: "taxable", originalItemKind: "service", addedByUserId: id, capturedAt: t, overriddenFields: [])
 let lines = [manual,estimate,pricebook].enumerated().map { idx, source in FieldLine(id: "00000000-0000-4000-8000-00000000000\(idx + 2)", description: "Original", quantity: 1, unitPrice: .init(amount: 200,currency:"USD"), source: source) }
 let invoice = InvoiceRecord(id:id, organizationId:id, customerId:id, jobId:nil, createdByUserId:id, locationId:nil, scheduleId:nil, origin:"manual", sourceOperationKey:"key", sourceEstimateId:nil, sourceEstimateRevisionNumber:nil, manualPhysicalServiceEvidence:nil, status:"draft", lines:lines, linesRevision:1, amountPaid:0, currency:"USD", issuedAt:nil, paidAt:nil, voidedAt:nil, createdAt:t, updatedAt:t)
 let scope = InvoiceDraftRecoveryScope(actorID:id, organizationID:id, origin:"https://app.thorbis.com", invoiceID:id, customerID:id, jobID:nil)
 var state=InvoiceLineEditorState(invoice:invoice)
 state.lines[0].description = "É plumbing 🚰\n\"quoted\""
 try state.addPriceBookItem(.init(id:id,description:"New item",unit:"each",kind:"service",taxClassification:"taxable",sellPrice:.init(amount: 400,currency:"USD"),revision:1,archivedAt:nil))
 let snapshot = try InvoiceDraftRecovery(scope:scope,state:state,writeState:.idle)
 let command = try InvoiceKeyedEdit.prepare(snapshot:snapshot,expectedScope:scope,expectedSnapshotID:snapshot.snapshotID,commandID:UUID(uuidString:id)!,deviceID:UUID(uuidString:id)!,policyVersion:1,clientCreatedAt:t)
 try command.envelopeBytes.write(to:URL(fileURLWithPath: directory).appendingPathComponent("envelope.json"))
 print("actual model envelope bytes: \(command.envelopeBytes.count)")
 var bulk = InvoiceLineEditorState(invoice: invoice)
 bulk.lines = []
 bulk.priceBookOverrideReason = "Testing a replacement"
 var last: InvoiceKeyedEdit?
 for _ in 0..<500 {
   bulk.lines.append(.init(description:String(repeating:"a", count:211),quantity:"1",unitPrice:"1.00",source:.manual))
   let snap = try InvoiceDraftRecovery(scope:scope,state:bulk,writeState:.idle)
   do { last = try InvoiceKeyedEdit.prepare(snapshot:snap,expectedScope:scope,expectedSnapshotID:snap.snapshotID,commandID:UUID(uuidString:id)!,deviceID:UUID(uuidString:id)!,policyVersion:1,clientCreatedAt:t) }
   catch { bulk.lines.removeLast(); break }
 }
 bulk.lines[bulk.lines.count - 1].description = String(repeating: "a", count:111)
 for n in 1...211 {
   var candidate = bulk
   candidate.lines.append(.init(description:String(repeating:"b",count:n),quantity:"1",unitPrice:"1.00",source:.manual))
   let snap = try InvoiceDraftRecovery(scope:scope,state:candidate,writeState:.idle)
   do { last = try InvoiceKeyedEdit.prepare(snapshot:snap,expectedScope:scope,expectedSnapshotID:snap.snapshotID,commandID:UUID(uuidString:id)!,deviceID:UUID(uuidString:id)!,policyVersion:1,clientCreatedAt:t) } catch { break }
 }
 guard let last else { fatalError("no boundary envelope") }
 try last.envelopeBytes.write(to:URL(fileURLWithPath: directory).appendingPathComponent("boundary.json"))
 print("actual model boundary bytes: \(last.envelopeBytes.count)")

 }
}
