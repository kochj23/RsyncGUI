//
//  SharedDataManager.swift
//  RsyncGUI Widget
//
//  Created by Jordan Koch on 2/4/26.
//

import Foundation
import WidgetKit

/// Manages data sharing between the main app and widget
/// Uses a shared Application Support location since the app is non-sandboxed
class SharedDataManager {
    static let shared = SharedDataManager()

    private let dataFileName = "widget_data.json"
    private let appSupportFolder = "RsyncGUI"

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
        containerURL?.appendingPathComponent(dataFileName)
    }

    private init() {}

    // MARK: - Read Data

    /// Load widget data from shared container
    func loadWidgetData() -> WidgetSyncData {
        guard let url = dataFileURL else {
            print("[Widget] Failed to get data file URL")
            return WidgetSyncData()
        }

        guard FileManager.default.fileExists(atPath: url.path) else {
            print("[Widget] Widget data file does not exist yet at: \(url.path)")
            return WidgetSyncData()
        }

        do {
            let data = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let widgetData = try decoder.decode(WidgetSyncData.self, from: data)
            print("[Widget] Successfully loaded widget data, last updated: \(widgetData.lastUpdated)")
            return widgetData
        } catch {
            print("[Widget] Failed to load widget data: \(error)")
            return WidgetSyncData()
        }
    }

    // MARK: - Write Data

    /// Save widget data to shared container (called from main app)
    func saveWidgetData(_ widgetData: WidgetSyncData) {
        guard let url = dataFileURL else {
            print("[SharedData] Failed to get data file URL")
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
            print("[SharedData] Successfully saved widget data to: \(url.path)")

            // Reload widget timelines
            WidgetCenter.shared.reloadAllTimelines()
        } catch {
            print("[SharedData] Failed to save widget data: \(error)")
        }
    }

    // MARK: - Update Helpers

    /// Update widget data from job execution result
    func updateAfterExecution(
        jobId: UUID,
        jobName: String,
        status: String,
        filesTransferred: Int,
        bytesTransferred: Int64,
        errors: [String]
    ) {
        var data = loadWidgetData()

        // Update last sync info
        data.lastSyncTime = Date()
        data.lastSyncStatus = status
        data.lastSyncJobName = jobName

        // Add to recent syncs (keep last 10)
        let recentSync = WidgetRecentSync(
            id: UUID(),
            jobName: jobName,
            timestamp: Date(),
            status: status,
            filesTransferred: filesTransferred,
            bytesTransferred: bytesTransferred
        )
        data.recentSyncs.insert(recentSync, at: 0)
        if data.recentSyncs.count > 10 {
            data.recentSyncs = Array(data.recentSyncs.prefix(10))
        }

        // Update error tracking if failed
        if status == "failed" || status == "partialSuccess" {
            if let index = data.jobsWithErrors.firstIndex(where: { $0.jobName == jobName }) {
                data.jobsWithErrors[index].lastFailedTime = Date()
                data.jobsWithErrors[index].failureCount += 1
                data.jobsWithErrors[index].errorMessage = errors.first ?? "Unknown error"
            } else {
                let jobError = WidgetJobError(
                    id: jobId,
                    jobName: jobName,
                    errorMessage: errors.first ?? "Unknown error",
                    lastFailedTime: Date(),
                    failureCount: 1
                )
                data.jobsWithErrors.append(jobError)
            }
        } else if status == "success" {
            // Remove from errors if successful
            data.jobsWithErrors.removeAll { $0.jobName == jobName }
        }

        data.lastUpdated = Date()
        saveWidgetData(data)
    }

    /// Update widget data with full job list and schedules
    func updateJobsAndSchedules(
        jobs: [(id: UUID, name: String, isEnabled: Bool, lastRun: Date?, lastStatus: String?, schedule: (nextRun: Date?, frequency: String)?)],
        backupHealthScore: Int,
        backupHealthGrade: String
    ) {
        var data = loadWidgetData()

        data.totalJobs = jobs.count
        data.enabledJobs = jobs.filter { $0.isEnabled }.count
        data.backupHealthScore = backupHealthScore
        data.backupHealthGrade = backupHealthGrade

        // Find next scheduled sync
        var nextSync: (date: Date, jobName: String)? = nil
        for job in jobs {
            if let schedule = job.schedule, let nextRun = schedule.nextRun {
                if nextSync == nil || nextRun < nextSync!.date {
                    nextSync = (nextRun, job.name)
                }
            }
        }
        data.nextScheduledSync = nextSync?.date
        data.nextScheduledJobName = nextSync?.jobName

        // Find most recent sync
        var lastSync: (date: Date, name: String, status: String)? = nil
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
            data.lastSyncStatus = last.status
        }

        data.lastUpdated = Date()
        saveWidgetData(data)
    }

    /// Force refresh the widget
    func refreshWidget() {
        WidgetCenter.shared.reloadAllTimelines()
    }
}

// MARK: - Widget Refresh Extension

extension WidgetCenter {
    /// Reload RsyncGUI widget timelines
    static func reloadRsyncGUIWidgets() {
        shared.reloadTimelines(ofKind: "RsyncGUIWidget")
    }
}
