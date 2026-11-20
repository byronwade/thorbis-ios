import Foundation
struct FieldMoney: Codable, Hashable, Sendable { let amount:Int; let currency:String }
struct FieldLine: Codable, Identifiable, Hashable, Sendable { let id:String; let description:String; let quantity:Int; let unitPrice:FieldMoney; let source:String?; var group:String? = nil; var showToCustomer:Bool? = nil }
struct FieldEstimateOption: Codable, Hashable { let id:String; let title:String; let description:String; let lines:[FieldLine]; let totalAmount:Int; let currency:String }
struct CustomerIssuedEstimateRevision { let id:String; let estimateId:String; let revisionNumber:Int; let status:String; let lines:[FieldLine]; let options:[FieldEstimateOption]?; let totalAmount:Int; let currency:String }
struct Problem: Error { let title:String?; let status:Int?; let detail:String? }
func customerEstimateProjection(_ lines:[FieldLine], currency:String)->[FieldLine]? { lines }
func total(_ lines:[FieldLine])->Int { lines.reduce(0) { $0 + $1.quantity * $1.unitPrice.amount } }
struct CustomerDocumentAmounts { let total:Int; init?(lines:[FieldLine],currency:String) { guard lines.allSatisfy({ $0.quantity > 0 && $0.unitPrice.currency == currency }) else { return nil }; total = Swift.max(0, Swift.min(Int.max, lines.reduce(0) { $0 + $1.quantity * $1.unitPrice.amount })) } }
// ACTUAL_RECEIPT
@main struct Test {
 static func main() throws {
 let line=FieldLine(id:"line",description:"Repair",quantity:1,unitPrice:.init(amount:19000,currency:"USD"),source:nil)
 let option=FieldEstimateOption(id:"option",title:"Package",description:"",lines:[line],totalAmount:19000,currency:"USD")
 let revision=CustomerIssuedEstimateRevision(id:"revision",estimateId:"estimate",revisionNumber:1,status:"approved",lines:[],options:[option],totalAmount:19000,currency:"USD")
 let base="""
 {"id":"receipt","estimateId":"estimate","revisionId":"revision","revisionNumber":1,"contentHash":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","optionId":"option","optionTitle":"Package","signerName":"Alex","acceptedAt":"2026-11-13T00:00:00Z","totalAmount":19000,"currency":"USD","lines":[{"id":"line","description":"Repair","quantity":1,"unitPrice":{"amount":19000,"currency":"USD"}}]}
 """
 func receipt(_ json:String) throws -> CustomerEstimateAcceptanceReceipt {try JSONDecoder().decode(CustomerEstimateAcceptanceReceipt.self, from:Data(json.utf8))}
 let valid=try receipt(base); try valid.validate(for:revision)
 for mutated in [base.replacingOccurrences(of:"\"revisionId\":\"revision\"",with:"\"revisionId\":\"other\""), base.replacingOccurrences(of:"\"optionId\":\"option\"",with:"\"optionId\":\"other\""), base.replacingOccurrences(of:"Repair",with:"Different"),base.replacingOccurrences(of:"19000",with:"18000")] { do { try receipt(mutated).validate(for:revision); fatalError("accepted mismatched receipt") } catch {} }
 print("receipt validation passed")
 }
}
