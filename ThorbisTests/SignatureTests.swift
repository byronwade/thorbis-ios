import XCTest
@testable import Thorbis

final class SignatureTests: XCTestCase {
    func testSignatureInputMatchesTheApproveContract() throws {
        let input = FieldSignatureInput(signerName: "Dana Customer", signedAt: "2026-10-27T15:00:00Z",
                                        imageMediaId: "00000000-0000-4000-8000-000000000001")
        let json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(input)) as? [String: String]
        XCTAssertEqual(json, ["signerName": "Dana Customer", "signedAt": "2026-10-27T15:00:00Z",
                              "imageMediaId": "00000000-0000-4000-8000-000000000001"])
    }

    func testInvoiceAuthorizationDecodesAndTracksTheSignedRevision() throws {
        let json = #"{"id":"a","invoiceId":"i","linesRevision":3,"totalAmount":34000,"currency":"USD","signerName":"Dana","signedAt":"2026-10-27T15:00:00Z","imageMediaId":"m","capturedByUserId":"u","recordedAt":"2026-10-27T15:00:01Z"}"#
        let signature = try JSONDecoder().decode(FieldSignatureRecord.self, from: Data(json.utf8))
        XCTAssertEqual(signature.signerName, "Dana")
        XCTAssertEqual(signature.linesRevision, 3)
    }
}
