// Standalone contract harness; compile with the production AtomicEstimateCommand.swift.
// The minimal JobRecord type is only here because the production model's held
// scope predicate refers to it. The wire encoder and response decoder are real.
import Foundation

struct JobRecord {
    let id, organizationId, customerId: String
    let locationId: String?
    let status: String
}

@main struct AtomicEstimateContractFixture {
    static func main() throws {
        let args = CommandLine.arguments
        guard args.count == 8 else { fatalError("expected mode, job, customer, actor, organization, command ID, status") }
        let operation = try AtomicEstimateCommand.make(
            jobID: args[2], draftCustomerID: args[3], draftLocationID: nil,
            title: "Contract test estimate", lines: [.init(description: "Test valve", quantity: 2,
                unitPrice: .init(amount: 12500, currency: "USD"), source: .manual,
                group: nil, showToCustomer: nil)], actorID: args[4], organizationID: args[5],
            deviceID: "018f0000-0000-7000-8000-00000000d001", policyVersion: 1,
            origin: "https://example.test", createdAt: "2026-11-03T00:00:00Z",
            commandID: args[6])
        switch args[1] {
        case "envelope":
            FileHandle.standardOutput.write(try JSONEncoder().encode(operation.batch()))
        case "response":
            let data = FileHandle.standardInput.readDataToEndOfFile()
            let response = try JSONDecoder().decode(AtomicEstimateCommand.Response.self, from: data)
            guard response.outcomes.count == 1, response.outcomes[0].status == args[7] else { fatalError("unexpected server outcome") }
            if args[7] == "rejected" {
                guard operation.interpret(response) == .needsReview else { fatalError("rejection did not remain held") }
            } else {
                guard case .linked = operation.interpret(response) else { fatalError("server link did not bind to the operation") }
            }
            print("Swift accepted the server's bound \(args[7]) response")
        default: fatalError("unsupported mode")
        }
    }
}
