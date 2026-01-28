//
//  ExecutionHistory.swift
//  RsyncGUI
//
//  Created by Jordan Koch on 1/14/26.
//

import Foundation

/// Manager for execution history storage and retrieval
class ExecutionHistoryManager {
    static let shared = ExecutionHistoryManager()

    private let storageURL: URL
    private let maxHistoryEntries = 1000 // Keep last 1000 executions

    private init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        storageURL = appSupport.appendingPathComponent("RsyncGUI/History", isDirectory: true)
        try? FileManager.default.createDirectory(at: storageURL, withIntermediateDirectories: true)
    }

    // MARK: - Add History

    func addExecution(_ result: ExecutionResult, jobName: String) {
        let entry = ExecutionHistoryEntry(
            result: result,
            jobName: jobName
        )

        // Load existing history
        var history = loadAllHistory()

        // Add new entry
        history.append(entry)

        // Keep only last N entries
        if history.count > maxHistoryEntries {
            history = Array(history.suffix(maxHistoryEntries))
        }

        // Save
        saveHistory(history)
    }

    // MARK: - Query History

    func getHistory(for jobId: UUID, limit: Int = 50) -> [ExecutionHistoryEntry] {
        let all = loadAllHistory()
        return all.filter { $0.jobId == jobId }.suffix(limit).reversed()
    }

    func getAllHistory(limit: Int = 100) -> [ExecutionHistoryEntry] {
        let all = loadAllHistory()
        return Array(all.suffix(limit).reversed())
    }

    func getRecentHistory(days: Int = 7) -> [ExecutionHistoryEntry] {
        let cutoffDate = Calendar.current.date(byAdding: .day, value: -days, to: Date())!
        let all = loadAllHistory()
        return all.filter { $0.timestamp >= cutoffDate }.reversed()
    }

    // MARK: - Clear History

    /// Clear all execution history
    func clearHistory() {
        saveHistory([])
    }

    /// Clear history for a specific job
    func clearHistory(for jobId: UUID) {
        var history = loadAllHistory()
        history.removeAll { $0.jobId == jobId }
        saveHistory(history)
    }

    // MARK: - Export

    func exportToCSV() -> String {
        let history = loadAllHistory()

        var csv = "Timestamp,Job ID,Job Name,Status,Files Transferred,Bytes Transferred,Duration,Errors\n"

        for entry in history {
            let timestamp = entry.timestamp.formatted(date: .numeric, time: .shortened)
            let jobId = entry.jobId.uuidString
            let jobName = entry.jobName.replacingOccurrences(of: ",", with: ";")
            let status = entry.status.rawValue
            let files = entry.filesTransferred
            let bytes = entry.bytesTransferred
            let duration = String(format: "%.2f", entry.duration)
            let errors = entry.errors.isEmpty ? "None" : "\(entry.errors.count) errors"

            csv += "\(timestamp),\(jobId),\(jobName),\(status),\(files),\(bytes),\(duration),\(errors)\n"
        }

        return csv
    }

    // MARK: - Storage

    private func loadAllHistory() -> [ExecutionHistoryEntry] {
        let historyFile = storageURL.appendingPathComponent("history.json")

        guard FileManager.default.fileExists(atPath: historyFile.path),
              let data = try? Data(contentsOf: historyFile),
              let history = try? JSONDecoder().decode([ExecutionHistoryEntry].self, from: data) else {
            return []
        }

        return history
    }

    private func saveHistory(_ history: [ExecutionHistoryEntry]) {
        let historyFile = storageURL.appendingPathComponent("history.json")

        guard let data = try? JSONEncoder().encode(history) else {
            print("Failed to encode history")
            return
        }

        try? data.write(to: historyFile, options: .atomic)
    }
}

/// Single execution history entry
struct ExecutionHistoryEntry: Codable, Identifiable {
    var id: UUID
    var jobId: UUID
    var jobName: String
    var timestamp: Date
    var status: ExecutionStatus
    var filesTransferred: Int
    var bytesTransferred: Int64
    var duration: TimeInterval
    var errors: [String]

    init(result: ExecutionResult, jobName: String) {
        self.id = result.id
        self.jobId = result.jobId
        self.jobName = jobName
        self.timestamp = result.startTime
        self.status = result.status
        self.filesTransferred = result.filesTransferred
        self.bytesTransferred = result.bytesTransferred
        self.duration = result.duration
        self.errors = result.errors
    }
}
