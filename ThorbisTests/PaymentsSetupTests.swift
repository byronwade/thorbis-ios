import XCTest
@testable import Thorbis

@MainActor
final class PaymentsSetupTests: XCTestCase {
    private let actionRequired = #"{"state":"action_required","chargesReady":false,"payoutsReady":false,"actionRequired":true,"requirements":{"eventuallyDueCount":1,"currentlyDueCount":2,"pastDueCount":0}}"#

    func testReadinessDecodesAndSaysWhatToDo() async throws {
        let api = APIClient(session: URLProtocolFixture.session([.init(200, actionRequired)]), baseURL: "https://app.thorbis.com")

        let readiness = try await api.merchantReadiness()

        XCTAssertEqual(readiness.state, "action_required")
        XCTAssertEqual(readiness.requirements.total, 3)
        XCTAssertEqual(readiness.headline, "Stripe needs something from you")
        XCTAssertEqual(readiness.actionTitle, "Open Stripe")
        XCTAssertEqual(URLProtocolFixture.recorded.first?.url?.path, "/v1/organization/merchant-readiness")
    }

    func testReadyAndUnderReviewOfferNoHostedPage() throws {
        let ready = #"{"state":"ready","chargesReady":true,"payoutsReady":true,"actionRequired":false,"requirements":{"eventuallyDueCount":0,"currentlyDueCount":0,"pastDueCount":0}}"#
        let review = #"{"state":"under_review","chargesReady":false,"payoutsReady":false,"actionRequired":false,"requirements":{"eventuallyDueCount":0,"currentlyDueCount":0,"pastDueCount":0}}"#
        XCTAssertNil(try JSONDecoder().decode(MerchantReadiness.self, from: Data(ready.utf8)).actionTitle)
        XCTAssertNil(try JSONDecoder().decode(MerchantReadiness.self, from: Data(review.utf8)).actionTitle)
    }

    func testOnboardingPostsWithoutBodyAndOnlyOpensStripe() async throws {
        let link = #"{"url":"https://connect.stripe.com/setup/e/acct_1/abc","expiresAt":"2026-10-28T03:00:00.000Z"}"#
        let api = APIClient(session: URLProtocolFixture.session([.init(201, link)]), baseURL: "https://app.thorbis.com")

        let hosted = try await api.startMerchantOnboarding()

        XCTAssertEqual(hosted.safeURL?.host, "connect.stripe.com")
        let request = try XCTUnwrap(URLProtocolFixture.recorded.first)
        XCTAssertEqual(request.method, "POST")
        XCTAssertEqual(request.url?.path, "/v1/organization/merchant-onboarding")

        for bad in ["http://connect.stripe.com/x", "https://stripe.com.evil.example/x", "https://evilstripe.com/x", "thorbis://schedule"] {
            XCTAssertNil(HostedMerchantOnboardingLink(url: bad, expiresAt: "2026-10-28T03:00:00.000Z").safeURL, bad)
        }
    }

    func testReturnReconcilesReadiness() async throws {
        let api = APIClient(session: URLProtocolFixture.session([.init(200, actionRequired)]), baseURL: "https://app.thorbis.com")

        _ = try await api.reconcileMerchantOnboarding()

        XCTAssertEqual(URLProtocolFixture.recorded.first?.url?.path, "/v1/organization/merchant-onboarding/return")
        XCTAssertEqual(URLProtocolFixture.recorded.first?.method, "GET")
    }

    func testMoneyAvailabilityDecodesServerWording() async throws {
        let body = #"{"version":1,"asOf":"2026-10-28T03:00:00.000Z","balances":[{"currency":"USD","available":-1200,"pending":0,"explanation":"The balance is negative."}],"payouts":[{"state":"failed","amount":5000,"currency":"USD","arrivalDate":"2026-10-27","title":"Payout failed","explanation":"The bank rejected this payout.","responsibleActor":"owner","providerCode":"account_closed"}],"attention":{"title":"Fix your bank account in Stripe","explanation":"The bank rejected this payout."}}"#
        let api = APIClient(session: URLProtocolFixture.session([.init(200, body)]), baseURL: "https://app.thorbis.com")

        let money = try await api.moneyAvailability()

        XCTAssertEqual(URLProtocolFixture.recorded.first?.url?.path, "/v1/organization/money-availability")
        XCTAssertEqual(money.balances.first?.available, -1200)
        XCTAssertEqual(money.payouts.first?.responsibleActor, "owner")
        XCTAssertEqual(money.attention?.title, "Fix your bank account in Stripe")
    }
}
