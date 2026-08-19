//
//  LLMSupportTypes.swift
//  RsyncGUI
//
//  Supporting value types for the multi-model LLM load balancer.
//  These mirror the small AIStudio types that the verbatim-shared services
//  (ModelRegistry / OpenRouterProvider / KeychainStore / LLMBackendType) depend
//  on, so the pure/network-free pieces port over unchanged.
//
//  Author: Jordan Koch
//

import Foundation

// MARK: - Backend connection status

/// Connection status for a single LLM backend.
enum BackendStatus: Sendable, Equatable {
    case connected
    case disconnected
    case checking
    case error(String)

    var displayText: String {
        switch self {
        case .connected: return "Connected"
        case .disconnected: return "Disconnected"
        case .checking: return "Checking..."
        case .error(let msg): return "Error: \(msg)"
        }
    }

    var isConnected: Bool {
        if case .connected = self { return true }
        return false
    }
}

// MARK: - Chat message shape

/// Role in a chat conversation (OpenAI-compatible roles).
enum ChatRole: String, Codable, Sendable {
    case system
    case user
    case assistant
}

/// A single chat message passed to the OpenAI-compatible request builders.
struct ChatMessage: Identifiable, Codable, Sendable {
    let id: UUID
    let role: ChatRole
    var content: String
    let timestamp: Date

    init(role: ChatRole, content: String) {
        self.id = UUID()
        self.role = role
        self.content = content
        self.timestamp = Date()
    }
}

// MARK: - LLM errors

/// Errors surfaced by the load-balanced LLM path. `noBackendAvailable` is the
/// signal the natural-language rsync feature uses to disable itself gracefully.
enum LLMError: LocalizedError, Sendable {
    case noBackendAvailable
    case invalidURL
    case invalidResponse
    case httpError(Int)
    case noResponse
    case mlxNotAvailable

    var errorDescription: String? {
        switch self {
        case .noBackendAvailable:
            return "No LLM backend is available. Start Ollama, add an OpenRouter key, or enable the Nova Gateway."
        case .invalidURL:
            return "Invalid backend URL configuration."
        case .invalidResponse:
            return "Received an invalid response from the LLM backend."
        case .httpError(let code):
            return "HTTP error \(code) from the LLM backend."
        case .noResponse:
            return "No response received from the LLM backend."
        case .mlxNotAvailable:
            return "MLX not available. Install with: pip install mlx-lm"
        }
    }
}
