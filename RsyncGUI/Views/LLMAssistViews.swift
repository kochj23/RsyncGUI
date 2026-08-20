//
//  LLMAssistViews.swift
//  RsyncGUI
//
//  UI for the multi-model load balancer and the "Describe it in English" rsync
//  assistant. The assistant NEVER executes anything — it only surfaces a validated
//  command for review and pre-fills the builder on explicit user action.
//
//  Author: Jordan Koch
//

import SwiftUI

// MARK: - Assistant view model

@MainActor
final class RsyncAssistViewModel: ObservableObject {
    @Published var intent: String = ""
    @Published var isGenerating = false
    @Published var rawResponse: String?
    @Published var parsed: RsyncCommand?
    @Published var errorMessage: String?
    @Published var rejected = false   // got output, but it failed validation

    private let balancer = LLMLoadBalancerService.shared

    /// Whether the feature is usable right now (a balancing toggle is on). This is
    /// the graceful gate — when false the UI disables itself with a clear reason.
    var isAvailable: Bool { balancer.isBalancingEnabled }

    var unavailableReason: String {
        "No LLM backend is enabled. Turn on Local, Frontier, or Nova Gateway in Settings → AI Assist."
    }

    /// Ask the balanced LLM for a command, then validate it. Fully guarded: a
    /// missing backend or malformed output produces a message, never a crash.
    func generate(sources: [String], destination: String?) async {
        let trimmed = intent.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard isAvailable else { errorMessage = unavailableReason; return }

        isGenerating = true
        rawResponse = nil
        parsed = nil
        errorMessage = nil
        rejected = false
        defer { isGenerating = false }

        let system = RsyncPromptBuilder.systemPrompt()
        let user = RsyncPromptBuilder.userPrompt(intent: trimmed, sources: sources, destination: destination)

        do {
            let response = try await balancer.generate(prompt: user, systemPrompt: system)
            rawResponse = response
            if let command = parseRsyncSuggestion(response) {
                parsed = command
            } else {
                rejected = true
                errorMessage = "The model's reply was not a clean rsync command and was rejected for safety."
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - Embeddable assistant section (used in the Job editor)

struct RsyncAssistSection: View {
    @Binding var job: SyncJob
    @StateObject private var model = RsyncAssistViewModel()
    @State private var applied = false

    var body: some View {
        FormSection(title: "Describe it in English (AI)") {
            VStack(alignment: .leading, spacing: 10) {
                Text("Describe what you want in plain English. The balanced LLM proposes an rsync command for you to review — nothing runs automatically.")
                    .font(.caption)
                    .foregroundColor(.secondary)

                if !model.isAvailable {
                    Label(model.unavailableReason, systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundColor(.orange)
                }

                HStack(alignment: .top, spacing: 8) {
                    TextField("e.g. mirror Photos to the NAS, skip video files, delete extras on the destination",
                              text: $model.intent, axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                        .lineLimit(1...3)
                        .disabled(!model.isAvailable || model.isGenerating)

                    Button {
                        Task {
                            applied = false
                            await model.generate(sources: job.sources, destination: job.destination)
                        }
                    } label: {
                        if model.isGenerating {
                            ProgressView().controlSize(.small)
                        } else {
                            Label("Suggest", systemImage: "sparkles")
                        }
                    }
                    .disabled(!model.isAvailable || model.isGenerating ||
                              model.intent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }

                if let error = model.errorMessage {
                    Label(error, systemImage: "xmark.octagon")
                        .font(.caption)
                        .foregroundColor(.red)
                }

                if let command = model.parsed {
                    reviewCard(command)
                }
            }
        }
    }

    @ViewBuilder
    private func reviewCard(_ command: RsyncCommand) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Suggested command (review before running):")
                .font(.caption).bold()

            Text(command.displayString)
                .font(.system(.body, design: .monospaced))
                .textSelection(.enabled)
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(nsColor: .textBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.3)))

            Label("This is only a suggestion. It will not run until you start the job yourself.",
                  systemImage: "hand.raised")
                .font(.caption2)
                .foregroundColor(.secondary)

            HStack {
                Button {
                    job.options = command.applied(to: job.options)
                    if job.sources.first?.isEmpty ?? true, let firstSource = command.sources.first,
                       firstSource != "SRC" {
                        job.sources = [firstSource]
                    }
                    if job.destination.isEmpty, let dest = command.destination, dest != "DEST" {
                        job.destination = dest
                    }
                    applied = true
                } label: {
                    Label("Apply flags to builder", systemImage: "arrow.down.doc")
                }

                if applied {
                    Label("Applied", systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundColor(.green)
                }
            }
        }
        .padding(.top, 4)
    }
}

// MARK: - Load balancer settings pane

struct LLMSettingsView: View {
    @ObservedObject private var balancer = LLMLoadBalancerService.shared
    @State private var openRouterKeyField: String = ""
    @State private var keySaved = false

    var body: some View {
        Form {
            Section("Multi-Model Load Balancing") {
                Toggle("Use all local models (Ollama + MLX)", isOn: $balancer.useAllLocalModels)
                Toggle("Enable all frontier models (OpenRouter)", isOn: $balancer.enableAllFrontierModels)
                Toggle("Use Nova Gateway (optional)", isOn: $balancer.useNovaGateway)
                Text("Work is spread across every enabled, healthy model using a least-busy policy. Nova is never required — local and frontier work on their own.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Section("Endpoints") {
                LabeledContent("Ollama") {
                    TextField("http://localhost:11434", text: $balancer.ollamaURL)
                        .textFieldStyle(.roundedBorder)
                }
                LabeledContent("Nova Gateway") {
                    TextField(ModelRegistry.novaGatewayDefaultURL, text: $balancer.novaGatewayURL)
                        .textFieldStyle(.roundedBorder)
                }
            }

            Section("OpenRouter API Key (frontier models)") {
                SecureField("sk-or-...", text: $openRouterKeyField)
                    .textFieldStyle(.roundedBorder)
                HStack {
                    Button("Save Key") {
                        balancer.setOpenRouterAPIKey(openRouterKeyField)
                        openRouterKeyField = ""
                        keySaved = true
                    }
                    if balancer.hasOpenRouterKey {
                        Label("Key stored in Keychain", systemImage: "key.fill")
                            .font(.caption).foregroundColor(.green)
                    }
                    if keySaved { Text("Saved").font(.caption).foregroundColor(.secondary) }
                    Spacer()
                    Button("Clear") {
                        balancer.setOpenRouterAPIKey("")
                        keySaved = false
                    }
                    .disabled(!balancer.hasOpenRouterKey)
                }
            }

            Section("Backend Status") {
                ForEach(balancer.failoverChain, id: \.self) { backend in
                    let status = balancer.backendStatus[backend] ?? .disconnected
                    HStack {
                        Circle().fill(status.isConnected ? .green : .gray).frame(width: 9, height: 9)
                        Text(backend.displayName)
                        Spacer()
                        Text(status.displayText).font(.caption).foregroundColor(.secondary)
                    }
                }
                HStack {
                    Button {
                        Task { await balancer.refreshAllBackends() }
                    } label: {
                        if balancer.isRefreshing { ProgressView().controlSize(.small) }
                        else { Text("Refresh Status") }
                    }
                    .disabled(balancer.isRefreshing)
                    Spacer()
                    Text("\(balancer.discoveredModels.count) model(s) in pool")
                        .font(.caption).foregroundColor(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}
