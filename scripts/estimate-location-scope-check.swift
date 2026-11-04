import Foundation
@MainActor @main struct Check {
 static func main() {
  precondition(CommercialDraftAccess.matchesLocation(expected: nil, actual: nil))
  precondition(CommercialDraftAccess.matchesLocation(expected: "one", actual: "one"))
  precondition(!CommercialDraftAccess.matchesLocation(expected: nil, actual: "one"))
  precondition(!CommercialDraftAccess.matchesLocation(expected: "one", actual: nil))
  precondition(!CommercialDraftAccess.matchesLocation(expected: "one", actual: "two"))
  print("PASS: recovered job location requires exact optional equality")
 }
}
