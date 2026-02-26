//
//  AIBackendManager.swift
//  RsyncGUI
//
//  AI Backend Manager with TinyChat/TinyLLM support for intelligent sync operations
//  Author: Jordan Koch
//
//  THIRD-PARTY INTEGRATIONS:
//  - TinyChat by Jason Cox (https://github.com/jasonacox/tinychat)
//    Fast chatbot interface with OpenAI-compatible API
//  - TinyLLM by Jason Cox (https://github.com/jasonacox/TinyLLM)
//    Lightweight LLM server with OpenAI-compatible API
//
//  AI FEATURES FOR RSYNCGUI:
//  - Smart sync scheduling based on usage patterns
//  - Anomaly detection for ransomware protection
//  - Intelligent exclusion pattern suggestions
//  - Predictive sync time/size estimates
//  - Duplicate file detection assistance
//

import Foundation
import SwiftUI
import Combine

// MARK: - AI Backend Type

enum AIBackend: String, Codable, CaseIterable {
    case ollama = "Ollama"
    case mlx = "MLX Toolkit"
    case tinyLLM = "TinyLLM"
    case tinyChat = "TinyChat"
    case auto = "Auto (Prefer Local)"

    var icon: String {
        switch self {
        case .ollama: return "network"
        case .mlx: return "cpu"
        case .tinyLLM: return "cube"
        case .tinyChat: return "bubble.left.and.bubble.right.fill"
        case .auto: return "sparkles"
        }
    }

    var description: String {
        switch self {
        case .ollama:
            return "Ollama local LLM (localhost:11434)"
        case .mlx:
            return "MLX Toolkit - Apple Silicon optimized"
        case .tinyLLM:
            return "TinyLLM by Jason Cox - Lightweight LLM server"
        case .tinyChat:
            return "TinyChat by Jason Cox - Fast chatbot interface"
        case .auto:
            return "Automatically select best available backend"
        }
    }

    var attribution: String? {
        switch self {
        case .tinyLLM:
            return "TinyLLM by Jason Cox (https://github.com/jasonacox/TinyLLM)"
        case .tinyChat:
            return "TinyChat by Jason Cox (https://github.com/jasonacox/tinychat)"
        default:
            return nil
        }
    }
}

// MARK: - AI Backend Manager

@MainActor
class AIBackendManager: ObservableObject {
    static let shared = AIBackendManager()

    // MARK: - Published Properties

    @Published var selectedBackend: AIBackend = .auto
    @Published var activeBackend: AIBackend? = nil
    @Published var isOllamaAvailable = false
    @Published var isMLXAvailable = false
    @Published var isTinyLLMAvailable = false
    @Published var isTinyChatAvailable = false
    @Published var isProcessing = false
    @Published var lastError: String? = nil
    @Published var aiEnabled = true

    // Backend URLs
    @Published var ollamaURL: String = "http://localhost:11434"
    @Published var tinyLLMServerURL: String = "http://localhost:8000"
    @Published var tinyChatServerURL: String = "http://localhost:8000"
    @Published var pythonPath: String = "/opt/homebrew/bin/python3"

    // Ollama model selection
    @Published var ollamaModels: [String] = []
    @Published var selectedOllamaModel: String = "llama3.2"

    private let userDefaults = UserDefaults.standard

    private enum Keys {
        static let selectedBackend = "AIBackendManager_SelectedBackend"
        static let ollamaModel = "AIBackendManager_OllamaModel"
        static let tinyLLMServerURL = "AIBackendManager_TinyLLMServerURL"
        static let tinyChatServerURL = "AIBackendManager_TinyChatServerURL"
        static let pythonPath = "AIBackendManager_PythonPath"
        static let aiEnabled = "AIBackendManager_AIEnabled"
    }

    // MARK: - Initialization

    private init() {
        loadSettings()
        Task {
            await checkBackendAvailability()
        }
    }

    private func loadSettings() {
        if let backendRaw = userDefaults.string(forKey: Keys.selectedBackend),
           let backend = AIBackend(rawValue: backendRaw) {
            selectedBackend = backend
        }
        selectedOllamaModel = userDefaults.string(forKey: Keys.ollamaModel) ?? "llama3.2"
        tinyLLMServerURL = userDefaults.string(forKey: Keys.tinyLLMServerURL) ?? "http://localhost:8000"
        tinyChatServerURL = userDefaults.string(forKey: Keys.tinyChatServerURL) ?? "http://localhost:8000"
        pythonPath = userDefaults.string(forKey: Keys.pythonPath) ?? "/opt/homebrew/bin/python3"
        aiEnabled = userDefaults.bool(forKey: Keys.aiEnabled)
    }

