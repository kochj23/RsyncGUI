//
//  WidgetDataSync.swift
//  RsyncGUI
//
//  Created by Jordan Koch on 2/4/26.
//
//  Service to sync job data to the macOS widget via App Group container.
//

import Foundation
import WidgetKit

/// App Group identifier for sharing data between main app and widget
private let appGroupIdentifier = "group.com.jkoch.rsyncgui"
private let widgetDataFileName = "widget_data.json"
private let appSupportFolder = "RsyncGUI"

// MARK: - Widget Data Models (Shared with Widget Extension)

/// Summary data for the widget
struct WidgetSyncData: Codable {
    var lastSyncTime: Date?
    var lastSyncStatus: String?
    var lastSyncJobName: String?
    var nextScheduledSync: Date?
    var nextScheduledJobName: String?
    var backupHealthScore: Int
    var backupHealthGrade: String
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
    var status: String
    var filesTransferred: Int
    var bytesTransferred: Int64
}

// MARK: - Widget Data Sync Service

/// Service to sync data between the main RsyncGUI app and the widget
class WidgetDataSyncService {
    static let shared = WidgetDataSyncService()

    /// Serial queue to prevent concurrent saves from racing
    private let saveQueue = DispatchQueue(label: "com.jkoch.rsyncgui.widgetDataSync")

    /// Shared container URL - uses Application Support for non-sandboxed apps
    /// Falls back to App Group container if available
    private var containerURL: URL? {
        // First try App Group (works when properly signed)
        if let groupURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier) {
            return groupURL
        }

