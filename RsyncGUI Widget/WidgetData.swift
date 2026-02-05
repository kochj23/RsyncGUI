//
//  WidgetData.swift
//  RsyncGUI Widget
//
//  Created by Jordan Koch on 2/4/26.
//

import Foundation
import WidgetKit

/// App Group identifier for sharing data between main app and widget
let appGroupIdentifier = "group.com.jkoch.rsyncgui"

// MARK: - Widget Data Models

/// Summary data for the widget
struct WidgetSyncData: Codable {
    var lastSyncTime: Date?
    var lastSyncStatus: String?
    var lastSyncJobName: String?
    var nextScheduledSync: Date?
    var nextScheduledJobName: String?
    var backupHealthScore: Int // 0-100
    var backupHealthGrade: String // A, B, C, D, F
    var totalJobs: Int
    var enabledJobs: Int
    var jobsWithErrors: [WidgetJobError]
    var recentSyncs: [WidgetRecentSync]
    var lastUpdated: Date

    init() {
        self.lastSyncTime = nil
        self.lastSyncStatus = nil
        self.lastSyncJobName = nil
        self.nextScheduledSync = nil
        self.nextScheduledJobName = nil
        self.backupHealthScore = 0
        self.backupHealthGrade = "?"
        self.totalJobs = 0
        self.enabledJobs = 0
        self.jobsWithErrors = []
        self.recentSyncs = []
        self.lastUpdated = Date()
    }
}

/// Job with errors for widget display
struct WidgetJobError: Codable, Identifiable {
    var id: UUID
    var jobName: String
    var errorMessage: String
    var lastFailedTime: Date
    var failureCount: Int
}

/// Recent sync summary for widget
struct WidgetRecentSync: Codable, Identifiable {
    var id: UUID
    var jobName: String
    var timestamp: Date
    var status: String // "success", "failed", "partialSuccess"
    var filesTransferred: Int
    var bytesTransferred: Int64
}

// MARK: - Widget Timeline Entry

/// Timeline entry for the widget
struct RsyncGUIWidgetEntry: TimelineEntry {
    let date: Date
    let data: WidgetSyncData
    let configuration: ConfigurationIntent?

    init(date: Date = Date(), data: WidgetSyncData = WidgetSyncData(), configuration: ConfigurationIntent? = nil) {
        self.date = date
        self.data = data
        self.configuration = configuration
    }

    static var placeholder: RsyncGUIWidgetEntry {
        var data = WidgetSyncData()
        data.lastSyncTime = Date().addingTimeInterval(-3600) // 1 hour ago
        data.lastSyncStatus = "success"
        data.lastSyncJobName = "Documents Backup"
        data.nextScheduledSync = Date().addingTimeInterval(7200) // 2 hours from now
        data.nextScheduledJobName = "Photos Sync"
        data.backupHealthScore = 85
        data.backupHealthGrade = "B"
        data.totalJobs = 5
        data.enabledJobs = 4
        return RsyncGUIWidgetEntry(date: Date(), data: data)
    }
}

// MARK: - Configuration Intent (Simple placeholder)

/// Simple configuration intent (expand for user configuration options)
struct ConfigurationIntent {
    var showDetailedStatus: Bool = true
}

// MARK: - Health Score Helpers

extension WidgetSyncData {
    /// Color name for the health score
    var healthScoreColorName: String {
        switch backupHealthScore {
        case 90...100: return "green"
        case 70..<90: return "blue"
        case 50..<70: return "yellow"
        case 25..<50: return "orange"
        default: return "red"
        }
    }

    /// Icon for health grade
    var healthGradeIcon: String {
        switch backupHealthGrade {
        case "A": return "checkmark.shield.fill"
        case "B": return "shield.fill"
        case "C": return "exclamationmark.shield.fill"
        case "D": return "xmark.shield.fill"
        case "F": return "xmark.shield.fill"
        default: return "questionmark.diamond.fill"
        }
    }

    /// Status icon for last sync
    var lastSyncStatusIcon: String {
        switch lastSyncStatus {
        case "success": return "checkmark.circle.fill"
        case "failed": return "xmark.circle.fill"
        case "partialSuccess": return "exclamationmark.circle.fill"
        case "cancelled": return "minus.circle.fill"
        default: return "questionmark.circle"
        }
    }

    /// Color name for last sync status
    var lastSyncStatusColorName: String {
        switch lastSyncStatus {
        case "success": return "green"
        case "failed": return "red"
        case "partialSuccess": return "orange"
        case "cancelled": return "gray"
        default: return "secondary"
        }
    }
}

// MARK: - Time Formatting Helpers

extension Date {
    /// Relative time string (e.g., "2h ago", "5m ago")
    var relativeTimeString: String {
        let now = Date()
        let interval = now.timeIntervalSince(self)

        if interval < 0 {
            // Future date
            let futureInterval = -interval
            if futureInterval < 60 {
                return "in \(Int(futureInterval))s"
            } else if futureInterval < 3600 {
                return "in \(Int(futureInterval / 60))m"
            } else if futureInterval < 86400 {
                return "in \(Int(futureInterval / 3600))h"
            } else {
                return "in \(Int(futureInterval / 86400))d"
            }
        } else {
            // Past date
            if interval < 60 {
                return "\(Int(interval))s ago"
            } else if interval < 3600 {
                return "\(Int(interval / 60))m ago"
            } else if interval < 86400 {
                return "\(Int(interval / 3600))h ago"
            } else {
                return "\(Int(interval / 86400))d ago"
            }
        }
    }

    /// Short time string for display
    var shortTimeString: String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: self)
    }
}

// MARK: - Byte Formatting

extension Int64 {
    /// Human-readable byte string
    var humanReadableBytes: String {
        let units = ["B", "KB", "MB", "GB", "TB"]
        var value = Double(self)
        var unitIndex = 0

        while value >= 1024 && unitIndex < units.count - 1 {
            value /= 1024
            unitIndex += 1
        }

        if unitIndex == 0 {
            return "\(Int(value)) \(units[unitIndex])"
        } else {
            return String(format: "%.1f %@", value, units[unitIndex])
        }
    }
}