    func saveSettings() {
        userDefaults.set(selectedBackend.rawValue, forKey: Keys.selectedBackend)
        userDefaults.set(selectedOllamaModel, forKey: Keys.ollamaModel)
        userDefaults.set(tinyLLMServerURL, forKey: Keys.tinyLLMServerURL)
        userDefaults.set(tinyChatServerURL, forKey: Keys.tinyChatServerURL)
        userDefaults.set(pythonPath, forKey: Keys.pythonPath)
        userDefaults.set(aiEnabled, forKey: Keys.aiEnabled)
    }

    // MARK: - Backend Availability

    func checkBackendAvailability() async {
        async let ollamaCheck = checkOllamaAvailability()
        async let mlxCheck = checkMLXAvailability()
        async let tinyLLMCheck = checkTinyLLMAvailability()
        async let tinyChatCheck = checkTinyChatAvailability()

        let (ollama, mlx, tinyLLM, tinyChat) = await (ollamaCheck, mlxCheck, tinyLLMCheck, tinyChatCheck)

        isOllamaAvailable = ollama
        isMLXAvailable = mlx
        isTinyLLMAvailable = tinyLLM
        isTinyChatAvailable = tinyChat

        determineActiveBackend()
    }

    private func determineActiveBackend() {
        switch selectedBackend {
        case .ollama:
            activeBackend = isOllamaAvailable ? .ollama : nil
        case .mlx:
            activeBackend = isMLXAvailable ? .mlx : nil
        case .tinyLLM:
            activeBackend = isTinyLLMAvailable ? .tinyLLM : nil
        case .tinyChat:
            activeBackend = isTinyChatAvailable ? .tinyChat : nil
        case .auto:
            if isOllamaAvailable {
                activeBackend = .ollama
            } else if isTinyChatAvailable {
                activeBackend = .tinyChat
            } else if isTinyLLMAvailable {
                activeBackend = .tinyLLM
            } else if isMLXAvailable {
                activeBackend = .mlx
            } else {
                activeBackend = nil
            }
        }
    }