        // Fallback to shared Application Support (works for non-sandboxed apps)
        guard let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }
        return appSupport.appendingPathComponent(appSupportFolder, isDirectory: true)
    }

    private var dataFileURL: URL? {
        containerURL?.appendingPathComponent(widgetDataFileName)
    }

    private init() {}

    // MARK: - Load Data

    /// Load current widget data from shared container (serialized to prevent race conditions)
    private func loadWidgetData() -> WidgetSyncData {
        return saveQueue.sync {
            guard let url = dataFileURL else {
                print("[WidgetSync] Failed to get container URL for app group: \(appGroupIdentifier)")
                return WidgetSyncData()
            }

            guard FileManager.default.fileExists(atPath: url.path) else {
                return WidgetSyncData()
            }

            do {
                let data = try Data(contentsOf: url)
                let decoder = JSONDecoder()
                decoder.dateDecodingStrategy = .iso8601
                return try decoder.decode(WidgetSyncData.self, from: data)
            } catch {
                print("[WidgetSync] Failed to load widget data: \(error)")
                return WidgetSyncData()
            }
        }
    }

    // MARK: - Save Data

    /// Save widget data to shared container (serialized to prevent race conditions)
    private func saveWidgetData(_ widgetData: WidgetSyncData) {
        saveQueue.sync {
            guard let url = dataFileURL else {
                print("[WidgetSync] Failed to get container URL for app group: \(appGroupIdentifier)")
                return
            }

            // Ensure container directory exists
            if let containerURL = containerURL {
                try? FileManager.default.createDirectory(at: containerURL, withIntermediateDirectories: true)
            }

            do {
                let encoder = JSONEncoder()
                encoder.dateEncodingStrategy = .iso8601
                encoder.outputFormatting = .prettyPrinted
                let data = try encoder.encode(widgetData)
                try data.write(to: url, options: .atomic)
                print("[WidgetSync] Successfully saved widget data")

                // Reload widget timelines
                WidgetCenter.shared.reloadTimelines(ofKind: "RsyncGUIWidget")
            } catch {
                print("[WidgetSync] Failed to save widget data: \(error)")
            }
        }
    }

    // MARK: - Public API

    /// Update widget after a job execution completes
    func updateAfterJobExecution(
        job: SyncJob,
        result: ExecutionResult
    ) {
        var data = loadWidgetData()

        // Update last sync info
        data.lastSyncTime = result.startTime
        data.lastSyncStatus = result.status.rawValue
        data.lastSyncJobName = job.name

        // Add to recent syncs (keep last 10)
        let recentSync = WidgetRecentSync(
            id: UUID(),
            jobName: job.name,
            timestamp: result.startTime,
            status: result.status.rawValue,
            filesTransferred: result.filesTransferred,
            bytesTransferred: result.bytesTransferred
        )
        data.recentSyncs.insert(recentSync, at: 0)
        if data.recentSyncs.count > 10 {
            data.recentSyncs = Array(data.recentSyncs.prefix(10))
        }

        // Update error tracking
        if result.status == .failed || result.status == .partialSuccess {
            if let index = data.jobsWithErrors.firstIndex(where: { $0.id == job.id }) {
                data.jobsWithErrors[index].lastFailedTime = Date()
                data.jobsWithErrors[index].failureCount += 1
                data.jobsWithErrors[index].errorMessage = result.errors.first ?? "Unknown error"
            } else {
                let jobError = WidgetJobError(
                    id: job.id,
                    jobName: job.name,
                    errorMessage: result.errors.first ?? "Unknown error",
                    lastFailedTime: Date(),
                    failureCount: 1
                )
                data.jobsWithErrors.append(jobError)
            }
        } else if result.status == .success {
            // Clear error for this job if successful
            data.jobsWithErrors.removeAll { $0.id == job.id }
        }

        data.lastUpdated = Date()
        saveWidgetData(data)
    }

    /// Full sync of all job data to widget
    @MainActor
    func syncAllJobData() {
        let jobs = JobManager.shared.jobs
        var data = loadWidgetData()

        // Update job counts
        data.totalJobs = jobs.count
        data.enabledJobs = jobs.filter { $0.isEnabled }.count

        // Find most recent sync
        var lastSync: (date: Date, name: String, status: ExecutionStatus)? = nil
        for job in jobs {
            if let lastRun = job.lastRun, let status = job.lastStatus {
                if lastSync == nil || lastRun > lastSync!.date {
                    lastSync = (lastRun, job.name, status)
                }
            }
        }
        if let last = lastSync {
            data.lastSyncTime = last.date
            data.lastSyncJobName = last.name
            data.lastSyncStatus = last.status.rawValue
        }

        // Find next scheduled sync
        var nextSync: (date: Date, jobName: String)? = nil
        for job in jobs where job.isEnabled {
            if let schedule = job.schedule, schedule.isEnabled {
                if let nextRun = calculateNextRun(for: schedule) {
                    if nextSync == nil || nextRun < nextSync!.date {
                        nextSync = (nextRun, job.name)
                    }
                }
            }
        }
        data.nextScheduledSync = nextSync?.date
        data.nextScheduledJobName = nextSync?.jobName

        // Calculate backup health score
        let (score, grade) = calculateBackupHealthScore(jobs: jobs)
        data.backupHealthScore = score
        data.backupHealthGrade = grade

        // Update jobs with errors
        data.jobsWithErrors = jobs.compactMap { job -> WidgetJobError? in
            guard job.lastStatus == .failed || job.lastStatus == .partialSuccess else {
                return nil
            }
            return WidgetJobError(
                id: job.id,
                jobName: job.name,
                errorMessage: "Last sync \(job.lastStatus?.rawValue ?? "unknown")",
                lastFailedTime: job.lastRun ?? Date(),
                failureCount: job.failedRuns
            )
        }

        data.lastUpdated = Date()
        saveWidgetData(data)
    }

    // MARK: - Helpers

    /// Calculate the next run time for a schedule
    private func calculateNextRun(for schedule: ScheduleConfig) -> Date? {
        guard schedule.isEnabled else { return nil }

        let now = Date()
        let calendar = Calendar.current

        switch schedule.frequency {
        case .manual:
            return nil

        case .hourly:
            // Next hour at minute 0
            var components = calendar.dateComponents([.year, .month, .day, .hour], from: now)
            components.minute = 0
            components.second = 0
            if let date = calendar.date(from: components) {
                return calendar.date(byAdding: .hour, value: 1, to: date)
            }

        case .daily:
            if let scheduleTime = schedule.time {
                let timeComponents = calendar.dateComponents([.hour, .minute], from: scheduleTime)
                var nextRun = calendar.date(bySettingHour: timeComponents.hour ?? 0,
                                           minute: timeComponents.minute ?? 0,
                                           second: 0,
                                           of: now)
                if let next = nextRun, next <= now {
                    nextRun = calendar.date(byAdding: .day, value: 1, to: next)
                }
                return nextRun
            }

        case .weekly:
            if let scheduleTime = schedule.time, let dayOfWeek = schedule.dayOfWeek {
                let timeComponents = calendar.dateComponents([.hour, .minute], from: scheduleTime)
                var dateComponents = DateComponents()
                dateComponents.weekday = dayOfWeek + 1 // Calendar uses 1-7 (Sunday = 1)
                dateComponents.hour = timeComponents.hour
                dateComponents.minute = timeComponents.minute
                return calendar.nextDate(after: now, matching: dateComponents, matchingPolicy: .nextTime)
            }

        case .monthly:
            if let scheduleTime = schedule.time, let dayOfMonth = schedule.dayOfMonth {
                let timeComponents = calendar.dateComponents([.hour, .minute], from: scheduleTime)
                var dateComponents = DateComponents()
                dateComponents.day = dayOfMonth
                dateComponents.hour = timeComponents.hour
                dateComponents.minute = timeComponents.minute
                return calendar.nextDate(after: now, matching: dateComponents, matchingPolicy: .nextTime)
            }

        case .custom:
            // Custom cron - would need parsing, skip for now
            return nil
        }

        return nil
    }

    /// Calculate backup health score based on job status
    private func calculateBackupHealthScore(jobs: [SyncJob]) -> (score: Int, grade: String) {
        guard !jobs.isEmpty else {
            return (0, "?")
        }

        var score = 100

        // Deduct for disabled jobs
        let disabledCount = jobs.filter { !$0.isEnabled }.count
        score -= disabledCount * 5

        // Deduct for failed jobs
        let failedJobs = jobs.filter { $0.lastStatus == .failed }
        score -= failedJobs.count * 15

        // Deduct for partial success
        let partialJobs = jobs.filter { $0.lastStatus == .partialSuccess }
        score -= partialJobs.count * 10

        // Deduct for jobs never run
        let neverRun = jobs.filter { $0.lastRun == nil }
        score -= neverRun.count * 10

        // Deduct for stale backups (no sync in 7 days)
        let sevenDaysAgo = Calendar.current.date(byAdding: .day, value: -7, to: Date())!
        let staleJobs = jobs.filter { job in
            guard let lastRun = job.lastRun else { return false }
            return lastRun < sevenDaysAgo
        }
        score -= staleJobs.count * 5

        // Bonus for scheduled jobs
        let scheduledJobs = jobs.filter { $0.schedule?.isEnabled == true }
        score += min(scheduledJobs.count * 2, 10)

        // Clamp to 0-100
        score = max(0, min(100, score))

        // Calculate grade
        let grade: String
        switch score {
        case 90...100: grade = "A"
        case 80..<90: grade = "B"
        case 70..<80: grade = "C"
        case 60..<70: grade = "D"
        default: grade = "F"
        }

        return (score, grade)
    }

    /// Refresh the widget
    func refreshWidget() {
        WidgetCenter.shared.reloadTimelines(ofKind: "RsyncGUIWidget")
    }
}
