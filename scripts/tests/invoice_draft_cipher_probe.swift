import Foundation
import CryptoKit

@main struct InvoiceDraftCipherProbe {
    static func main() throws {
        let domain = InvoiceFenceDomain(origin: "https://app.thorbis.com", organizationID: "00000000-0000-4000-8000-000000000001", invoiceID: "00000000-0000-4000-8000-000000000002")
        let scope = InvoiceIdleCaptureIdentity(domain: domain, actorID: "00000000-0000-4000-8000-000000000003", customerID: "00000000-0000-4000-8000-000000000004", jobID: nil)
        let other = InvoiceIdleCaptureIdentity(domain: domain, actorID: "00000000-0000-4000-8000-000000000005", customerID: scope.customerID, jobID: nil)
        let owner = UUID(), key = SymmetricKey(size: .bits256), raw = Data("sensitive raw\n- .".utf8)
        let first = try InvoiceDraftCipher.seal(raw, identity: scope, owner: owner, sequence: 1, key: key)
        let second = try InvoiceDraftCipher.seal(raw, identity: scope, owner: owner, sequence: 1, key: key)
        precondition(first.ciphertext != second.ciphertext && first.ciphertext.range(of: raw) == nil)
        let opened = try InvoiceDraftCipher.open(first.ciphertext, identity: scope, owner: owner, sequence: 1, key: key)
        precondition(opened == raw)
        func denied(_ cipher: Data, _ identity: InvoiceIdleCaptureIdentity, _ id: UUID, _ seq: Int64, _ key: SymmetricKey) -> Bool {
            (try? InvoiceDraftCipher.open(cipher, identity: identity, owner: id, sequence: seq, key: key)) == nil
        }
        precondition(denied(first.ciphertext, other, owner, 1, key))
        precondition(denied(first.ciphertext, scope, UUID(), 1, key))
        precondition(denied(first.ciphertext, scope, owner, 2, key))
        precondition(denied(first.ciphertext, scope, owner, 1, SymmetricKey(size: .bits256)))
        var corrupt = first.ciphertext; corrupt[corrupt.startIndex] ^= 1
        precondition(denied(corrupt, scope, owner, 1, key))
        print("invoice draft cipher: scope, sequence and authentication checks passed")
    }
}