    private func checkOllamaAvailability() async -> Bool {
        guard let url = URL(string: "\(ollamaURL)/api/tags") else { return false }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let models = json["models"] as? [[String: Any]] {
                let modelNames = models.compactMap { $0["name"] as? String }
                await MainActor.run { self.ollamaModels = modelNames }
            }
            return true
        } catch {
            return false
        }
    }

    // TinyLLM by Jason Cox: https://github.com/jasonacox/TinyLLM
    private func checkTinyLLMAvailability() async -> Bool {
        guard let url = URL(string: "\(tinyLLMServerURL)/") else { return false }
        do {
            let (_, response) = try await URLSession.shared.data(from: url)
            return (response as? HTTPURLResponse)?.statusCode == 200
        } catch {
            return false
        }
    }

    // TinyChat by Jason Cox: https://github.com/jasonacox/tinychat
    private func checkTinyChatAvailability() async -> Bool {
        guard let url = URL(string: "\(tinyChatServerURL)/") else { return false }
        do {
            let (_, response) = try await URLSession.shared.data(from: url)
            return (response as? HTTPURLResponse)?.statusCode == 200
        } catch {
            return false
        }
    }

    private func checkMLXAvailability() async -> Bool {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: pythonPath)
        task.arguments = ["-c", "import mlx.core as mx; print('OK')"]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = pipe
        defer {
            pipe.fileHandleForReading.closeFile()
        }
        do {
            try task.run()
            task.waitUntilExit()
            return task.terminationStatus == 0
        } catch { return false }
    }

    // MARK: - Text Generation

    func generate(prompt: String, systemPrompt: String? = nil, temperature: Float = 0.7, maxTokens: Int = 1024) async throws -> String {
        guard aiEnabled, let backend = activeBackend else {
            throw AIBackendError.noBackendAvailable
        }

        isProcessing = true
        defer { isProcessing = false }

        switch backend {
        case .ollama:
            return try await generateWithOllama(prompt: prompt, systemPrompt: systemPrompt, temperature: temperature, maxTokens: maxTokens)
        case .mlx:
            return try await generateWithMLX(prompt: prompt, systemPrompt: systemPrompt, temperature: temperature, maxTokens: maxTokens)
        case .tinyLLM:
            return try await generateWithTinyLLM(prompt: prompt, systemPrompt: systemPrompt, temperature: temperature, maxTokens: maxTokens)
        case .tinyChat:
            return try await generateWithTinyChat(prompt: prompt, systemPrompt: systemPrompt, temperature: temperature, maxTokens: maxTokens)
        case .auto:
            throw AIBackendError.invalidState
        }
    }

    private func generateWithOllama(prompt: String, systemPrompt: String?, temperature: Float, maxTokens: Int) async throws -> String {
        guard let url = URL(string: "\(ollamaURL)/api/generate") else {
            throw AIBackendError.invalidConfiguration
        }

        var requestBody: [String: Any] = [
            "model": selectedOllamaModel,
            "prompt": prompt,
            "stream": false,
            "options": ["temperature": temperature, "num_predict": maxTokens]
        ]
        if let systemPrompt = systemPrompt {
            requestBody["system"] = systemPrompt
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)

        let (data, _) = try await URLSession.shared.data(for: request)

        struct OllamaResponse: Codable { let response: String }
        let response = try JSONDecoder().decode(OllamaResponse.self, from: data)
        return response.response
    }

    private func generateWithMLX(prompt: String, systemPrompt: String?, temperature: Float, maxTokens: Int) async throws -> String {
        var fullPrompt = ""
        if let systemPrompt = systemPrompt { fullPrompt += "System: \(systemPrompt)\n\n" }
        fullPrompt += "User: \(prompt)\n\nAssistant:"

        let script = """
        import mlx_lm
        model, tokenizer = mlx_lm.load("mlx-community/Llama-3.2-1B-Instruct-4bit")
        response = mlx_lm.generate(model, tokenizer, prompt='''\(fullPrompt.replacingOccurrences(of: "'", with: "\\'"))''', max_tokens=\(maxTokens), temp=\(temperature), verbose=False)
        print(response)
        """

        let tempFile = FileManager.default.temporaryDirectory.appendingPathComponent("mlx_\(UUID().uuidString).py")
        try script.write(to: tempFile, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: tempFile) }

        let task = Process()
        task.executableURL = URL(fileURLWithPath: pythonPath)
        task.arguments = [tempFile.path]
        let outputPipe = Pipe()
        task.standardOutput = outputPipe
        defer {
            outputPipe.fileHandleForReading.closeFile()
        }
        try task.run()
        task.waitUntilExit()

        let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: outputData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    // TinyLLM by Jason Cox: https://github.com/jasonacox/TinyLLM
    private func generateWithTinyLLM(prompt: String, systemPrompt: String?, temperature: Float, maxTokens: Int) async throws -> String {
        guard let url = URL(string: "\(tinyLLMServerURL)/v1/chat/completions") else {
            throw AIBackendError.invalidConfiguration
        }

        var messages: [[String: String]] = []
        if let systemPrompt = systemPrompt {
            messages.append(["role": "system", "content": systemPrompt])
        }
        messages.append(["role": "user", "content": prompt])

        let requestBody: [String: Any] = [
            "messages": messages,
            "max_tokens": maxTokens,
            "temperature": temperature,
            "stream": false
        ]

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)

        let (data, _) = try await URLSession.shared.data(for: request)

        struct Response: Codable {
            struct Choice: Codable {
                struct Message: Codable { let content: String }
                let message: Message
            }
            let choices: [Choice]
        }
        let response = try JSONDecoder().decode(Response.self, from: data)
        return response.choices.first?.message.content ?? ""
    }

    // TinyChat by Jason Cox: https://github.com/jasonacox/tinychat
    private func generateWithTinyChat(prompt: String, systemPrompt: String?, temperature: Float, maxTokens: Int) async throws -> String {
        guard let url = URL(string: "\(tinyChatServerURL)/v1/chat/completions") else {
            throw AIBackendError.invalidConfiguration
        }

        var messages: [[String: String]] = []
        if let systemPrompt = systemPrompt {
            messages.append(["role": "system", "content": systemPrompt])
        }
        messages.append(["role": "user", "content": prompt])

        let requestBody: [String: Any] = [
            "messages": messages,
            "max_tokens": maxTokens,
            "temperature": temperature,
            "stream": false
        ]

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)

        let (data, _) = try await URLSession.shared.data(for: request)

        struct Response: Codable {
            struct Choice: Codable {
                struct Message: Codable { let content: String }
                let message: Message
            }
            let choices: [Choice]
        }
        let response = try JSONDecoder().decode(Response.self, from: data)
        return response.choices.first?.message.content ?? ""
    }

    // MARK: - RsyncGUI-Specific AI Features

    /// Analyze files for anomalies before sync (ransomware protection)
    func analyzeForAnomalies(files: [String], previousState: [String: Date]?) async -> String? {
        guard aiEnabled, activeBackend != nil else { return nil }

        let prompt = """
        Analyze these file changes for potential anomalies or ransomware indicators:

        Files changed: \(files.prefix(50).joined(separator: "\n"))

        Look for:
        1. Mass file extension changes (e.g., .encrypted, .locked)
        2. Unusual file naming patterns
        3. Large numbers of files changed simultaneously
        4. Suspicious file extensions

        Respond with a brief assessment: SAFE, WARNING, or DANGER with explanation.
        """

        return try? await generate(prompt: prompt, systemPrompt: "You are a security analyst detecting ransomware patterns in file changes. Be concise.")
    }

    /// Suggest exclusion patterns based on file analysis
    func suggestExclusionPatterns(sourceFiles: [String], existingExclusions: [String]) async -> [String]? {
        guard aiEnabled, activeBackend != nil else { return nil }

        let prompt = """
        Based on these source files and existing exclusions, suggest additional exclusion patterns:

        Sample files: \(sourceFiles.prefix(30).joined(separator: "\n"))
        Current exclusions: \(existingExclusions.joined(separator: ", "))

        Suggest patterns for:
        - Build artifacts
        - Cache directories
        - Temporary files
        - Version control internals
        - IDE settings

        Return only the patterns, one per line.
        """

        if let response = try? await generate(prompt: prompt, systemPrompt: "You are a DevOps expert. Return only file patterns, one per line.") {
            return response.components(separatedBy: "\n").filter { !$0.isEmpty }
        }
        return nil
    }

    /// Estimate sync time based on historical data
    func estimateSyncTime(fileCount: Int, totalSize: Int64, historicalTimes: [TimeInterval]) async -> String? {
        guard aiEnabled, activeBackend != nil else { return nil }

        let prompt = """
        Estimate sync completion time:
        - Files: \(fileCount)
        - Total size: \(ByteCountFormatter.string(fromByteCount: totalSize, countStyle: .file))
        - Historical sync times: \(historicalTimes.map { "\(Int($0))s" }.joined(separator: ", "))

        Provide a brief estimate with confidence level.
        """

        return try? await generate(prompt: prompt, systemPrompt: "You are a performance analyst. Be concise and practical.")
    }
}

