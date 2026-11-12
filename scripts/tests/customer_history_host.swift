import Foundation

// CUSTOMER_HISTORY_SOURCE

struct Record { let id: Int; let value: String }

@main struct Probe {
    static func main() {
        let jobs = Array(0..<600)
        var visible = CustomerJobHistory.initialCount
        precondition(Array(jobs.prefix(visible)) == [0, 1, 2, 3])
        var batches = 0
        while visible < jobs.count {
            let next = CustomerJobHistory.nextCount(total: jobs.count, visible: visible)
            precondition((1...25).contains(next))
            visible += next
            batches += 1
        }
        precondition(visible == 600 && Array(jobs.prefix(visible)) == jobs && batches == 24)
        precondition(Array(jobs.prefix(jobs.count)) == jobs) // Show all
        precondition(CustomerJobHistory.nextCount(total: 0, visible: 0) == 0)
        precondition(CustomerJobHistory.nextCount(total: 4, visible: 9) == 0)
        print("PASS 600 jobs reachable in bounded batches and Show all")

        let records = (0..<600).map { Record(id: $0, value: "first") } + [Record(id: 12, value: "duplicate")]
        let indexed = CustomerJobHistory.firstByID(records, id: \.id)
        precondition(indexed.count == 600 && indexed[12]?.value == "first")
        precondition(indexed[599]?.value == "first" && indexed[600] == nil)
        print("PASS indexed first-match identity and missing ID")
    }
}
