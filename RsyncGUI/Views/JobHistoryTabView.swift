//
//  JobHistoryTabView.swift
//  RsyncGUI
//
//  Job History tab view for the main detail pane
//  Shows all execution history across all jobs with filtering and search
//
//  Created by Jordan Koch on 1/28/26.
//

import SwiftUI

/// Main job history tab view displayed in the detail pane
struct JobHistoryTabView: View {
    @State private var history: [ExecutionHistoryEntry] = []
    @State private var filter: HistoryFilter = .all
    @State private var searchText: String = ""
    @State private var sortOrder: SortOrder = .newest
    @State private var selectedJobFilter: String? = nil
    @State private var isLoading = true

    enum HistoryFilter: String, CaseIterable {
        case all = "All"
        case success = "Successful"
        case failed = "Failed"
        case week = "Last 7 Days"
        case month = "Last 30 Days"
    }

    enum SortOrder: String, CaseIterable {
        case newest = "Newest First"
        case oldest = "Oldest First"
        case jobName = "By Job Name"
        case duration = "By Duration"
    }

    private var uniqueJobNames: [String] {
        Array(Set(history.map { $0.jobName })).sorted()
    }

    private var filteredHistory: [ExecutionHistoryEntry] {
        var result = history

        // Apply status filter
        switch filter {
        case .all:
            break
        case .success:
            result = result.filter { $0.status == .success }
        case .failed:
            result = result.filter { $0.status == .failed }
        case .week:
            let cutoff = Calendar.current.date(byAdding: .day, value: -7, to: Date())!
            result = result.filter { $0.timestamp >= cutoff }
        case .month:
            let cutoff = Calendar.current.date(byAdding: .day, value: -30, to: Date())!
            result = result.filter { $0.timestamp >= cutoff }
        }

        // Apply job filter
        if let jobFilter = selectedJobFilter {
            result = result.filter { $0.jobName == jobFilter }
        }

        // Apply search
        if !searchText.isEmpty {
            result = result.filter {
                $0.jobName.localizedCaseInsensitiveContains(searchText) ||
                $0.errors.joined(separator: " ").localizedCaseInsensitiveContains(searchText)
            }
        }

        // Apply sort
        switch sortOrder {
        case .newest:
            result.sort { $0.timestamp > $1.timestamp }
        case .oldest:
            result.sort { $0.timestamp < $1.timestamp }
        case .jobName:
            result.sort { $0.jobName < $1.jobName }
        case .duration:
            result.sort { $0.duration > $1.duration }
        }

        return result
    }

