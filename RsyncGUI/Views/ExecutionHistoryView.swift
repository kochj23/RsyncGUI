//
//  ExecutionHistoryView.swift
//  RsyncGUI
//
//  Created by Jordan Koch on 1/14/26.
//

import SwiftUI

/// Execution history viewer showing past sync runs
struct ExecutionHistoryView: View {
    let jobId: UUID?
    @State private var history: [ExecutionHistoryEntry] = []
    @State private var filter: HistoryFilter = .all
    @Environment(\.dismiss) private var dismiss

    enum HistoryFilter: String, CaseIterable {
        case all = "All"
        case success = "Successful"
        case failed = "Failed"
        case week = "Last 7 Days"
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            header

            Divider()

            // Filter bar
            Picker("Filter", selection: $filter) {
                ForEach(HistoryFilter.allCases, id: \.self) { filter in
                    Text(filter.rawValue).tag(filter)
                }
            }
            .pickerStyle(.segmented)
            .padding()

            Divider()

            // History list
            if filteredHistory.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(filteredHistory) { entry in
                            HistoryEntryRow(entry: entry)
                        }
                    }
                    .padding()
                }
            }

            Divider()

            // Footer
            footer
        }
        .frame(width: 900, height: 600)
        .onAppear {
            loadHistory()
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Image(systemName: "clock.arrow.circlepath")
                .font(.title)
                .foregroundStyle(.blue.gradient)

            VStack(alignment: .leading, spacing: 4) {
                Text("Execution History")
                    .font(.title2)
                    .fontWeight(.bold)

                Text("\(filteredHistory.count) execution(s)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            Button("Close") {
                dismiss()
            }
        }
        .padding()
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "clock")
                .font(.system(size: 60))
                .foregroundColor(.secondary)

            Text("No Execution History")
                .font(.title3)
                .foregroundColor(.secondary)

            Text("Run some syncs to see history here")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            Button("Export to CSV") {
                exportToCSV()
            }
            .buttonStyle(.bordered)

            Spacer()

            Text("\(history.count) total execution(s)")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // MARK: - Filtering

    private var filteredHistory: [ExecutionHistoryEntry] {
        switch filter {
        case .all:
            return history
        case .success:
            return history.filter { $0.status == .success }
        case .failed:
            return history.filter { $0.status == .failed }
        case .week:
            let cutoff = Calendar.current.date(byAdding: .day, value: -7, to: Date())!
            return history.filter { $0.timestamp >= cutoff }
        }
    }

    // MARK: - Actions

    private func loadHistory() {
        if let jobId = jobId {
            history = ExecutionHistoryManager.shared.getHistory(for: jobId)
        } else {
            history = ExecutionHistoryManager.shared.getAllHistory()
        }
    }

    private func exportToCSV() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.nameFieldStringValue = "rsyncgui-history-\(Date().formatted(date: .numeric, time: .omitted)).csv"

        if panel.runModal() == .OK, let url = panel.url {
            let csv = ExecutionHistoryManager.shared.exportToCSV()
            try? csv.write(to: url, atomically: true, encoding: .utf8)
        }
    }
}

// MARK: - History Entry Row

struct HistoryEntryRow: View {
    let entry: ExecutionHistoryEntry

    var body: some View {
        HStack(spacing: 16) {
            // Status indicator
            Image(systemName: statusIcon)
                .font(.title2)
                .foregroundColor(statusColor)

            VStack(alignment: .leading, spacing: 8) {
                // Job name and timestamp
                HStack {
                    Text(entry.jobName)
                        .font(.headline)
                    Spacer()
                    Text(entry.timestamp.formatted(date: .abbreviated, time: .shortened))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                // Statistics
                HStack(spacing: 20) {
                    HStack(spacing: 4) {
                        Image(systemName: "doc.fill")
                            .foregroundColor(.blue)
                        Text("\(entry.filesTransferred) files")
                    }

                    HStack(spacing: 4) {
                        Image(systemName: "arrow.down.circle.fill")
                            .foregroundColor(.green)
                        Text(ByteCountFormatter.string(fromByteCount: entry.bytesTransferred, countStyle: .binary))
                    }

                    HStack(spacing: 4) {
                        Image(systemName: "clock.fill")
                            .foregroundColor(.purple)
                        Text(formatDuration(entry.duration))
                    }

                    if !entry.errors.isEmpty {
                        HStack(spacing: 4) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.red)
                            Text("\(entry.errors.count) errors")
                        }
                    }
                }
                .font(.caption)
            }

            Spacer()
        }
        .padding()
        .background(Color.secondary.opacity(0.05))
        .cornerRadius(8)
    }

    private var statusIcon: String {
        switch entry.status {
        case .success: return "checkmark.circle.fill"
        case .failed: return "xmark.circle.fill"
        case .partialSuccess: return "exclamationmark.circle.fill"
        case .cancelled: return "stop.circle.fill"
        }
    }

    private var statusColor: Color {
        switch entry.status {
        case .success: return .green
        case .failed: return .red
        case .partialSuccess: return .orange
        case .cancelled: return .gray
        }
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        let hours = Int(duration) / 3600
        let minutes = (Int(duration) % 3600) / 60
        let seconds = Int(duration) % 60

        if hours > 0 {
            return String(format: "%dh %dm", hours, minutes)
        } else if minutes > 0 {
            return String(format: "%dm %ds", minutes, seconds)
        } else {
            return String(format: "%ds", seconds)
        }
    }
}
