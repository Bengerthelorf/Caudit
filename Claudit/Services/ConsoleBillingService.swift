import Foundation
import os.log

private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Claudit", category: "ConsoleBilling")

/// Fetches billing data from console.anthropic.com API.
final class ConsoleBillingService: Sendable {

    /// Fetch all billing data (spend, credits, per-key usage) in parallel.
    func fetchBilling() async throws -> ConsoleBilling {
        guard let creds = ConsoleCredentialStore.shared.credentials() else {
            throw ConsoleBillingError.noCredentials
        }
        let sessionKey = creds.sessionKey
        let orgId = creds.organizationId

        // Fetch spend, credits, and usage in parallel
        async let spendResult = fetchCurrentSpend(sessionKey: sessionKey, orgId: orgId)
        async let creditsResult = fetchPrepaidCredits(sessionKey: sessionKey, orgId: orgId)
        async let usageResult = fetchUsageCost(sessionKey: sessionKey, orgId: orgId)

        let spend = try await spendResult
        let credits = try await creditsResult
        let usage = try await usageResult

        return ConsoleBilling(
            currentSpend: spend.currentSpend,
            hardLimit: spend.hardLimit,
            softLimit: spend.softLimit,
            prepaidCredits: credits,
            apiKeyUsage: usage,
            lastUpdated: Date()
        )
    }

    // MARK: - Current Spend

    struct SpendResponse: Sendable {
        let currentSpend: Double
        let hardLimit: Double?
        let softLimit: Double?
    }

    private func fetchCurrentSpend(sessionKey: String, orgId: String) async throws -> SpendResponse {
        guard let url = URL(string: "https://console.anthropic.com/api/organizations/\(orgId)/current_spend") else {
            throw ConsoleBillingError.invalidResponse
        }
        let (data, httpResponse) = try await performRequest(url: url, sessionKey: sessionKey)

        await NetworkLogService.shared.record(
            method: "GET", url: url.absoluteString,
            statusCode: httpResponse.statusCode,
            responseBody: String(data: data.prefix(2000), encoding: .utf8),
            duration: 0
        )

        guard httpResponse.statusCode == 200 else {
            throw httpError(httpResponse.statusCode)
        }

        return try Self.parseSpendResponse(data)
    }

    static func parseSpendResponse(_ data: Data) throws -> SpendResponse {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ConsoleBillingError.invalidResponse
        }

        let currentSpend = (json["current_spend"] as? Double)
            ?? (json["total_spend"] as? Double)
            ?? (json["spend"] as? Double)
            ?? 0

        let hardLimit = json["hard_limit"] as? Double
        let softLimit = json["soft_limit"] as? Double