    private var statistics: HistoryStatistics {
        HistoryStatistics(entries: filteredHistory)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            header

            // Statistics cards
            statisticsSection

            // Filter bar
            filterBar

            Divider()
                .background(ModernColors.glassBorder)

            // History list
            if isLoading {
                loadingView
            } else if filteredHistory.isEmpty {
                emptyState
            } else {
                historyList
            }

            Divider()
                .background(ModernColors.glassBorder)

            // Footer
            footer
        }
        .onAppear {
            loadHistory()
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 16) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 40))
                .foregroundStyle(
                    LinearGradient(
                        colors: [ModernColors.cyan, ModernColors.purple],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .shadow(color: ModernColors.cyan.opacity(0.5), radius: 10)

            VStack(alignment: .leading, spacing: 4) {
                Text("Job History")
                    .modernHeader(size: .medium)

                Text("All sync executions across all jobs")
                    .font(.subheadline)
                    .foregroundColor(ModernColors.textSecondary)
            }

            Spacer()

            // Search field
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(ModernColors.textSecondary)
                TextField("Search history...", text: $searchText)
                    .textFieldStyle(.plain)
                    .foregroundColor(ModernColors.textPrimary)
                if !searchText.isEmpty {
                    Button(action: { searchText = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(ModernColors.textSecondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(8)
            .frame(width: 200)
            .background(ModernColors.glassBackground)
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(ModernColors.glassBorder, lineWidth: 1)
            )

            Button(action: { loadHistory() }) {
                Image(systemName: "arrow.clockwise")
                    .font(.title3)
            }
            .buttonStyle(ModernButtonStyle(color: ModernColors.cyan, style: .glass))
            .help("Refresh history")
        }
        .padding()
    }

    // MARK: - Statistics Section

    private var statisticsSection: some View {
        HStack(spacing: 16) {
            HistoryStatCard(
                title: "Total Runs",
                value: "\(statistics.totalRuns)",
                icon: "play.circle.fill",
                color: ModernColors.cyan
            )

            HistoryStatCard(
                title: "Success Rate",
                value: String(format: "%.1f%%", statistics.successRate),
                icon: "checkmark.circle.fill",
                color: ModernColors.accentGreen
            )

            HistoryStatCard(
                title: "Files Synced",
                value: formatNumber(statistics.totalFiles),
                icon: "doc.fill",
                color: ModernColors.purple
            )

            HistoryStatCard(
                title: "Data Transferred",
                value: ByteCountFormatter.string(fromByteCount: statistics.totalBytes, countStyle: .binary),
                icon: "arrow.down.circle.fill",
                color: ModernColors.orange
            )

            HistoryStatCard(
                title: "Total Time",
                value: formatDuration(statistics.totalDuration),
                icon: "clock.fill",
                color: ModernColors.pink
            )
        }
        .padding(.horizontal)
        .padding(.bottom)
    }

    // MARK: - Filter Bar

    private var filterBar: some View {
        HStack(spacing: 16) {
            // Status filter
            Picker("Status", selection: $filter) {
                ForEach(HistoryFilter.allCases, id: \.self) { filter in
                    Text(filter.rawValue).tag(filter)
                }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 400)

            Spacer()

            // Job filter
            Picker("Job", selection: $selectedJobFilter) {
                Text("All Jobs").tag(nil as String?)
                ForEach(uniqueJobNames, id: \.self) { name in
                    Text(name).tag(name as String?)
                }
            }
            .frame(width: 150)

            // Sort order
            Picker("Sort", selection: $sortOrder) {
                ForEach(SortOrder.allCases, id: \.self) { order in
                    Text(order.rawValue).tag(order)
                }
            }
            .frame(width: 140)
        }
        .padding()
    }

    // MARK: - History List

    private var historyList: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                ForEach(filteredHistory) { entry in
                    HistoryEntryCard(entry: entry)
                }
            }
            .padding()
        }
    }

    // MARK: - Loading View

    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .progressViewStyle(CircularProgressViewStyle(tint: ModernColors.cyan))
                .scaleEffect(1.5)

            Text("Loading history...")
                .font(.headline)
                .foregroundColor(ModernColors.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 20) {
            Image(systemName: "clock")
                .font(.system(size: 80))
                .foregroundStyle(
                    LinearGradient(
                        colors: [ModernColors.textSecondary, ModernColors.textTertiary],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )

            VStack(spacing: 8) {
                Text("No Execution History")
                    .font(.title2)
                    .fontWeight(.semibold)
                    .foregroundColor(ModernColors.textPrimary)

                Text(emptyStateMessage)
                    .font(.subheadline)
                    .foregroundColor(ModernColors.textSecondary)
                    .multilineTextAlignment(.center)
            }

            if filter != .all || selectedJobFilter != nil || !searchText.isEmpty {
                Button("Clear Filters") {
                    filter = .all
                    selectedJobFilter = nil
                    searchText = ""
                }
                .buttonStyle(ModernButtonStyle(color: ModernColors.cyan, style: .outlined))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyStateMessage: String {
        if !searchText.isEmpty {
            return "No results match '\(searchText)'"
        } else if selectedJobFilter != nil {
            return "No history for selected job"
        } else if filter != .all {
            return "No \(filter.rawValue.lowercased()) executions found"
        } else {
            return "Run some sync jobs to see history here"
        }
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            Button(action: exportToCSV) {
                Label("Export to CSV", systemImage: "square.and.arrow.up")
            }
            .buttonStyle(ModernButtonStyle(color: ModernColors.cyan, style: .outlined))

            Button(action: clearHistory) {
                Label("Clear History", systemImage: "trash")
            }
            .buttonStyle(ModernButtonStyle(color: ModernColors.statusCritical, style: .outlined))

            Spacer()

            Text("\(filteredHistory.count) of \(history.count) execution(s)")
                .font(.caption)
                .foregroundColor(ModernColors.textSecondary)
        }
        .padding()
    }

    // MARK: - Actions

    private func loadHistory() {
        isLoading = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            history = ExecutionHistoryManager.shared.getAllHistory(limit: 1000)
            isLoading = false
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

    private func clearHistory() {
        let alert = NSAlert()
        alert.messageText = "Clear All History?"
        alert.informativeText = "This will permanently delete all execution history. This action cannot be undone."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Clear History")
        alert.addButton(withTitle: "Cancel")

        if alert.runModal() == .alertFirstButtonReturn {
            ExecutionHistoryManager.shared.clearHistory()
            loadHistory()
        }
    }

    // MARK: - Helpers

    private func formatNumber(_ number: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: number)) ?? "\(number)"
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        let hours = Int(duration) / 3600
        let minutes = (Int(duration) % 3600) / 60

        if hours > 0 {
            return String(format: "%dh %dm", hours, minutes)
        } else if minutes > 0 {
            return String(format: "%dm", minutes)
        } else {
            return String(format: "%ds", Int(duration))
        }
    }
}

