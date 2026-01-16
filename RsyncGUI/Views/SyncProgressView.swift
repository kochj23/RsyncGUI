//
//  ProgressView.swift
//  RsyncGUI
//
//  Created by Jordan Koch on 1/14/26.
//

import SwiftUI

/// Beautiful real-time progress visualization for huge syncs
struct SyncProgressView: View {
    let job: SyncJob
    @StateObject private var executor = RsyncExecutor()
    @Environment(\.dismiss) private var dismiss
    @State private var hasStarted = false
    @State private var hasCompleted = false
    @State private var result: ExecutionResult?

    var body: some View {
        VStack(spacing: 0) {
            // Header
            headerView

            Divider()

            if !hasStarted {
                // Starting view
                startingView
            } else if hasCompleted, let finalResult = result {
                // Completion view
                completionView(result: finalResult)
            } else {
                // Active progress view
                activeProgressView
            }
        }
        .frame(minWidth: 800, idealWidth: 1000, maxWidth: .infinity,
               minHeight: 600, idealHeight: 700, maxHeight: .infinity)
        .task {
            await runSync()
        }
    }

    // MARK: - Header

    private var headerView: some View {
        HStack {
            Image(systemName: "arrow.triangle.2.circlepath.circle.fill")
                .font(.title)
                .foregroundStyle(.blue.gradient)

            VStack(alignment: .leading, spacing: 4) {
                Text(job.name)
                    .font(.headline)

                HStack(spacing: 12) {
                    HStack { Image(systemName: "folder.fill"); Text(job.source) }
                    Image(systemName: "arrow.right")
                    HStack { Image(systemName: "folder.badge.plus"); Text(job.destination) }
                }
                .font(.caption)
                .foregroundColor(.secondary)
            }

            Spacer()

            if !hasCompleted {
                Button("Cancel", role: .cancel) {
                    executor.cancel()
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
            } else {
                Button("Done") {
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding()
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // MARK: - Starting View

    private var startingView: some View {
        VStack(spacing: 24) {
            SwiftUI.ProgressView()
                .scaleEffect(1.5)

            Text("Starting rsync...")
                .font(.title2)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Active Progress

    private var activeProgressView: some View {
        ZStack {
            GlassmorphicBackground()

            ScrollView {
                VStack(spacing: 30) {
                    // Dual progress circles
                    HStack(spacing: 60) {
                        // Overall progress
                        VStack(spacing: 12) {
                            CircularGauge(
                                value: safeOverallPercentage,
                                color: ModernColors.cyan,
                                size: 200,
                                lineWidth: 20,
                                label: "%"
                            )
                            Text("Overall Progress")
                                .font(.headline)
                                .foregroundColor(ModernColors.textSecondary)
                        }

                        // Current file progress
                        VStack(spacing: 12) {
                            CircularGauge(
                                value: safeCurrentFilePercentage,
                                color: ModernColors.orange,
                                size: 200,
                                lineWidth: 20,
                                label: "%"
                            )
                            Text("Current File")
                                .font(.headline)
                                .foregroundColor(ModernColors.textSecondary)
                        }
                    }

                    // Statistics grid
                    statisticsGrid

                    // Current file
                    currentFileSection

                    // Speed and time
                    speedTimeSection
                }
                .padding(40)
            }
        }
    }

    // Safe overall percentage (calculated from files done/total)
    private var safeOverallPercentage: Double {
        let percentage = executor.progress?.overallPercentage ?? 0
        guard percentage.isFinite && !percentage.isNaN else {
            return 0
        }
        return min(max(percentage, 0), 100) // Clamp between 0-100
    }

    // Safe current file percentage
    private var safeCurrentFilePercentage: Double {
        let percentage = executor.progress?.percentage ?? 0
        guard percentage.isFinite && !percentage.isNaN else {
            return 0
        }
        return min(max(percentage, 0), 100) // Clamp between 0-100
    }

    private var statisticsGrid: some View {
        LazyVGrid(columns: [
            GridItem(.flexible()),
            GridItem(.flexible())
        ], spacing: 20) {
            StatCard(
                icon: "doc.fill",
                title: "Files Transferred",
                value: "\(executor.progress?.filesTransferred ?? 0) / \(executor.progress?.totalFiles ?? 0)",
                color: ModernColors.cyan
            )

            StatCard(
                icon: "arrow.down.circle.fill",
                title: "Data Transferred",
                value: executor.progress?.bytesTransferredFormatted ?? "0 B",
                color: ModernColors.accentGreen
            )

            StatCard(
                icon: "gauge.high",
                title: "Transfer Speed",
                value: executor.progress?.speedFormatted ?? "0 B/s",
                color: ModernColors.orange
            )

            StatCard(
                icon: "clock.fill",
                title: "Time Remaining",
                value: executor.progress?.timeRemainingFormatted ?? "—",
                color: ModernColors.purple
            )
        }
    }

    private var currentFileSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "doc.text.fill")
                    .foregroundColor(ModernColors.cyan)
                Text("Current File")
                    .foregroundColor(ModernColors.textPrimary)
            }
            .font(.headline)

            HStack {
                Image(systemName: "arrow.right.circle.fill")
                    .foregroundColor(ModernColors.cyan)

                Text(executor.progress?.currentFile ?? "Preparing...")
                    .font(.system(.body, design: .monospaced))
                    .foregroundColor(ModernColors.textSecondary)
                    .lineLimit(2)
                    .truncationMode(.middle)

                Spacer()
            }
            .padding()
            .glassCard()
        }
    }

    private var speedTimeSection: some View {
        HStack(spacing: 40) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "speedometer")
                        .foregroundColor(ModernColors.cyan)
                    Text("Average Speed")
                        .foregroundColor(ModernColors.textSecondary)
                }
                .font(.caption)

                Text(executor.progress?.speedFormatted ?? "Calculating...")
                    .font(.title3)
                    .fontWeight(.semibold)
                    .foregroundColor(ModernColors.cyan)
            }

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "hourglass")
                        .foregroundColor(ModernColors.purple)
                    Text("Estimated Time")
                        .foregroundColor(ModernColors.textSecondary)
                }
                .font(.caption)

                Text(executor.progress?.timeRemainingFormatted ?? "Calculating...")
                    .font(.title3)
                    .fontWeight(.semibold)
                    .foregroundColor(ModernColors.purple)
            }

            Spacer()
        }
        .padding()
        .glassCard()
    }

    // MARK: - Completion View

    private func completionView(result: ExecutionResult) -> some View {
        ZStack {
            GlassmorphicBackground()

            VStack(spacing: 30) {
                // Success/failure icon
                Image(systemName: result.status == .success ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .font(.system(size: 80))
                    .foregroundColor(result.status == .success ? ModernColors.accentGreen : ModernColors.statusCritical)
                    .shadow(color: result.status == .success ? ModernColors.accentGreen.opacity(0.6) : ModernColors.statusCritical.opacity(0.6), radius: 20)

                VStack(spacing: 12) {
                    Text(result.status == .success ? "Sync Completed Successfully" : "Sync Failed")
                        .modernHeader(size: .large)

                    Text(completionMessage(result: result))
                        .font(.title3)
                        .foregroundColor(ModernColors.textSecondary)
                        .multilineTextAlignment(.center)
                }

                // Final statistics
                LazyVGrid(columns: [
                    GridItem(.flexible()),
                    GridItem(.flexible()),
                    GridItem(.flexible())
                ], spacing: 20) {
                    CompletionStatCard(
                        icon: "doc.fill",
                        title: "Files",
                        value: "\(result.filesTransferred)",
                        color: ModernColors.cyan
                    )

                    CompletionStatCard(
                        icon: "arrow.down.circle.fill",
                        title: "Data",
                        value: ByteCountFormatter.string(fromByteCount: result.bytesTransferred, countStyle: .binary),
                        color: ModernColors.accentGreen
                    )

                    CompletionStatCard(
                        icon: "clock.fill",
                        title: "Duration",
                        value: formatDuration(result.duration),
                        color: ModernColors.purple
                    )
                }
                .padding()

                if !result.errors.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(ModernColors.statusCritical)
                            Text("Errors")
                                .foregroundColor(ModernColors.textPrimary)
                        }
                        .font(.headline)

                        ScrollView {
                            Text(result.errors.joined(separator: "\n"))
                                .font(.system(.caption, design: .monospaced))
                                .foregroundColor(ModernColors.textSecondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding()
                                .background(ModernColors.statusCritical.opacity(0.1))
                                .cornerRadius(8)
                        }
                        .frame(maxHeight: 150)
                    }
                    .padding(.horizontal)
                }
            }
            .padding(40)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: - Execution

    private func runSync() async {
        hasStarted = true

        // Progress is automatically updated via executor's @Published property
        // which SwiftUI observes through @StateObject

        do {
            let syncResult = try await executor.execute(job: job, dryRun: false)
            await MainActor.run {
                result = syncResult
                hasCompleted = true
            }
        } catch {
            await MainActor.run {
                result = ExecutionResult(
                    id: UUID(),
                    jobId: job.id,
                    startTime: Date(),
                    endTime: Date(),
                    status: .failed,
                    filesTransferred: 0,
                    bytesTransferred: 0,
                    errors: [error.localizedDescription],
                    output: ""
                )
                hasCompleted = true
            }
        }
    }

    // MARK: - Helpers

    private func completionMessage(result: ExecutionResult) -> String {
        if result.status == .success {
            let speed = result.transferSpeed
            let speedFormatted = ByteCountFormatter.string(fromByteCount: Int64(speed), countStyle: .binary)
            return "Transferred \(result.filesTransferred) files at \(speedFormatted)/s"
        } else if result.status == .partialSuccess {
            return "Some files failed to transfer. Check errors below."
        } else {
            return "The sync operation encountered errors."
        }
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        let hours = Int(duration) / 3600
        let minutes = (Int(duration) % 3600) / 60
        let seconds = Int(duration) % 60

        if hours > 0 {
            return String(format: "%dh %dm %ds", hours, minutes, seconds)
        } else if minutes > 0 {
            return String(format: "%dm %ds", minutes, seconds)
        } else {
            return String(format: "%ds", seconds)
        }
    }
}

// MARK: - Stat Card

struct StatCard: View {
    let icon: String
    let title: String
    let value: String
    let color: Color

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(color)
                .shadow(color: color.opacity(0.6), radius: 8)

            VStack(spacing: 4) {
                Text(value)
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(color)

                Text(title)
                    .font(.caption)
                    .foregroundColor(ModernColors.textSecondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding()
        .glassCard()
    }
}

struct CompletionStatCard: View {
    let icon: String
    let title: String
    let value: String
    let color: Color

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundColor(color)
                .shadow(color: color.opacity(0.5), radius: 5)

            Text(value)
                .font(.title3)
                .fontWeight(.semibold)
                .foregroundColor(ModernColors.textPrimary)

            Text(title)
                .font(.caption)
                .foregroundColor(ModernColors.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .glassCard()
    }
}
