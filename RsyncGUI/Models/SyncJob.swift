//
//  SyncJob.swift
//  RsyncGUI
//
//  Created by Jordan Koch on 1/14/26.
//

import Foundation

/// Destination type for sync jobs
enum DestinationType: String, Codable {
    case local = "Local Folder"
    case remoteSSH = "Remote Server (SSH)"
    case iCloudDrive = "iCloud Drive"
}

/// Represents a single destination with its configuration
struct SyncDestination: Identifiable, Codable, Equatable {
    var id: UUID
    var path: String
    var type: DestinationType
    var remoteHost: String?
    var remoteUser: String?
    var sshKeyPath: String?
    var bookmark: Data?
    var isEnabled: Bool

    init(path: String = "", type: DestinationType = .local) {
        self.id = UUID()
        self.path = path
        self.type = type
        self.isEnabled = true
    }

    static func == (lhs: SyncDestination, rhs: SyncDestination) -> Bool {
        lhs.id == rhs.id
    }
}

/// Represents a complete rsync synchronization job
struct SyncJob: Identifiable, Codable {
    var id: UUID
    var name: String

    // Multiple sources support (new)
    var sources: [String]

    // Multiple destinations support (new)
    var destinations: [SyncDestination]

    // Legacy single source/destination for backward compatibility
    var source: String {
        get { sources.first ?? "" }
        set {
            if sources.isEmpty {
                sources = [newValue]
            } else {
                sources[0] = newValue
            }
        }
    }

    var destination: String {
        get { destinations.first?.path ?? "" }
        set {
            if destinations.isEmpty {
                destinations = [SyncDestination(path: newValue)]
            } else {
                destinations[0].path = newValue
            }
        }
    }

    var destinationType: DestinationType? {
        get { destinations.first?.type }
        set {
            if !destinations.isEmpty, let type = newValue {
                destinations[0].type = type
            }
        }
    }

    var isRemote: Bool {
        get { destinations.first?.type == .remoteSSH }
        set {
            if !destinations.isEmpty {
                destinations[0].type = newValue ? .remoteSSH : .local
            }
        }
    }

    var remoteHost: String? {
        get { destinations.first?.remoteHost }
        set {
            if !destinations.isEmpty {
                destinations[0].remoteHost = newValue
            }
        }
    }

    var remoteUser: String? {
        get { destinations.first?.remoteUser }
        set {
            if !destinations.isEmpty {
                destinations[0].remoteUser = newValue
            }
        }
    }

    var sshKeyPath: String? {
        get { destinations.first?.sshKeyPath }
        set {
            if !destinations.isEmpty {
                destinations[0].sshKeyPath = newValue
            }
        }
    }

    // Security-scoped bookmark for sandbox permission persistence
    var destinationBookmark: Data? {
        get { destinations.first?.bookmark }
        set {
            if !destinations.isEmpty {
                destinations[0].bookmark = newValue
            }
        }
    }

    // Computed property for safe destination type access (handles migration)
    var effectiveDestinationType: DestinationType {
        get {
            if let type = destinationType {
                return type
            }
            // Migration: Use isRemote to determine type for old jobs
            return isRemote ? .remoteSSH : .local
        }
        set {
            destinationType = newValue
            // Keep isRemote in sync for backwards compatibility
            isRemote = (newValue == .remoteSSH)
        }
    }

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

    init(name: String, source: String, destination: String, destinationType: DestinationType = .local) {
        self.id = UUID()
        self.name = name
        self.sources = [source]
        self.destinations = [SyncDestination(path: destination, type: destinationType)]
        self.options = RsyncOptions()
        self.dependencies = []
        self.runOnlyIfChanged = false
        self.isEnabled = true
        self.created = Date()
        self.totalRuns = 0
        self.successfulRuns = 0
        self.failedRuns = 0
    }

    /// Initialize with multiple sources and destinations
    init(name: String, sources: [String], destinations: [SyncDestination]) {
        self.id = UUID()
        self.name = name
        self.sources = sources.isEmpty ? [""] : sources
        self.destinations = destinations.isEmpty ? [SyncDestination()] : destinations
        self.options = RsyncOptions()
        self.dependencies = []
        self.runOnlyIfChanged = false
        self.isEnabled = true
        self.created = Date()
        self.totalRuns = 0
        self.successfulRuns = 0
        self.failedRuns = 0
    }

    /// Get iCloud Drive path
    static var iCloudDrivePath: String {
        let homeDir = FileManager.default.homeDirectoryForCurrentUser.path
        return "\(homeDir)/Library/Mobile Documents/com~apple~CloudDocs"
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
