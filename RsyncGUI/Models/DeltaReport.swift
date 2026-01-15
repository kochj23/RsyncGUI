//
//  DeltaReport.swift
//  RsyncGUI
//
//  Created by Jordan Koch on 1/14/26.
//

import Foundation

/// Report of what changed during a sync operation
struct DeltaReport: Codable, Identifiable {
    var id: UUID
    var timestamp: Date
    var jobId: UUID

    // Change statistics
    var filesAdded: [String]
    var filesModified: [String]
    var filesDeleted: [String]
    var filesSkipped: Int

    // Size statistics
    var bytesAdded: Int64
    var bytesModified: Int64
    var bytesDeleted: Int64

    // Summary
    var totalChanges: Int {
        filesAdded.count + filesModified.count + filesDeleted.count
    }

    var hasChanges: Bool {
        totalChanges > 0
    }

    init(jobId: UUID) {
        self.id = UUID()
        self.timestamp = Date()
        self.jobId = jobId
        self.filesAdded = []
        self.filesModified = []
        self.filesDeleted = []
        self.filesSkipped = 0
        self.bytesAdded = 0
        self.bytesModified = 0
        self.bytesDeleted = 0
    }

    /// Human-readable summary
    var summary: String {
        var parts: [String] = []

        if !filesAdded.isEmpty {
            parts.append("\(filesAdded.count) added")
        }
        if !filesModified.isEmpty {
            parts.append("\(filesModified.count) modified")
        }
        if !filesDeleted.isEmpty {
            parts.append("\(filesDeleted.count) deleted")
        }
        if filesSkipped > 0 {
            parts.append("\(filesSkipped) skipped")
        }

        return parts.isEmpty ? "No changes" : parts.joined(separator: ", ")
    }

    /// Copyable text report
    var copyableReport: String {
        var report = """
        === Delta Report ===
        Job: \(jobId)
        Timestamp: \(timestamp.formatted(date: .long, time: .complete))

        Summary:
        - Files Added: \(filesAdded.count)
        - Files Modified: \(filesModified.count)
        - Files Deleted: \(filesDeleted.count)
        - Files Skipped: \(filesSkipped)

        Data Transfer:
        - Added: \(ByteCountFormatter.string(fromByteCount: bytesAdded, countStyle: .binary))
        - Modified: \(ByteCountFormatter.string(fromByteCount: bytesModified, countStyle: .binary))
        - Deleted: \(ByteCountFormatter.string(fromByteCount: bytesDeleted, countStyle: .binary))

        """

        if !filesAdded.isEmpty {
            report += "\n=== Added Files ===\n"
            for file in filesAdded.prefix(100) {
                report += "  + \(file)\n"
            }
            if filesAdded.count > 100 {
                report += "  ... and \(filesAdded.count - 100) more\n"
            }
        }

        if !filesModified.isEmpty {
            report += "\n=== Modified Files ===\n"
            for file in filesModified.prefix(100) {
                report += "  * \(file)\n"
            }
            if filesModified.count > 100 {
                report += "  ... and \(filesModified.count - 100) more\n"
            }
        }

        if !filesDeleted.isEmpty {
            report += "\n=== Deleted Files ===\n"
            for file in filesDeleted.prefix(100) {
                report += "  - \(file)\n"
            }
            if filesDeleted.count > 100 {
                report += "  ... and \(filesDeleted.count - 100) more\n"
            }
        }

        report += "\n=== End of Report ===\n"
        return report
    }
}