// MARK: - Errors

enum AIBackendError: LocalizedError {
    case noBackendAvailable
    case invalidConfiguration
    case invalidState

    var errorDescription: String? {
        switch self {
        case .noBackendAvailable:
            return "No AI backend available. Install Ollama, TinyChat, or TinyLLM."
        case .invalidConfiguration:
            return "AI backend configuration is invalid."
        case .invalidState:
            return "AI backend is in an invalid state."
        }
    }
}

// MARK: - Settings View

struct AISettingsView: View {
    @ObservedObject var manager = AIBackendManager.shared
    @State private var isChecking = false

    var body: some View {
        Form {
            Section("AI Features") {
                Toggle("Enable AI Assistance", isOn: $manager.aiEnabled)
                    .onChange(of: manager.aiEnabled) { _ in manager.saveSettings() }

                Text("AI can help with anomaly detection, smart scheduling, and exclusion suggestions.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Section("Backend Selection") {
                Picker("Backend", selection: $manager.selectedBackend) {
                    ForEach(AIBackend.allCases, id: \.self) { backend in
                        Label(backend.rawValue, systemImage: backend.icon).tag(backend)
                    }
                }
                .onChange(of: manager.selectedBackend) { _ in
                    manager.saveSettings()
                    Task { await manager.checkBackendAvailability() }
                }

                Text(manager.selectedBackend.description)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Section("Backend Status") {
                HStack {
                    Circle()
                        .fill(manager.activeBackend != nil ? .green : .red)
                        .frame(width: 10, height: 10)
                    Text(manager.activeBackend != nil ? "Active: \(manager.activeBackend!.rawValue)" : "No backend available")
                }

                LabeledContent("Ollama", value: manager.isOllamaAvailable ? "Available" : "Unavailable")
                LabeledContent("MLX Toolkit", value: manager.isMLXAvailable ? "Available" : "Unavailable")
                LabeledContent("TinyChat", value: manager.isTinyChatAvailable ? "Available" : "Unavailable")
                LabeledContent("TinyLLM", value: manager.isTinyLLMAvailable ? "Available" : "Unavailable")

                Button("Refresh Status") {
                    isChecking = true
                    Task {
                        await manager.checkBackendAvailability()
                        isChecking = false
                    }
                }
                .disabled(isChecking)
            }

            Section("Attribution") {
                Link("TinyChat by Jason Cox", destination: URL(string: "https://github.com/jasonacox/tinychat")!)
                Link("TinyLLM by Jason Cox", destination: URL(string: "https://github.com/jasonacox/TinyLLM")!)
            }
        }
        .formStyle(.grouped)
    }
}
