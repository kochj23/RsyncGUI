//
//  LLMLoadBalancerService.swift
//  RsyncGUI
//
//  The shared multi-model LLM load balancer, wired into RsyncGUI. Mirrors the
//  balanced-dispatch design from AIStudio's LLMBackendManager: it composes the
//  enabled model pool from three independent toggles, health-gates it, and spreads
//  work across the healthy models via the pure `LoadBalancer`.
//
//  HARD INVARIANT — Nova is NEVER required. The feature works with zero Nova:
//    • local models (Ollama discovered via /api/tags, MLX from the HF hub cache)
//    • frontier models (OpenRouter, bring-your-own-key)
//  The Nova Gateway (OpenAI-compatible, 127.0.0.1:18792, health at /v1/models) is
//  one OPTIONAL backend. A failed health check simply marks it unavailable; every
//  other backend keeps working. There is no hard dependency on Nova / PG / gateway.
//
//  Author: Jordan Koch
//

import Foundation
import Combine

@MainActor
final class LLMLoadBalancerService: ObservableObject {
    static let shared = LLMLoadBalancerService()

    // MARK: - Toggles (persisted)

    /// Include all discovered local models (Ollama + MLX) in the balanced pool.
    @Published var useAllLocalModels: Bool {
        didSet { UserDefaults.standard.set(useAllLocalModels, forKey: Keys.useAllLocalModels) }
    }
    /// Include all frontier (OpenRouter) models in the balanced pool.
    @Published var enableAllFrontierModels: Bool {
        didSet { UserDefaults.standard.set(enableAllFrontierModels, forKey: Keys.enableAllFrontierModels) }
    }
    /// Include the optional Nova Gateway backend in the balanced pool.
    @Published var useNovaGateway: Bool {
        didSet { UserDefaults.standard.set(useNovaGateway, forKey: Keys.useNovaGateway) }
    }

    // MARK: - Endpoints (persisted)

    @Published var ollamaURL: String {
        didSet { UserDefaults.standard.set(ollamaURL, forKey: Keys.ollamaURL) }
    }
    @Published var novaGatewayURL: String {
        didSet { UserDefaults.standard.set(novaGatewayURL, forKey: Keys.novaGatewayURL) }
    }

    // MARK: - Discovered state

    /// Models currently discovered across the enabled sources.
    @Published var discoveredModels: [DiscoveredModel] = []
    /// Per-backend connection status (for the settings UI).
    @Published var backendStatus: [LLMBackendType: BackendStatus] = [:]
    @Published var isRefreshing = false

    @Published var openRouterModels: [String] = OpenRouterProvider.fallbackModels

    /// Pure, network-free balancer that spreads work across the enabled pool.
    let balancer = LoadBalancer()
    /// Least-busy mirrors how Nova's gateway spreads load.
    var balancerPolicy: BalancerPolicy = .leastBusy

    /// Keychain-backed store for the OpenRouter API key.
    let openRouterKeychain = KeychainStore()

    /// Ordered preference chain for automatic failover (local-first, then frontier,
    /// then the optional gateway).
    let failoverChain: [LLMBackendType] = [.ollama, .mlx, .openRouter, .novaGateway]

    private let session: URLSession

    private enum Keys {
        static let useAllLocalModels = "LLMBalancer_useAllLocalModels"
        static let enableAllFrontierModels = "LLMBalancer_enableAllFrontierModels"
        static let useNovaGateway = "LLMBalancer_useNovaGateway"
        static let ollamaURL = "LLMBalancer_ollamaURL"
        static let novaGatewayURL = "LLMBalancer_novaGatewayURL"
    }

    init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        self.session = URLSession(configuration: config)