        return SpendResponse(
            currentSpend: currentSpend,
            hardLimit: hardLimit,
            softLimit: softLimit
        )
    }

    // MARK: - Prepaid Credits

    private func fetchPrepaidCredits(sessionKey: String, orgId: String) async throws -> Double {
        guard let url = URL(string: "https://console.anthropic.com/api/organizations/\(orgId)/prepaid/credits") else {
            return 0
        }

        do {
            let (data, httpResponse) = try await performRequest(url: url, sessionKey: sessionKey)

            await NetworkLogService.shared.record(
                method: "GET", url: url.absoluteString,
                statusCode: httpResponse.statusCode,
                responseBody: String(data: data.prefix(2000), encoding: .utf8),
                duration: 0
            )

            guard httpResponse.statusCode == 200 else {
                // Credits endpoint may 404 if org has no prepaid credits — not an error
                if httpResponse.statusCode == 404 { return 0 }
                throw httpError(httpResponse.statusCode)
            }

            return try Self.parseCreditsResponse(data)
        } catch let error as ConsoleBillingError {
            throw error
        } catch {
            // If credits endpoint fails, return 0 rather than failing the whole request
            logger.warning("Failed to fetch prepaid credits: \(error.localizedDescription)")
            return 0
        }
    }

    static func parseCreditsResponse(_ data: Data) throws -> Double {
        guard let json = try? JSONSerialization.jsonObject(with: data) else {
            throw ConsoleBillingError.invalidResponse
        }

        // Response may be {"total": 100.0} or {"balance": 50.0} or {"data": [...]}
        if let dict = json as? [String: Any] {
            if let total = dict["total"] as? Double { return total }
            if let balance = dict["balance"] as? Double { return balance }
            if let remaining = dict["remaining_credits"] as? Double { return remaining }
            // Sum up individual credit entries if present
            if let credits = dict["data"] as? [[String: Any]] {
                return credits.compactMap { $0["remaining_amount"] as? Double ?? $0["amount"] as? Double }.reduce(0, +)
            }
        }

        if let array = json as? [[String: Any]] {
            return array.compactMap { $0["remaining_amount"] as? Double ?? $0["amount"] as? Double }.reduce(0, +)
        }

        return 0
    }

    // MARK: - Usage Cost by API Key

    private func fetchUsageCost(sessionKey: String, orgId: String) async throws -> [ConsoleBilling.APIKeyUsage] {
        // Get usage for the current calendar month
        let calendar = Calendar.current
        let now = Date()
        let startOfMonth = calendar.dateInterval(of: .month, for: now)?.start ?? now
        let startOfNextMonth = calendar.date(byAdding: .month, value: 1, to: startOfMonth) ?? now

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let startStr = dateFormatter.string(from: startOfMonth)
        let endStr = dateFormatter.string(from: startOfNextMonth)

        let urlStr = "https://console.anthropic.com/api/organizations/\(orgId)/workspaces/default/usage_cost?starting_on=\(startStr)&ending_before=\(endStr)&group_by=api_key_id"
        guard let url = URL(string: urlStr) else { return [] }

        do {
            let (data, httpResponse) = try await performRequest(url: url, sessionKey: sessionKey)

            await NetworkLogService.shared.record(
                method: "GET", url: url.absoluteString,
                statusCode: httpResponse.statusCode,
                responseBody: String(data: data.prefix(2000), encoding: .utf8),
                duration: 0
            )

            guard httpResponse.statusCode == 200 else {
                if httpResponse.statusCode == 404 { return [] }
                throw httpError(httpResponse.statusCode)
            }

            return try Self.parseUsageCostResponse(data)
        } catch let error as ConsoleBillingError {
            throw error
        } catch {
            logger.warning("Failed to fetch usage cost: \(error.localizedDescription)")
            return []
        }
    }

    static func parseUsageCostResponse(_ data: Data) throws -> [ConsoleBilling.APIKeyUsage] {
        guard let json = try? JSONSerialization.jsonObject(with: data) else {
            throw ConsoleBillingError.invalidResponse
        }

        var entries: [[String: Any]] = []

        if let dict = json as? [String: Any] {
            if let data = dict["data"] as? [[String: Any]] {
                entries = data
            } else if let usage = dict["usage"] as? [[String: Any]] {
                entries = usage
            }
        } else if let array = json as? [[String: Any]] {
            entries = array
        }

        // Aggregate costs by API key
        var costByKey: [String: (name: String?, cost: Double)] = [:]

        for entry in entries {
            guard let keyId = entry["api_key_id"] as? String else { continue }
            let cost = entry["cost"] as? Double
                ?? entry["total_cost"] as? Double
                ?? entry["usage_cost"] as? Double
                ?? 0
            let name = entry["api_key_name"] as? String

            if var existing = costByKey[keyId] {
                existing.cost += cost
                if existing.name == nil { existing.name = name }
                costByKey[keyId] = existing
            } else {
                costByKey[keyId] = (name: name, cost: cost)
            }
        }

        return costByKey.map { key, value in
            ConsoleBilling.APIKeyUsage(
                apiKeyId: key,
                apiKeyName: value.name,
                cost: value.cost
            )
        }
        .sorted { $0.cost > $1.cost }
    }

    // MARK: - HTTP Helpers

    private func performRequest(url: URL, sessionKey: String) async throws -> (Data, HTTPURLResponse) {
        var request = URLRequest(url: url)
        request.timeoutInterval = 30
        request.setValue("sessionKey=\(sessionKey)", forHTTPHeaderField: "Cookie")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
        request.setValue("Claudit/\(appVersion)", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw ConsoleBillingError.invalidResponse
        }

        return (data, httpResponse)
    }

    private func httpError(_ statusCode: Int) -> ConsoleBillingError {
        if statusCode == 401 || statusCode == 403 {
            return .sessionExpired
        }
        return .httpError(statusCode)
    }
}
