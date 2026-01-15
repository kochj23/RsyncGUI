//
//  SyncJob.swift
//  RsyncGUI
//
//  Created by Jordan Koch on 1/14/26.
//

import Foundation

/// Represents a complete rsync synchronization job
struct SyncJob: Identifiable, Codable {
    var id: UUID
    var name: String
    var source: String
    var destination: String
    var isRemote: Bool
    var remoteHost: String?
    var remoteUser: String?
    var sshKeyPath: String?

    // Rsync options
    var options: RsyncOptions

    // Parallelism for tiny files
    var parallelism: ParallelismConfig?

    // Job dependencies
    var dependencies: [UUID] // Job IDs that must complete successfully before this job runs
    var runOnlyIfChanged: Bool // Only run if source has changed since last run
    var lastSourceChecksum: String? // Checksum of source for change detection

    // Scheduling
    var schedule: ScheduleConfig?
    var isEnabled: Bool

    // Metadata
    var created: Date
    var lastRun: Date?
    var lastStatus: ExecutionStatus?
    var lastDeltaReport: DeltaReport?

    // Statistics
    var totalRuns: Int
    var successfulRuns: Int
    var failedRuns: Int

    init(name: String, source: String, destination: String) {
        self.id = UUID()
        self.name = name
        self.source = source
        self.destination = destination
        self.isRemote = false
        self.options = RsyncOptions()
        self.dependencies = []
        self.runOnlyIfChanged = false
        self.isEnabled = true
        self.created = Date()
        self.totalRuns = 0
        self.successfulRuns = 0
        self.failedRuns = 0
    }
}

/// Execution status
enum ExecutionStatus: String, Codable {
    case success
    case failed
    case partialSuccess
    case cancelled
}

/// Execution result with detailed statistics
struct ExecutionResult: Identifiable, Codable {
    var id: UUID
    var jobId: UUID
    var startTime: Date
    var endTime: Date?
    var status: ExecutionStatus
    var filesTransferred: Int
    var bytesTransferred: Int64
    var errors: [String]
    var output: String

    var duration: TimeInterval {
        guard let end = endTime else { return 0 }
        return end.timeIntervalSince(startTime)
    }

    var transferSpeed: Double {
        guard duration > 0 else { return 0 }
        return Double(bytesTransferred) / duration
    }
}
