import Foundation
struct FieldMoney { let amount: Int; let currency: String }
struct FieldLine { let quantity: Int; let unitPrice: FieldMoney }
struct EstimateRecord { let status: String; let lines: [FieldLine] }
struct InvoiceRecord { let status: String; let lines: [FieldLine]; let amountPaid: Int; let currency: String }
// FINANCIAL_SOURCE
func line(_ amount: Int, quantity: Int = 1, currency: String = "USD") -> FieldLine {
    FieldLine(quantity: quantity, unitPrice: FieldMoney(amount: amount, currency: currency))
}
@main struct Probe {
    static func main() {
        let goodEstimate = EstimateRecord(status: "sent", lines: [line(12000)])
        let goodInvoice = InvoiceRecord(status: "issued", lines: [line(12000)], amountPaid: 2000, currency: "USD")
        precondition(estimatesSummary([goodEstimate]).contains("$120.00"))
        precondition(invoicesSummary([goodInvoice]).contains("$100.00"))
        precondition(estimatesSummary([]) == "Nothing waiting on customers")
        precondition(invoicesSummary([]) == "Everything is paid")
        let hugeEstimate = EstimateRecord(status: "sent", lines: [line(Int.max)])
        let hugeInvoice = InvoiceRecord(status: "issued", lines: [line(Int.max)], amountPaid: 0, currency: "USD")
        precondition(estimatesSummary([hugeEstimate, hugeEstimate]).contains("unavailable"))
        precondition(invoicesSummary([hugeInvoice, hugeInvoice]).contains("unavailable"))
        precondition(invoicesSummary([InvoiceRecord(status: "issued", lines: [line(100)], amountPaid: -1, currency: "USD")]).contains("unavailable"))
        precondition(invoicesSummary([InvoiceRecord(status: "issued", lines: [line(100, currency: "EUR")], amountPaid: 0, currency: "USD")]).contains("unavailable"))
        precondition(estimatesSummary([EstimateRecord(status: "sent", lines: [line(Int.max, quantity: 2)])]).contains("unavailable"))
        precondition(invoicesSummary([InvoiceRecord(status: "issued", lines: [line(100)], amountPaid: Int.min, currency: "USD")]).contains("unavailable"))
        precondition(invoicesSummary([goodInvoice, InvoiceRecord(status: "draft", lines: [line(Int.max, quantity: 2)], amountPaid: 0, currency: "USD")]).contains("$100.00"))
        precondition(estimatesSummary([goodEstimate, EstimateRecord(status: "draft", lines: [line(Int.max, quantity: 2)])]).contains("$120.00"))
        precondition(invoicesSummary([goodInvoice, InvoiceRecord(status: "issued", lines: [line(100, currency: "EUR")], amountPaid: 0, currency: "USD")]).contains("unavailable"))
        precondition(invoicesSummary([InvoiceRecord(status: "issued", lines: [line(100)], amountPaid: 200, currency: "USD")]).contains("$0.00"))
        let creditLines = [line(12000), line(-2000)]
        precondition(estimatesSummary([EstimateRecord(status: "sent", lines: creditLines)]).contains("$100.00"))
        precondition(invoicesSummary([InvoiceRecord(status: "issued", lines: creditLines, amountPaid: 1000, currency: "USD")]).contains("$90.00"))
        precondition(invoicesSummary([InvoiceRecord(status: "issued", lines: [line(100), line(-101)], amountPaid: 0, currency: "USD")]).contains("unavailable"))
        precondition(invoicesSummary([InvoiceRecord(status: "issued", lines: [line(100, quantity: 0)], amountPaid: 0, currency: "USD")]).contains("unavailable"))
        print("financial summaries checked")
    }
}
