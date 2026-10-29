import XCTest
@testable import QuotaView

final class BrandAnnouncementTests: XCTestCase {
    func testEachEligibleReleaseGetsItsOwnReminder() {
        let campaign = BrandAnnouncementCampaign(id: "fixture", releaseBuilds: ["101", "102"])
        XCTAssertTrue(campaign.shouldPresent(build: "101", acknowledged: []))
        let first = campaign.acknowledging(build: "101", in: [])
        XCTAssertFalse(campaign.shouldPresent(build: "101", acknowledged: first))
        XCTAssertTrue(campaign.shouldPresent(build: "102", acknowledged: first))
        let both = campaign.acknowledging(build: "102", in: first)
        XCTAssertFalse(campaign.shouldPresent(build: "102", acknowledged: both))
        XCTAssertEqual(both, ["101", "102"])
    }

    func testSkippingFirstReleaseStillShowsSecondButNotLaterBuilds() {
        let campaign = BrandAnnouncementCampaign(id: "fixture", releaseBuilds: ["101", "102"])
        XCTAssertTrue(campaign.shouldPresent(build: "102", acknowledged: []))
        XCTAssertFalse(campaign.shouldPresent(build: "103", acknowledged: []))
        XCTAssertEqual(campaign.acknowledging(build: "103", in: ["101"]), ["101"])
    }

    func testUnconfiguredCampaignCannotAnnounceAndCampaignReceiptsAreSeparate() {
        let unconfigured = BrandAnnouncementCampaign(id: "preview", releaseBuilds: [])
        XCTAssertFalse(unconfigured.shouldPresent(build: "91", acknowledged: []))
        XCTAssertNotEqual(BrandAnnouncementCampaign(id: "first", releaseBuilds: []).storageKey,
                          BrandAnnouncementCampaign(id: "second", releaseBuilds: []).storageKey)
    }
}
