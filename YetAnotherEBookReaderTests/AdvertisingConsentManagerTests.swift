import XCTest
@testable import YetAnotherEBookReader

@MainActor
final class AdvertisingConsentManagerTests: XCTestCase {
    private enum Failure: Error { case consent }

    func testConsentPrecedesATTAndAdsRemainBlockedUntilInitializationFinishes() async {
        var events: [String] = []
        var manager: AdvertisingConsentManager?
        let subject = AdvertisingConsentManager(
            updateConsent: { events.append("update") },
            presentConsent: { events.append("GDPR") },
            consentAllowsAds: { true },
            requestTracking: {
                events.append("ATT")
                XCTAssertFalse(manager?.canRequestAds ?? true)
            },
            startAds: {
                events.append("ads")
                XCTAssertFalse(manager?.canRequestAds ?? true)
            }
        )
        manager = subject
        await subject.gatherConsent()
        XCTAssertEqual(events, ["update", "GDPR", "ATT", "ads"])
        XCTAssertTrue(subject.canRequestAds)
        manager = nil
    }

    func testConsentFailureBlocksATTAndAdsEvenWithPreviouslyCachedConsent() async {
        var requestedTracking = false
        var startedAds = false
        let manager = AdvertisingConsentManager(
            updateConsent: { throw Failure.consent },
            presentConsent: { XCTFail("Must not present after update fails") },
            consentAllowsAds: { true },
            requestTracking: { requestedTracking = true },
            startAds: { startedAds = true }
        )
        await manager.gatherConsent()
        XCTAssertFalse(requestedTracking)
        XCTAssertFalse(startedAds)
        XCTAssertFalse(manager.canRequestAds)
    }

    func testFormFailureBlocksATTAndAds() async {
        let manager = AdvertisingConsentManager(
            updateConsent: {},
            presentConsent: { throw Failure.consent },
            consentAllowsAds: { true },
            requestTracking: { XCTFail("ATT must wait for consent form completion") },
            startAds: { XCTFail("Ads must wait for consent form completion") }
        )
        await manager.gatherConsent()
        XCTAssertFalse(manager.canRequestAds)
    }

    func testConsentNotReadyDoesNotRequestATTOrAds() async {
        let manager = AdvertisingConsentManager(
            updateConsent: {}, presentConsent: {}, consentAllowsAds: { false },
            requestTracking: { XCTFail("No ATT before consent allows ads") },
            startAds: { XCTFail("No ads without consent") }
        )
        await manager.gatherConsent()
        XCTAssertFalse(manager.canRequestAds)
    }

    func testRepeatedAndConcurrentTriggersDoNotRepeatPrompts() async {
        var formCount = 0
        var attCount = 0
        var startCount = 0
        var manager: AdvertisingConsentManager?
        let subject = AdvertisingConsentManager(
            updateConsent: {},
            presentConsent: {
                formCount += 1
                await manager?.gatherConsent()
            },
            consentAllowsAds: { true },
            requestTracking: { attCount += 1 },
            startAds: { startCount += 1 }
        )
        manager = subject
        await subject.gatherConsent()
        await subject.gatherConsent()
        XCTAssertEqual(formCount, 1)
        XCTAssertEqual(attCount, 1)
        XCTAssertEqual(startCount, 1)
        manager = nil
    }

    func testAnExistingATTDecisionIsNotRequestedAgain() async {
        var events: [String] = []
        let manager = AdvertisingConsentManager(
            updateConsent: { events.append("update") },
            presentConsent: { events.append("GDPR") },
            consentAllowsAds: { true },
            trackingAuthorizationRequired: { false },
            requestTracking: { XCTFail("Respect an existing ATT denial or authorization") },
            startAds: { events.append("ads") }
        )
        await manager.gatherConsent()
        XCTAssertEqual(events, ["update", "GDPR", "ads"])
        XCTAssertTrue(manager.canRequestAds)
    }

    func testConsentCanBecomeAvailableOnARetry() async {
        var allowsAds = false
        var events: [String] = []
        let manager = AdvertisingConsentManager(
            updateConsent: { events.append("update") },
            presentConsent: { events.append("GDPR") },
            consentAllowsAds: { allowsAds },
            requestTracking: { events.append("ATT") },
            startAds: { events.append("ads") }
        )
        await manager.gatherConsent()
        XCTAssertFalse(manager.canRequestAds)
        XCTAssertEqual(events, ["update", "GDPR"])
        allowsAds = true
        await manager.gatherConsent()
        XCTAssertTrue(manager.canRequestAds)
        XCTAssertEqual(events, ["update", "GDPR", "update", "GDPR", "ATT", "ads"])
    }
}
