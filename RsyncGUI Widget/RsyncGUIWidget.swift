//
//  RsyncGUIWidget.swift
//  RsyncGUI Widget
//
//  Created by Jordan Koch on 2/4/26.
//

import WidgetKit
import SwiftUI

// MARK: - Widget Provider

struct RsyncGUIWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> RsyncGUIWidgetEntry {
        RsyncGUIWidgetEntry.placeholder
    }

    func getSnapshot(in context: Context, completion: @escaping (RsyncGUIWidgetEntry) -> Void) {
        if context.isPreview {
            completion(RsyncGUIWidgetEntry.placeholder)
        } else {
            let data = SharedDataManager.shared.loadWidgetData()
            completion(RsyncGUIWidgetEntry(date: Date(), data: data))
        }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<RsyncGUIWidgetEntry>) -> Void) {
        let data = SharedDataManager.shared.loadWidgetData()
        let entry = RsyncGUIWidgetEntry(date: Date(), data: data)

        // Update every 15 minutes
        let nextUpdate = Calendar.current.date(byAdding: .minute, value: 15, to: Date())!
        let timeline = Timeline(entries: [entry], policy: .after(nextUpdate))
        completion(timeline)
    }
}

// MARK: - Small Widget View

struct RsyncGUIWidgetSmallView: View {
    let entry: RsyncGUIWidgetEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Header with health score
            HStack {
                Image(systemName: entry.data.healthGradeIcon)
                    .font(.title2)
                    .foregroundColor(healthColor)
                Text(entry.data.backupHealthGrade)
                    .font(.title2.bold())
                    .foregroundColor(healthColor)
                Spacer()
            }

            // Last sync status
            if let lastSync = entry.data.lastSyncTime {
                HStack(spacing: 4) {
                    Image(systemName: entry.data.lastSyncStatusIcon)
                        .font(.caption)
                        .foregroundColor(statusColor)
                    Text(lastSync.relativeTimeString)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            } else {
                Text("No syncs yet")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            // Job count
            HStack {
                Image(systemName: "folder.fill")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                Text("\(entry.data.enabledJobs)/\(entry.data.totalJobs) jobs")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            // Errors indicator
            if !entry.data.jobsWithErrors.isEmpty {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.caption2)
                        .foregroundColor(.orange)
                    Text("\(entry.data.jobsWithErrors.count) errors")
                        .font(.caption2)
                        .foregroundColor(.orange)
                }
            }
        }
        .padding()
    }

    private var healthColor: Color {
        switch entry.data.healthScoreColorName {
        case "green": return .green
        case "blue": return .blue
        case "yellow": return .yellow
        case "orange": return .orange
        case "red": return .red
        default: return .secondary
        }
    }

    private var statusColor: Color {
        switch entry.data.lastSyncStatusColorName {
        case "green": return .green
        case "red": return .red
        case "orange": return .orange
        default: return .secondary
        }
    }
}

// MARK: - Medium Widget View

struct RsyncGUIWidgetMediumView: View {
    let entry: RsyncGUIWidgetEntry