// MARK: - Statistics Model

struct HistoryStatistics {
    let totalRuns: Int
    let successfulRuns: Int
    let failedRuns: Int
    let totalFiles: Int
    let totalBytes: Int64
    let totalDuration: TimeInterval

    var successRate: Double {
        guard totalRuns > 0 else { return 0 }
        return Double(successfulRuns) / Double(totalRuns) * 100
    }

    init(entries: [ExecutionHistoryEntry]) {
        totalRuns = entries.count
        successfulRuns = entries.filter { $0.status == .success }.count
        failedRuns = entries.filter { $0.status == .failed }.count
        totalFiles = entries.reduce(0) { $0 + $1.filesTransferred }
        totalBytes = entries.reduce(0) { $0 + $1.bytesTransferred }
        totalDuration = entries.reduce(0) { $0 + $1.duration }
    }
}

// MARK: - History Stat Card

struct HistoryStatCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(color)
                .shadow(color: color.opacity(0.5), radius: 5)

            VStack(alignment: .leading, spacing: 2) {
                Text(value)
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundColor(ModernColors.textPrimary)

                Text(title)
                    .font(.caption)
                    .foregroundColor(ModernColors.textSecondary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(ModernColors.glassBackground)
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(ModernColors.glassBorder, lineWidth: 1)
        )
    }
}

// MARK: - History Entry Card

struct HistoryEntryCard: View {
    let entry: ExecutionHistoryEntry
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Main row
            HStack(spacing: 16) {
                // Status indicator
                Image(systemName: statusIcon)
                    .font(.title)
                    .foregroundColor(statusColor)
                    .shadow(color: statusColor.opacity(0.5), radius: 5)

                VStack(alignment: .leading, spacing: 4) {
                    // Job name and timestamp
                    HStack {
                        Text(entry.jobName)
                            .font(.headline)
                            .foregroundColor(ModernColors.textPrimary)

                        Spacer()

                        Text(entry.timestamp.formatted(date: .abbreviated, time: .shortened))
                            .font(.caption)
                            .foregroundColor(ModernColors.textSecondary)
                    }

                    // Statistics
                    HStack(spacing: 20) {
                        StatBadge(icon: "doc.fill", value: "\(entry.filesTransferred) files", color: ModernColors.cyan)
                        StatBadge(icon: "arrow.down.circle.fill", value: ByteCountFormatter.string(fromByteCount: entry.bytesTransferred, countStyle: .binary), color: ModernColors.accentGreen)
                        StatBadge(icon: "clock.fill", value: formatDuration(entry.duration), color: ModernColors.purple)

                        if !entry.errors.isEmpty {
                            StatBadge(icon: "exclamationmark.triangle.fill", value: "\(entry.errors.count) errors", color: ModernColors.statusCritical)
                        }
                    }
                }

                // Expand button
                if !entry.errors.isEmpty {
                    Button(action: { withAnimation { isExpanded.toggle() } }) {
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .foregroundColor(ModernColors.textSecondary)
                    }
                    .buttonStyle(.plain)
                }
            }

            // Expanded error details
            if isExpanded && !entry.errors.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Errors")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(ModernColors.statusCritical)

                    ForEach(entry.errors.prefix(10), id: \.self) { error in
                        Text(error)
                            .font(.caption)
                            .foregroundColor(ModernColors.textSecondary)
                            .lineLimit(2)
                    }

                    if entry.errors.count > 10 {
                        Text("... and \(entry.errors.count - 10) more errors")
                            .font(.caption)
                            .foregroundColor(ModernColors.textTertiary)
                    }
                }
                .padding()
                .background(ModernColors.statusCritical.opacity(0.1))
                .cornerRadius(8)
            }
        }
        .padding()
        .background(ModernColors.glassBackground)
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(ModernColors.glassBorder, lineWidth: 1)
        )
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
        case .success: return ModernColors.accentGreen
        case .failed: return ModernColors.statusCritical
        case .partialSuccess: return ModernColors.orange
        case .cancelled: return ModernColors.textTertiary
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

// MARK: - Stat Badge

struct StatBadge: View {
    let icon: String
    let value: String
    let color: Color

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .foregroundColor(color)
            Text(value)
                .foregroundColor(ModernColors.textSecondary)
        }
        .font(.caption)
    }
}

#Preview {
    JobHistoryTabView()
        .frame(width: 1000, height: 700)
        .background(GlassmorphicBackground())
}
