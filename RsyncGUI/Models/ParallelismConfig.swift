//
//  ParallelismConfig.swift
//  RsyncGUI
//
//  Created by Jordan Koch on 1/14/26.
//

import Foundation

/// Configuration for parallel rsync execution (for tons of tiny files)
struct ParallelismConfig: Codable {
    var isEnabled: Bool
    var numberOfThreads: Int // Number of parallel rsync processes
    var filesPerThread: Int? // Split work by file count (auto-calculated if nil)
    var strategy: ParallelStrategy

    init() {
        self.isEnabled = false
        self.numberOfThreads = 4 // Default to 4 parallel processes
        self.filesPerThread = nil
        self.strategy = .automatic
    }
}

/// Strategy for splitting work across parallel processes
enum ParallelStrategy: String, Codable, CaseIterable {
    case automatic = "Automatic (Smart Split)"
    case bySize = "By File Size"
    case byCount = "By File Count"
    case byDirectory = "By Directory"

    var description: String {
        switch self {
        case .automatic:
            return "Automatically choose best split method based on file analysis"
        case .bySize:
            return "Split so each thread gets roughly equal data size"
        case .byCount:
            return "Split so each thread gets equal number of files"
        case .byDirectory:
            return "Assign directories to different threads"
        }
    }
}

/// Parallel execution result tracking
struct ParallelExecutionResult {
    var threadResults: [ThreadResult]
    var totalDuration: TimeInterval
    var averageSpeed: Double
    var peakSpeed: Double

    struct ThreadResult {
        var threadId: Int
        var filesTransferred: Int
        var bytesTransferred: Int64
        var duration: TimeInterval
        var errors: [String]
    }

    var totalFilesTransferred: Int {
        threadResults.reduce(0) { $0 + $1.filesTransferred }
    }

    var totalBytesTransferred: Int64 {
        threadResults.reduce(0) { $0 + $1.bytesTransferred }
    }

    var hadErrors: Bool {
        threadResults.contains { !$0.errors.isEmpty }
    }
}
