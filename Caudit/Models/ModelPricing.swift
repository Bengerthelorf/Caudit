import Foundation

struct ModelPricing: Sendable {
    let inputPrice: Double
    let outputPrice: Double
    let cacheReadPrice: Double
    let cacheCreationPrice: Double

    init(inputPrice: Double, outputPrice: Double, cacheReadPrice: Double? = nil, cacheCreationPrice: Double? = nil) {
        self.inputPrice = inputPrice
        self.outputPrice = outputPrice
        self.cacheReadPrice = cacheReadPrice ?? (inputPrice * 0.10)
        self.cacheCreationPrice = cacheCreationPrice ?? (inputPrice * 1.25)
    }

    func cost(input: Int, output: Int, cacheRead: Int, cacheCreation: Int) -> Double {
        let inputCost = Double(input) * inputPrice / 1_000_000
        let outputCost = Double(output) * outputPrice / 1_000_000
        let cacheReadCost = Double(cacheRead) * cacheReadPrice / 1_000_000
        let cacheCreationCost = Double(cacheCreation) * cacheCreationPrice / 1_000_000
        return inputCost + outputCost + cacheReadCost + cacheCreationCost
    }
}

final class PricingTable: @unchecked Sendable {
    static let shared = PricingTable()

    private var models: [String: ModelPricing]
    private let fallback = ModelPricing(inputPrice: 3.00, outputPrice: 15.00)
    private var lastFetched: Date?
    private let lock = NSLock()

    private init() {
        self.models = Self.builtinPricing
        Task.detached { [weak self] in
            await self?.fetchRemotePricing()
        }
    }

    func pricing(for model: String) -> ModelPricing {
        lock.lock()
        defer { lock.unlock() }

        if let p = models[model] { return p }

        // Prefer longest prefix match to avoid e.g. "opus-4" matching "opus-4-6"
        var bestMatch: (key: String, pricing: ModelPricing)?
        for (key, p) in models where model.hasPrefix(key) {
            if bestMatch == nil || key.count > bestMatch!.key.count {
                bestMatch = (key, p)
            }
        }
        if let match = bestMatch { return match.pricing }

        var containsMatch: (key: String, pricing: ModelPricing)?
        for (key, p) in models where model.contains(key) {
            if containsMatch == nil || key.count > containsMatch!.key.count {
                containsMatch = (key, p)
            }
        }
        if let match = containsMatch { return match.pricing }

        return fallback
    }

    func refreshIfNeeded() {
        let now = Date()
        if let last = lastFetched, now.timeIntervalSince(last) < 3600 { return }
        Task.detached { [weak self] in
            await self?.fetchRemotePricing()
        }
    }

    private func updateModels(_ newPricing: [String: ModelPricing]) {
        lock.lock()
        self.models = newPricing
        self.lastFetched = Date()
        lock.unlock()
    }

    private func fetchRemotePricing() async {
        let url = URL(string: "https://raw.githubusercontent.com/BerriAI/litellm/main/model_prices_and_context_window.json")!
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }

            var newPricing: [String: ModelPricing] = [:]

            for (key, value) in json {
                guard key.contains("claude") || key.contains("gemini"),
                      let info = value as? [String: Any] else { continue }
                guard let inputCPT = info["input_cost_per_token"] as? Double,
                      let outputCPT = info["output_cost_per_token"] as? Double else { continue }

                let cacheReadCPT = info["cache_read_input_token_cost"] as? Double
                let cacheCreationCPT = info["cache_creation_input_token_cost"] as? Double

                let pricing = ModelPricing(
                    inputPrice: inputCPT * 1_000_000,
                    outputPrice: outputCPT * 1_000_000,
                    cacheReadPrice: cacheReadCPT.map { $0 * 1_000_000 },
                    cacheCreationPrice: cacheCreationCPT.map { $0 * 1_000_000 }
                )

                let modelId = key.components(separatedBy: "/").last ?? key
                newPricing[modelId] = pricing
            }

            if !newPricing.isEmpty {
                for (k, v) in Self.builtinPricing where newPricing[k] == nil {
                    newPricing[k] = v
                }
                updateModels(newPricing)
            }
        } catch {
        }
    }

    private static let builtinPricing: [String: ModelPricing] = [
        "claude-opus-4-6": ModelPricing(inputPrice: 5.50, outputPrice: 27.50),
        "claude-sonnet-4-5": ModelPricing(inputPrice: 3.30, outputPrice: 16.50),
        "claude-sonnet-4": ModelPricing(inputPrice: 3.00, outputPrice: 15.00),
        "claude-opus-4": ModelPricing(inputPrice: 5.00, outputPrice: 25.00),
        "claude-3-5-sonnet": ModelPricing(inputPrice: 3.00, outputPrice: 15.00),
        "claude-3-5-haiku": ModelPricing(inputPrice: 0.80, outputPrice: 4.00),
        "claude-3-opus": ModelPricing(inputPrice: 15.00, outputPrice: 75.00),
        "claude-3-sonnet": ModelPricing(inputPrice: 3.00, outputPrice: 15.00),
        "claude-3-haiku": ModelPricing(inputPrice: 0.25, outputPrice: 1.25),
        "claude-haiku-4-5": ModelPricing(inputPrice: 1.10, outputPrice: 5.50),
        "gemini-2.5-pro": ModelPricing(inputPrice: 1.25, outputPrice: 10.00),
        "gemini-2.5-flash": ModelPricing(inputPrice: 0.15, outputPrice: 0.60),
    ]
}