    var body: some View {
        HStack(spacing: 16) {
            // Left side - Health score
            VStack(alignment: .center, spacing: 4) {
                ZStack {
                    Circle()
                        .stroke(healthColor.opacity(0.3), lineWidth: 8)
                        .frame(width: 60, height: 60)
                    Circle()
                        .trim(from: 0, to: CGFloat(entry.data.backupHealthScore) / 100)
                        .stroke(healthColor, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                        .frame(width: 60, height: 60)
                        .rotationEffect(.degrees(-90))
                    Text(entry.data.backupHealthGrade)
                        .font(.title2.bold())
                        .foregroundColor(healthColor)
                }

                Text("Health")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            .padding(.leading, 4)

            // Right side - Details
            VStack(alignment: .leading, spacing: 6) {
                // Last sync
                VStack(alignment: .leading, spacing: 2) {
                    Text("Last Sync")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    if let lastSync = entry.data.lastSyncTime {
                        HStack(spacing: 4) {
                            Image(systemName: entry.data.lastSyncStatusIcon)
                                .font(.caption)
                                .foregroundColor(statusColor)
                            Text(entry.data.lastSyncJobName ?? "Unknown")
                                .font(.caption.bold())
                                .lineLimit(1)
                        }
                        Text(lastSync.relativeTimeString)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    } else {
                        Text("No syncs yet")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                Divider()

                // Next scheduled
                VStack(alignment: .leading, spacing: 2) {
                    Text("Next Scheduled")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    if let nextSync = entry.data.nextScheduledSync {
                        HStack(spacing: 4) {
                            Image(systemName: "clock.fill")
                                .font(.caption)
                                .foregroundColor(.blue)
                            Text(entry.data.nextScheduledJobName ?? "Unknown")
                                .font(.caption.bold())
                                .lineLimit(1)
                        }
                        Text(nextSync.relativeTimeString)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    } else {
                        Text("None scheduled")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }

            Spacer()

            // Errors column (if any)
            if !entry.data.jobsWithErrors.isEmpty {
                VStack(alignment: .trailing, spacing: 4) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.title3)
                        .foregroundColor(.orange)
                    Text("\(entry.data.jobsWithErrors.count)")
                        .font(.title3.bold())
                        .foregroundColor(.orange)
                    Text("errors")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                .padding(.trailing, 4)
            }
        }
        .padding()
    }

    private var healthColor: Color {
        switch entry.data.healthScoreColorName {
        case "green": return .green
        case "blue": return .blue
        case "yellow": return .yellow
        case "orange": return .orange
        case "red": return .red
        default: return .secondary
        }
    }

    private var statusColor: Color {
        switch entry.data.lastSyncStatusColorName {
        case "green": return .green
        case "red": return .red
        case "orange": return .orange
        default: return .secondary
        }
    }
}

// MARK: - Large Widget View

struct RsyncGUIWidgetLargeView: View {
    let entry: RsyncGUIWidgetEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.title2)
                    .foregroundColor(.blue)
                Text("RsyncGUI")
                    .font(.headline)
                Spacer()

                // Health badge
                HStack(spacing: 4) {
                    Image(systemName: entry.data.healthGradeIcon)
                        .font(.caption)
                        .foregroundColor(healthColor)
                    Text("\(entry.data.backupHealthScore)%")
                        .font(.caption.bold())
                        .foregroundColor(healthColor)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(healthColor.opacity(0.15))
                .cornerRadius(8)
            }

            Divider()

            // Status row
            HStack(spacing: 20) {
                // Last sync
                VStack(alignment: .leading, spacing: 2) {
                    Text("Last Sync")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    if let lastSync = entry.data.lastSyncTime {
                        HStack(spacing: 4) {
                            Image(systemName: entry.data.lastSyncStatusIcon)
                                .foregroundColor(statusColor)
                            Text(entry.data.lastSyncJobName ?? "Unknown")
                                .font(.subheadline.bold())
                                .lineLimit(1)
                        }
                        Text(lastSync.relativeTimeString)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } else {
                        Text("No syncs yet")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }

                Spacer()

                // Next scheduled
                VStack(alignment: .trailing, spacing: 2) {
                    Text("Next Scheduled")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    if let nextSync = entry.data.nextScheduledSync {
                        HStack(spacing: 4) {
                            Text(entry.data.nextScheduledJobName ?? "Unknown")
                                .font(.subheadline.bold())
                                .lineLimit(1)
                            Image(systemName: "clock.fill")
                                .foregroundColor(.blue)
                        }
                        Text(nextSync.relativeTimeString)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } else {
                        Text("None scheduled")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }
            }

            Divider()

            // Jobs overview
            HStack {
                Label("\(entry.data.enabledJobs) active", systemImage: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundColor(.green)
                Spacer()
                Label("\(entry.data.totalJobs) total", systemImage: "folder.fill")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            // Jobs with errors
            if !entry.data.jobsWithErrors.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Label("Jobs with Errors", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption.bold())
                        .foregroundColor(.orange)

                    ForEach(entry.data.jobsWithErrors.prefix(3)) { error in
                        HStack {
                            Text(error.jobName)
                                .font(.caption)
                                .lineLimit(1)
                            Spacer()
                            Text(error.lastFailedTime.relativeTimeString)
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        .padding(.vertical, 2)
                    }

                    if entry.data.jobsWithErrors.count > 3 {
                        Text("+\(entry.data.jobsWithErrors.count - 3) more")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(8)
                .background(Color.orange.opacity(0.1))
                .cornerRadius(8)
            }

            Spacer()

            // Recent syncs
            if !entry.data.recentSyncs.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Recent Activity")
                        .font(.caption2)
                        .foregroundColor(.secondary)

                    ForEach(entry.data.recentSyncs.prefix(3)) { sync in
                        HStack {
                            Image(systemName: syncStatusIcon(sync.status))
                                .font(.caption2)
                                .foregroundColor(syncStatusColor(sync.status))
                            Text(sync.jobName)
                                .font(.caption)
                                .lineLimit(1)
                            Spacer()
                            Text(sync.timestamp.relativeTimeString)
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
        }
        .padding()
    }

    private var healthColor: Color {
        switch entry.data.healthScoreColorName {
        case "green": return .green
        case "blue": return .blue
        case "yellow": return .yellow
        case "orange": return .orange
        case "red": return .red
        default: return .secondary
        }
    }

    private var statusColor: Color {
        switch entry.data.lastSyncStatusColorName {
        case "green": return .green
        case "red": return .red
        case "orange": return .orange
        default: return .secondary
        }
    }

    private func syncStatusIcon(_ status: String) -> String {
        switch status {
        case "success": return "checkmark.circle.fill"
        case "failed": return "xmark.circle.fill"
        case "partialSuccess": return "exclamationmark.circle.fill"
        default: return "circle.fill"
        }
    }

    private func syncStatusColor(_ status: String) -> Color {
        switch status {
        case "success": return .green
        case "failed": return .red
        case "partialSuccess": return .orange
        default: return .secondary
        }
    }
}

// MARK: - Widget Entry View

struct RsyncGUIWidgetEntryView: View {
    @Environment(\.widgetFamily) var family
    var entry: RsyncGUIWidgetEntry

    var body: some View {
        switch family {
        case .systemSmall:
            RsyncGUIWidgetSmallView(entry: entry)
        case .systemMedium:
            RsyncGUIWidgetMediumView(entry: entry)
        case .systemLarge:
            RsyncGUIWidgetLargeView(entry: entry)
        default:
            RsyncGUIWidgetSmallView(entry: entry)
        }
    }
}

// MARK: - Widget Configuration

@main
struct RsyncGUIWidget: Widget {
    let kind: String = "RsyncGUIWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: RsyncGUIWidgetProvider()) { entry in
            RsyncGUIWidgetEntryView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("RsyncGUI Status")
        .description("Monitor your backup jobs, health score, and sync status.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

// MARK: - Preview

#Preview(as: .systemSmall) {
    RsyncGUIWidget()
} timeline: {
    RsyncGUIWidgetEntry.placeholder
}

#Preview(as: .systemMedium) {
    RsyncGUIWidget()
} timeline: {
    RsyncGUIWidgetEntry.placeholder
}

#Preview(as: .systemLarge) {
    RsyncGUIWidget()
} timeline: {
    RsyncGUIWidgetEntry(date: Date(), data: {
        var data = WidgetSyncData()
        data.lastSyncTime = Date().addingTimeInterval(-1800)
        data.lastSyncStatus = "success"
        data.lastSyncJobName = "Documents Backup"
        data.nextScheduledSync = Date().addingTimeInterval(3600)
        data.nextScheduledJobName = "Photos Sync"
        data.backupHealthScore = 92
        data.backupHealthGrade = "A"
        data.totalJobs = 8
        data.enabledJobs = 6
        data.jobsWithErrors = [
            WidgetJobError(id: UUID(), jobName: "Server Backup", errorMessage: "Connection refused", lastFailedTime: Date().addingTimeInterval(-7200), failureCount: 2)
        ]
        data.recentSyncs = [
            WidgetRecentSync(id: UUID(), jobName: "Documents", timestamp: Date().addingTimeInterval(-1800), status: "success", filesTransferred: 45, bytesTransferred: 12500000),
            WidgetRecentSync(id: UUID(), jobName: "Photos", timestamp: Date().addingTimeInterval(-7200), status: "success", filesTransferred: 120, bytesTransferred: 856000000),
            WidgetRecentSync(id: UUID(), jobName: "Server Backup", timestamp: Date().addingTimeInterval(-10800), status: "failed", filesTransferred: 0, bytesTransferred: 0)
        ]
        return data
    }())
}