        let defaults = UserDefaults.standard
        self.useAllLocalModels = defaults.object(forKey: Keys.useAllLocalModels) as? Bool ?? false
        self.enableAllFrontierModels = defaults.object(forKey: Keys.enableAllFrontierModels) as? Bool ?? false
        self.useNovaGateway = defaults.object(forKey: Keys.useNovaGateway) as? Bool ?? false
        self.ollamaURL = defaults.string(forKey: Keys.ollamaURL) ?? ModelRegistry.ollamaBaseURL
        self.novaGatewayURL = defaults.string(forKey: Keys.novaGatewayURL) ?? ModelRegistry.novaGatewayDefaultURL
    }

    // MARK: - OpenRouter API key (Keychain-backed)

    func setOpenRouterAPIKey(_ key: String) {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            openRouterKeychain.delete()
        } else {
            openRouterKeychain.set(trimmed)
        }
    }

    func openRouterAPIKey() -> String? { openRouterKeychain.get() }
    var hasOpenRouterKey: Bool { openRouterKeychain.hasValue }

    /// True when at least one balancing toggle is on. The natural-language rsync
    /// feature uses this (plus a live pool) to decide whether it is usable.
    var isBalancingEnabled: Bool {
        useAllLocalModels || enableAllFrontierModels || useNovaGateway
    }

    // MARK: - Availability probes (resilient — never throw)

    func checkAvailability(_ type: LLMBackendType) async -> Bool {
        switch type {
        case .ollama: return await checkOllama()
        case .mlx: return checkMLX()
        case .openRouter: return await checkOpenRouter()
        case .novaGateway: return await checkNovaGateway()
        default: return false
        }
    }

    /// Refresh the status of every backend that a toggle could enable. Used by the
    /// settings UI; each probe is independent so one failure never blocks the rest.
    func refreshAllBackends() async {
        isRefreshing = true
        defer { isRefreshing = false }
        for backend in failoverChain {
            backendStatus[backend] = .checking
            let ok = await checkAvailability(backend)
            backendStatus[backend] = ok ? .connected : .disconnected
        }
        _ = await discoverEnabledPool()
    }

    private func checkOllama() async -> Bool {
        guard let url = URL(string: "\(ollamaURL)/api/tags") else { return false }
        do {
            let (_, response) = try await session.data(from: url)
            return (response as? HTTPURLResponse)?.statusCode == 200
        } catch { return false }
    }

    private func checkMLX() -> Bool {
        // MLX runs in-process from the local Hugging Face hub cache; "available"
        // simply means at least one MLX model is present. No network, never throws.
        !ModelRegistry.discoverMLX().isEmpty
    }

    private func checkOpenRouter() async -> Bool {
        guard let key = openRouterAPIKey(), !key.isEmpty,
              let url = URL(string: OpenRouterProvider.modelsURL) else { return false }
        var request = URLRequest(url: url)
        for (header, value) in OpenRouterProvider.authHeaders(apiKey: key) {
            request.setValue(value, forHTTPHeaderField: header)
        }
        do {
            let (data, response) = try await session.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { return false }
            let models = OpenRouterProvider.parseModels(data)
            if !models.isEmpty { openRouterModels = models }
            return true
        } catch { return false }
    }

    private func checkNovaGateway() async -> Bool {
        // OPTIONAL backend. Probe the OpenAI-compatible models listing; any failure
        // just marks it unavailable and the rest of the pool keeps working.
        let candidates = ["\(novaGatewayURL)/v1/models", "\(novaGatewayURL)/"].compactMap { URL(string: $0) }
        for url in candidates {
            do {
                let (_, response) = try await session.data(from: url)
                if (response as? HTTPURLResponse)?.statusCode == 200 { return true }
            } catch { continue }
        }
        return false
    }

    // MARK: - Pool composition

    /// Discover the enabled balancer pool honoring the three toggles. Resilient:
    /// any unreachable source contributes zero models.
    @discardableResult
    func discoverEnabledPool() async -> [DiscoveredModel] {
        var ollama: [DiscoveredModel] = []
        var mlx: [DiscoveredModel] = []
        var frontier: [DiscoveredModel] = []

        if useAllLocalModels {
            ollama = await ModelRegistry.discoverOllama(baseURL: ollamaURL, session: session)
            mlx = ModelRegistry.discoverMLX()
        }
        if enableAllFrontierModels {
            frontier = ModelRegistry.frontierModels(from: openRouterModels)
        }
        let nova = useNovaGateway ? ModelRegistry.novaGatewayModel(url: novaGatewayURL) : nil

        let pool = ModelRegistry.assemblePool(
            ollama: ollama, mlx: mlx, frontier: frontier, novaGateway: nova,
            useAllLocalModels: useAllLocalModels,
            enableAllFrontierModels: enableAllFrontierModels,
            useNovaGateway: useNovaGateway
        )
        discoveredModels = pool
        return pool
    }

    /// Build a `[modelId: Bool]` health map by probing each distinct backend once.
    private func healthMap(for pool: [DiscoveredModel]) async -> [String: Bool] {
        var backendHealth: [LLMBackendType: Bool] = [:]
        for backend in Set(pool.map { $0.backend }) {
            backendHealth[backend] = await checkAvailability(backend)
        }
        var map: [String: Bool] = [:]
        for model in pool { map[model.id] = backendHealth[model.backend] ?? false }
        return map
    }

    // MARK: - Balanced generation

    /// Balanced, health-gated text generation. Selects a model via the
    /// `LoadBalancer` over the healthy enabled pool, falling through to the next on
    /// failure. Throws `LLMError.noBackendAvailable` when nothing is usable so the
    /// caller (the rsync assistant) can disable itself gracefully.
    func generate(prompt: String, systemPrompt: String? = nil,
                  temperature: Float = 0.2, maxTokens: Int = 512) async throws -> String {
        let pool = await discoverEnabledPool()
        guard !pool.isEmpty else { throw LLMError.noBackendAvailable }

        let health = await healthMap(for: pool)
        var remaining = pool
        var lastError: Error?

        while let choice = balancer.next(pool: remaining, health: health, policy: balancerPolicy) {
            balancer.checkOut(choice.id)
            do {
                let result = try await dispatch(model: choice, prompt: prompt, systemPrompt: systemPrompt,
                                                temperature: temperature, maxTokens: maxTokens)
                balancer.checkIn(choice.id)
                return result
            } catch {
                balancer.checkIn(choice.id)
                lastError = error
                remaining.removeAll { $0.id == choice.id }
                continue
            }
        }
        throw lastError ?? LLMError.noBackendAvailable
    }

    /// Route a balancer-selected model through the appropriate backend
    /// implementation. All OpenAI-compatible backends ride the generic path.
    private func dispatch(model: DiscoveredModel, prompt: String, systemPrompt: String?,
                          temperature: Float, maxTokens: Int) async throws -> String {
        switch model.backend {
        case .ollama:
            return try await generateWithOllama(model: model.modelName, prompt: prompt,
                                                systemPrompt: systemPrompt, temperature: temperature, maxTokens: maxTokens)
        case .mlx:
            return try await generateWithMLX(prompt: prompt, systemPrompt: systemPrompt, maxTokens: maxTokens)
        case .openRouter:
            guard let key = openRouterAPIKey(), !key.isEmpty else { throw LLMError.noBackendAvailable }
            return try await generateOpenAICompatible(endpoint: model.endpoint, model: model.modelName,
                                                      headers: OpenRouterProvider.authHeaders(apiKey: key),
                                                      prompt: prompt, systemPrompt: systemPrompt,
                                                      temperature: temperature, maxTokens: maxTokens)
        case .novaGateway:
            return try await generateOpenAICompatible(endpoint: model.endpoint, model: model.modelName,
                                                      headers: [:], prompt: prompt, systemPrompt: systemPrompt,
                                                      temperature: temperature, maxTokens: maxTokens)
        default:
            throw LLMError.noBackendAvailable
        }
    }

    // MARK: - Backend implementations

    private func generateWithOllama(model: String, prompt: String, systemPrompt: String?,
                                    temperature: Float, maxTokens: Int) async throws -> String {
        guard let url = URL(string: "\(ollamaURL)/api/chat") else { throw LLMError.invalidURL }
        let messages = OpenAICompatibleRequest.chatMessages(prompt: prompt, systemPrompt: systemPrompt, history: [])
        let body: [String: Any] = [
            "model": model, "messages": messages, "stream": false,
            "options": ["temperature": temperature, "num_predict": maxTokens]
        ]
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.timeoutInterval = 120

        let (data, response) = try await session.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw LLMError.httpError((response as? HTTPURLResponse)?.statusCode ?? 0)
        }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let message = json["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw LLMError.noResponse
        }
        return content
    }

    private func generateOpenAICompatible(endpoint: String, model: String, headers: [String: String],
                                          prompt: String, systemPrompt: String?,
                                          temperature: Float, maxTokens: Int) async throws -> String {
        let messages = OpenAICompatibleRequest.chatMessages(prompt: prompt, systemPrompt: systemPrompt, history: [])
        var request = try OpenAICompatibleRequest.build(
            endpoint: endpoint, model: model, messages: messages,
            temperature: temperature, maxTokens: maxTokens, stream: false, headers: headers)
        request.timeoutInterval = 120

        let (data, response) = try await session.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw LLMError.httpError((response as? HTTPURLResponse)?.statusCode ?? 0)
        }
        struct OpenAIResponse: Codable {
            struct Choice: Codable { struct Message: Codable { let content: String }; let message: Message }
            let choices: [Choice]
        }
        let decoded = try JSONDecoder().decode(OpenAIResponse.self, from: data)
        return decoded.choices.first?.message.content ?? ""
    }

    private func generateWithMLX(prompt: String, systemPrompt: String?, maxTokens: Int) async throws -> String {
        let mlxPath = "/opt/homebrew/bin/mlx_lm.generate"
        guard FileManager.default.isExecutableFile(atPath: mlxPath) else { throw LLMError.mlxNotAvailable }

        var fullPrompt = prompt
        if let system = systemPrompt, !system.isEmpty { fullPrompt = "\(system)\n\n\(prompt)" }

        // Write the prompt to a temp file (never interpolate user text into args in a shell).
        let promptFile = FileManager.default.temporaryDirectory
            .appendingPathComponent("rsyncgui_mlx_\(UUID().uuidString).txt")
        try fullPrompt.write(to: promptFile, atomically: true, encoding: .utf8)

        return try await withCheckedThrowingContinuation { continuation in
            defer { try? FileManager.default.removeItem(at: promptFile) }
            let process = Process()
            process.executableURL = URL(fileURLWithPath: mlxPath)
            process.arguments = ["--model", "mlx-community/Llama-3.2-3B-Instruct-4bit",
                                 "--prompt", fullPrompt, "--max-tokens", "\(maxTokens)"]
            let outputPipe = Pipe()
            process.standardOutput = outputPipe
            process.standardError = Pipe()
            do {
                try process.run()
                process.waitUntilExit()
                guard process.terminationStatus == 0 else {
                    continuation.resume(throwing: LLMError.mlxNotAvailable); return
                }
                let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
                guard let output = String(data: data, encoding: .utf8), !output.isEmpty else {
                    continuation.resume(throwing: LLMError.noResponse); return
                }
                continuation.resume(returning: output.trimmingCharacters(in: .whitespacesAndNewlines))
            } catch {
                continuation.resume(throwing: LLMError.mlxNotAvailable)
            }
        }
    }
}
