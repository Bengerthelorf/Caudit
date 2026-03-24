import XCTest
@testable import Claudit

final class ConsoleBillingServiceTests: XCTestCase {

    // MARK: - Spend Response Parsing

    func testParseSpendResponseBasic() throws {
        let json = """
        {
            "current_spend": 42.50,
            "hard_limit": 100.0,
            "soft_limit": 80.0
        }
        """.data(using: .utf8)!

        let result = try ConsoleBillingService.parseSpendResponse(json)
        XCTAssertEqual(result.currentSpend, 42.50, accuracy: 0.01)
        XCTAssertEqual(result.hardLimit, 100.0)
        XCTAssertEqual(result.softLimit, 80.0)
    }

    func testParseSpendResponseAlternateKeys() throws {
        let json = """
        {
            "total_spend": 15.00
        }
        """.data(using: .utf8)!

        let result = try ConsoleBillingService.parseSpendResponse(json)
        XCTAssertEqual(result.currentSpend, 15.00, accuracy: 0.01)
        XCTAssertNil(result.hardLimit)
        XCTAssertNil(result.softLimit)
    }

    func testParseSpendResponseFallbackToSpend() throws {
        let json = """
        {
            "spend": 7.25
        }
        """.data(using: .utf8)!

        let result = try ConsoleBillingService.parseSpendResponse(json)
        XCTAssertEqual(result.currentSpend, 7.25, accuracy: 0.01)
    }

    func testParseSpendResponseEmpty() throws {
        let json = "{}".data(using: .utf8)!
        let result = try ConsoleBillingService.parseSpendResponse(json)
        XCTAssertEqual(result.currentSpend, 0)
    }

    func testParseSpendResponseInvalidJSON() {
        let data = "not json".data(using: .utf8)!
        XCTAssertThrowsError(try ConsoleBillingService.parseSpendResponse(data))
    }

    // MARK: - Credits Response Parsing

    func testParseCreditsResponseTotal() throws {
        let json = """
        {"total": 500.0}
        """.data(using: .utf8)!

        let result = try ConsoleBillingService.parseCreditsResponse(json)
        XCTAssertEqual(result, 500.0, accuracy: 0.01)
    }

    func testParseCreditsResponseBalance() throws {
        let json = """
        {"balance": 250.0}
        """.data(using: .utf8)!

        let result = try ConsoleBillingService.parseCreditsResponse(json)
        XCTAssertEqual(result, 250.0, accuracy: 0.01)
    }

    func testParseCreditsResponseRemainingCredits() throws {
        let json = """
        {"remaining_credits": 100.0}
        """.data(using: .utf8)!

        let result = try ConsoleBillingService.parseCreditsResponse(json)
        XCTAssertEqual(result, 100.0, accuracy: 0.01)
    }

    func testParseCreditsResponseDataArray() throws {
        let json = """
        {"data": [
            {"remaining_amount": 100.0},
            {"remaining_amount": 50.0}
        ]}
        """.data(using: .utf8)!

        let result = try ConsoleBillingService.parseCreditsResponse(json)
        XCTAssertEqual(result, 150.0, accuracy: 0.01)
    }

    func testParseCreditsResponseTopLevelArray() throws {
        let json = """
        [
            {"amount": 200.0},
            {"amount": 100.0}
        ]
        """.data(using: .utf8)!

        let result = try ConsoleBillingService.parseCreditsResponse(json)
        XCTAssertEqual(result, 300.0, accuracy: 0.01)
    }

    func testParseCreditsResponseEmptyReturnsZero() throws {
        let json = "{}".data(using: .utf8)!
        let result = try ConsoleBillingService.parseCreditsResponse(json)
        XCTAssertEqual(result, 0)
    }

    // MARK: - Usage Cost Response Parsing

    func testParseUsageCostResponseWithData() throws {
        let json = """
        {"data": [
            {"api_key_id": "key1", "api_key_name": "Production", "cost": 25.0},
            {"api_key_id": "key2", "api_key_name": "Development", "cost": 10.0}
        ]}
        """.data(using: .utf8)!

        let result = try ConsoleBillingService.parseUsageCostResponse(json)
        XCTAssertEqual(result.count, 2)
        XCTAssertEqual(result[0].apiKeyId, "key1") // Sorted by cost desc
        XCTAssertEqual(result[0].cost, 25.0, accuracy: 0.01)
        XCTAssertEqual(result[0].apiKeyName, "Production")
        XCTAssertEqual(result[1].apiKeyId, "key2")
        XCTAssertEqual(result[1].cost, 10.0, accuracy: 0.01)
    }

