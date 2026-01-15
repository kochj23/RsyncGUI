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
        .frame(minWidth: 800, idealWidth: 800, maxWidth: 800,
               minHeight: 600, idealHeight: 600, maxHeight: 600)
        .fixedSize()
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
        ScrollView {
            VStack(spacing: 30) {
                // Main progress circle
                mainProgressCircle

                // Statistics grid
                statisticsGrid

                // Current file
                currentFileSection

                // Speed and time
                speedTimeSection
            }
            .padding(40)
        }
        .background(
            LinearGradient(
                colors: [
                    Color.blue.opacity(0.05),
                    Color.purple.opacity(0.05)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
    }

    private var mainProgressCircle: some View {
        ZStack {
            // Background circle
            Circle()
                .stroke(Color.secondary.opacity(0.2), lineWidth: 20)
                .frame(width: 200, height: 200)

            // Progress circle
            Circle()
                .trim(from: 0, to: CGFloat((executor.progress?.percentage ?? 0) / 100))
                .stroke(
                    AngularGradient(
                        colors: [.blue, .purple, .blue],
                        center: .center
                    ),
                    style: StrokeStyle(lineWidth: 20, lineCap: .round)
                )
                .frame(width: 200, height: 200)
                .rotationEffect(.degrees(-90))
                .animation(.easeInOut(duration: 0.5), value: executor.progress?.percentage)

            // Percentage text
            VStack(spacing: 4) {
                Text("\(Int(executor.progress?.percentage ?? 0))%")
                    .font(.system(size: 48, weight: .bold, design: .rounded))
                    .foregroundStyle(.blue.gradient)

                Text("Complete")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }

    private var statisticsGrid: some View {
        LazyVGrid(columns: [
            GridItem(.flexible()),
            GridItem(.flexible())
        ], spacing: 20) {
            StatCard(
                icon: "doc.fill",
                title: "Files Transferred",
                value: "\(executor.progress?.filesTransferred ?? 0)",
                color: .blue
            )

            StatCard(
                icon: "arrow.down.circle.fill",
                title: "Data Transferred",
                value: executor.progress?.bytesTransferredFormatted ?? "0 B",
                color: .green
            )

            StatCard(
                icon: "gauge.high",
                title: "Transfer Speed",
                value: executor.progress?.speedFormatted ?? "0 B/s",
                color: .orange
            )

            StatCard(
                icon: "clock.fill",
                title: "Time Remaining",
                value: executor.progress?.timeRemainingFormatted ?? "—",
                color: .purple
            )
        }
    }

    private var currentFileSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack { Image(systemName: "doc.text.fill"); Text("Current File") }
                .font(.headline)
                .foregroundColor(.secondary)

            HStack {
                Image(systemName: "arrow.right.circle.fill")
                    .foregroundColor(.blue)

                Text(executor.progress?.currentFile ?? "Preparing...")
                    .font(.system(.body, design: .monospaced))
                    .lineLimit(2)
                    .truncationMode(.middle)

                Spacer()
            }
            .padding()
            .background(Color.secondary.opacity(0.1))
            .cornerRadius(8)
        }
    }

    private var speedTimeSection: some View {
        HStack(spacing: 40) {
            VStack(alignment: .leading, spacing: 8) {
                HStack { Image(systemName: "speedometer"); Text("Average Speed") }
                    .font(.caption)
                    .foregroundColor(.secondary)

                Text(executor.progress?.speedFormatted ?? "Calculating...")
                    .font(.title3)
                    .fontWeight(.semibold)
                    .foregroundStyle(.blue.gradient)
            }

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                HStack { Image(systemName: "hourglass"); Text("Estimated Time") }
                    .font(.caption)
                    .foregroundColor(.secondary)

                Text(executor.progress?.timeRemainingFormatted ?? "Calculating...")
                    .font(.title3)
                    .fontWeight(.semibold)
                    .foregroundStyle(.purple.gradient)
            }

            Spacer()
        }
        .padding()
        .background(Color.secondary.opacity(0.05))
        .cornerRadius(12)
    }

    // MARK: - Completion View

    private func completionView(result: ExecutionResult) -> some View {
        VStack(spacing: 30) {
            // Success/failure icon
            Image(systemName: result.status == .success ? "checkmark.circle.fill" : "xmark.circle.fill")
                .font(.system(size: 80))
                .foregroundStyle(result.status == .success ? Color.green.gradient : Color.red.gradient)

            VStack(spacing: 12) {
                Text(result.status == .success ? "Sync Completed Successfully" : "Sync Failed")
                    .font(.title)
                    .fontWeight(.bold)

                Text(completionMessage(result: result))
                    .font(.title3)
                    .foregroundColor(.secondary)
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
                    color: .blue
                )

                CompletionStatCard(
                    icon: "arrow.down.circle.fill",
                    title: "Data",
                    value: ByteCountFormatter.string(fromByteCount: result.bytesTransferred, countStyle: .binary),
                    color: .green
                )

                CompletionStatCard(
                    icon: "clock.fill",
                    title: "Duration",
                    value: formatDuration(result.duration),
                    color: .purple
                )
            }
            .padding()

            if !result.errors.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    HStack { Image(systemName: "exclamationmark.triangle.fill"); Text("Errors") }
                        .font(.headline)
                        .foregroundColor(.red)

                    ScrollView {
                        Text(result.errors.joined(separator: "\n"))
                            .font(.system(.caption, design: .monospaced))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding()
                            .background(Color.red.opacity(0.1))
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

            VStack(spacing: 4) {
                Text(value)
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundStyle(color.gradient)

                Text(title)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(Color.secondary.opacity(0.05))
        .cornerRadius(12)
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

            Text(value)
                .font(.title3)
                .fontWeight(.semibold)

            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(Color.secondary.opacity(0.05))
        .cornerRadius(8)
    }
}
