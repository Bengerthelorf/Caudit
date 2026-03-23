import XCTest
@testable import Claudit

final class QuotaServiceTests: XCTestCase {

    // MARK: - Rate Limit Headers Parsing

    func testParseHeadersBasic() {
        let response = makeHTTPResponse(headers: [
            "anthropic-ratelimit-unified-5h-utilization": "0.42",
            "anthropic-ratelimit-unified-7d-utilization": "0.28",
            "anthropic-ratelimit-unified-5h-reset": "1774565400",
            "anthropic-ratelimit-unified-7d-reset": "1775000000",
        ])
        let info = RateLimitHeadersQuotaProvider.parseHeaders(response)
        XCTAssertEqual(info.fiveHourUtilization, 42, accuracy: 0.1)
        XCTAssertEqual(info.sevenDayUtilization, 28, accuracy: 0.1)
        XCTAssertNotNil(info.fiveHourResetAt)
        XCTAssertNotNil(info.sevenDayResetAt)
    }

    func testParseHeadersMissingValues() {
        let response = makeHTTPResponse(headers: [:])
        let info = RateLimitHeadersQuotaProvider.parseHeaders(response)
        XCTAssertEqual(info.fiveHourUtilization, 0)
        XCTAssertEqual(info.sevenDayUtilization, 0)
        XCTAssertNil(info.fiveHourResetAt)
        XCTAssertNil(info.sevenDayResetAt)
    }

    func testParseHeadersNoModelBreakdown() {
        let response = makeHTTPResponse(headers: [
            "anthropic-ratelimit-unified-5h-utilization": "0.50",
            "anthropic-ratelimit-unified-7d-utilization": "0.30",
        ])
        let info = RateLimitHeadersQuotaProvider.parseHeaders(response)
        XCTAssertNil(info.sevenDayOpusUtilization)
        XCTAssertNil(info.sevenDaySonnetUtilization)
    }

    func testParseHeadersPastResetForcesZero() {
        // Reset time in the past means session has already reset
        let pastTimestamp = String(Int(Date().timeIntervalSince1970 - 3600))
        let response = makeHTTPResponse(headers: [
            "anthropic-ratelimit-unified-5h-utilization": "0.75",
            "anthropic-ratelimit-unified-7d-utilization": "0.40",
            "anthropic-ratelimit-unified-5h-reset": pastTimestamp,
        ])
        let info = RateLimitHeadersQuotaProvider.parseHeaders(response)
        XCTAssertEqual(info.fiveHourUtilization, 0)
        XCTAssertNil(info.fiveHourResetAt)
    }

    // MARK: - OAuth API Response Parsing

    func testParseOAuthResponseFiveHourAndSevenDay() throws {
        let json = """
        {
            "five_hour": {"utilization_pct": 65.5, "resets_at": "2026-03-23T18:00:00Z"},
            "seven_day": {"utilization_pct": 30.2, "resets_at": "2026-03-30T00:00:00Z"},
            "seven_day_opus": {"utilization_pct": 10.0},
            "seven_day_sonnet": {"utilization_pct": 5.0}
        }
        """.data(using: .utf8)!

        let info = try OAuthAPIQuotaProvider.parseResponse(json)
        XCTAssertEqual(info.fiveHourUtilization, 65.5)
        XCTAssertEqual(info.sevenDayUtilization, 30.2)
        XCTAssertEqual(info.sevenDayOpusUtilization, 10.0)
        XCTAssertEqual(info.sevenDaySonnetUtilization, 5.0)
        XCTAssertNotNil(info.fiveHourResetAt)
    }

    func testParseOAuthResponseSessionKey() throws {
        let json = """
        {
            "session": {"utilization": 42.0, "resets_at": "2026-03-23T20:00:00Z"},
            "weekly": {"utilization": 15.0}
        }
        """.data(using: .utf8)!

        let info = try OAuthAPIQuotaProvider.parseResponse(json)
        XCTAssertEqual(info.fiveHourUtilization, 42.0)
        XCTAssertEqual(info.sevenDayUtilization, 15.0)
    }

    func testParseOAuthResponseInvalidJSON() {
        let data = "not json".data(using: .utf8)!
        XCTAssertThrowsError(try OAuthAPIQuotaProvider.parseResponse(data))
    }

    func testParseOAuthResponseEmpty() throws {
        let json = "{}".data(using: .utf8)!
        let info = try OAuthAPIQuotaProvider.parseResponse(json)
        XCTAssertEqual(info.fiveHourUtilization, 0)
        XCTAssertEqual(info.sevenDayUtilization, 0)
    }

    // MARK: - QuotaSource

    func testQuotaSourceRawValues() {
        XCTAssertEqual(QuotaSource.rateLimitHeaders.rawValue, "Auto (Rate Limit Headers)")
        XCTAssertEqual(QuotaSource.oauthAPI.rawValue, "OAuth API")
        XCTAssertEqual(QuotaSource.claudeSession.rawValue, "Claude.ai Session")
    }

    func testQuotaSourceRoundTrip() {
        for source in QuotaSource.allCases {
            XCTAssertEqual(QuotaSource(rawValue: source.rawValue), source)
        }
    }

    // MARK: - SessionCredentialStore

    func testSessionStoreIsExpiredWhenNoExpiry() {
        // When expiryDate is nil, isExpired should be false
        XCTAssertFalse(SessionCredentialStore.shared.isExpired || false)
    }

    // MARK: - Helpers

    private func makeHTTPResponse(headers: [String: String]) -> HTTPURLResponse {
        HTTPURLResponse(
            url: URL(string: "https://api.anthropic.com/v1/messages")!,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: headers
        )!
    }
}