    func testParseUsageCostResponseAggregatesSameKey() throws {
        let json = """
        {"data": [
            {"api_key_id": "key1", "api_key_name": "Production", "cost": 10.0},
            {"api_key_id": "key1", "cost": 5.0},
            {"api_key_id": "key2", "cost": 3.0}
        ]}
        """.data(using: .utf8)!

        let result = try ConsoleBillingService.parseUsageCostResponse(json)
        XCTAssertEqual(result.count, 2)
        // key1 should have aggregated cost of 15.0
        let key1 = result.first { $0.apiKeyId == "key1" }
        XCTAssertNotNil(key1)
        XCTAssertEqual(key1!.cost, 15.0, accuracy: 0.01)
        XCTAssertEqual(key1!.apiKeyName, "Production")
    }

    func testParseUsageCostResponseAlternateCostKeys() throws {
        let json = """
        [
            {"api_key_id": "key1", "total_cost": 30.0},
            {"api_key_id": "key2", "usage_cost": 15.0}
        ]
        """.data(using: .utf8)!

        let result = try ConsoleBillingService.parseUsageCostResponse(json)
        XCTAssertEqual(result.count, 2)
        let key1 = result.first { $0.apiKeyId == "key1" }
        XCTAssertNotNil(key1)
        XCTAssertEqual(key1!.cost, 30.0, accuracy: 0.01)
    }

    func testParseUsageCostResponseEmptyReturnsEmpty() throws {
        let json = "{}".data(using: .utf8)!
        let result = try ConsoleBillingService.parseUsageCostResponse(json)
        XCTAssertTrue(result.isEmpty)
    }

    func testParseUsageCostResponseWithUsageKey() throws {
        let json = """
        {"usage": [
            {"api_key_id": "key1", "cost": 12.0}
        ]}
        """.data(using: .utf8)!

        let result = try ConsoleBillingService.parseUsageCostResponse(json)
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].cost, 12.0, accuracy: 0.01)
    }

    // MARK: - ConsoleBilling Model

    func testSpendPercentage() {
        let billing = ConsoleBilling(
            currentSpend: 50.0,
            hardLimit: 200.0,
            softLimit: 150.0,
            prepaidCredits: 0,
            apiKeyUsage: [],
            lastUpdated: Date()
        )
        XCTAssertNotNil(billing.spendPercentage)
        XCTAssertEqual(billing.spendPercentage!, 25.0, accuracy: 0.01)
    }

    func testSpendPercentageNoLimit() {
        let billing = ConsoleBilling(
            currentSpend: 50.0,
            hardLimit: nil,
            softLimit: nil,
            prepaidCredits: 0,
            apiKeyUsage: [],
            lastUpdated: Date()
        )
        XCTAssertNil(billing.spendPercentage)
    }

    func testRemainingBudget() {
        let billing = ConsoleBilling(
            currentSpend: 75.0,
            hardLimit: 100.0,
            softLimit: nil,
            prepaidCredits: 0,
            apiKeyUsage: [],
            lastUpdated: Date()
        )
        XCTAssertNotNil(billing.remainingBudget)
        XCTAssertEqual(billing.remainingBudget!, 25.0, accuracy: 0.01)
    }

    func testRemainingBudgetOverSpend() {
        let billing = ConsoleBilling(
            currentSpend: 150.0,
            hardLimit: 100.0,
            softLimit: nil,
            prepaidCredits: 0,
            apiKeyUsage: [],
            lastUpdated: Date()
        )
        XCTAssertNotNil(billing.remainingBudget)
        XCTAssertEqual(billing.remainingBudget!, 0, accuracy: 0.01)
    }

    // MARK: - ConsoleBillingError

    func testErrorDescriptions() {
        XCTAssertNotNil(ConsoleBillingError.noCredentials.errorDescription)
        XCTAssertNotNil(ConsoleBillingError.sessionExpired.errorDescription)
        XCTAssertNotNil(ConsoleBillingError.invalidResponse.errorDescription)
        XCTAssertNotNil(ConsoleBillingError.httpError(500).errorDescription)
    }

    func testErrorEquality() {
        XCTAssertEqual(ConsoleBillingError.noCredentials, ConsoleBillingError.noCredentials)
        XCTAssertEqual(ConsoleBillingError.httpError(404), ConsoleBillingError.httpError(404))
        XCTAssertNotEqual(ConsoleBillingError.httpError(404), ConsoleBillingError.httpError(500))
        XCTAssertNotEqual(ConsoleBillingError.noCredentials, ConsoleBillingError.sessionExpired)
    }
}
