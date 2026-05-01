//
//  DeltaReportTests.swift
//  RsyncGUITests
//
//  Created by Jordan Koch on 4/21/26.
//

import XCTest
@testable import RsyncGUI

final class DeltaReportTests: XCTestCase {

    // MARK: - Initialization

    func testNewDeltaReportIsEmpty() {
        let jobId = UUID()
        let report = DeltaReport(jobId: jobId)

        XCTAssertEqual(report.jobId, jobId)
        XCTAssertTrue(report.filesAdded.isEmpty)
        XCTAssertTrue(report.filesModified.isEmpty)
        XCTAssertTrue(report.filesDeleted.isEmpty)
        XCTAssertEqual(report.filesSkipped, 0)
        XCTAssertEqual(report.bytesAdded, 0)
        XCTAssertEqual(report.bytesModified, 0)
        XCTAssertEqual(report.bytesDeleted, 0)
        XCTAssertEqual(report.totalChanges, 0)
        XCTAssertFalse(report.hasChanges)
    }

    // MARK: - Summary

    func testSummaryWithNoChanges() {
        let report = DeltaReport(jobId: UUID())
        XCTAssertEqual(report.summary, "No changes")
    }

    func testSummaryWithAddedFiles() {
        var report = DeltaReport(jobId: UUID())
        report.filesAdded = ["file1.txt", "file2.txt"]

        XCTAssertTrue(report.summary.contains("2 added"))
    }

    func testSummaryWithModifiedFiles() {
        var report = DeltaReport(jobId: UUID())
        report.filesModified = ["config.json"]

        XCTAssertTrue(report.summary.contains("1 modified"))
    }

    func testSummaryWithDeletedFiles() {
        var report = DeltaReport(jobId: UUID())
        report.filesDeleted = ["old1.txt", "old2.txt", "old3.txt"]

        XCTAssertTrue(report.summary.contains("3 deleted"))
    }

    func testSummaryWithSkippedFiles() {
        var report = DeltaReport(jobId: UUID())
        report.filesSkipped = 10

        XCTAssertTrue(report.summary.contains("10 skipped"))
    }

    func testSummaryWithMixedChanges() {
        var report = DeltaReport(jobId: UUID())
        report.filesAdded = ["new.txt"]
        report.filesModified = ["updated.txt"]
        report.filesDeleted = ["removed.txt"]

        let summary = report.summary
        XCTAssertTrue(summary.contains("1 added"))
        XCTAssertTrue(summary.contains("1 modified"))
        XCTAssertTrue(summary.contains("1 deleted"))
    }

    // MARK: - Total Changes

    func testTotalChangesIsSum() {
        var report = DeltaReport(jobId: UUID())
        report.filesAdded = ["a", "b"]
        report.filesModified = ["c"]
        report.filesDeleted = ["d", "e", "f"]

        XCTAssertEqual(report.totalChanges, 6)
        XCTAssertTrue(report.hasChanges)
    }

    // MARK: - Copyable Report

    func testCopyableReportContainsAllSections() {
        var report = DeltaReport(jobId: UUID())
        report.filesAdded = ["new_file.txt"]
        report.filesModified = ["changed_file.txt"]
        report.filesDeleted = ["old_file.txt"]
        report.filesSkipped = 5
        report.bytesAdded = 1024

        let text = report.copyableReport

        XCTAssertTrue(text.contains("Delta Report"))
        XCTAssertTrue(text.contains("Files Added: 1"))
        XCTAssertTrue(text.contains("Files Modified: 1"))
        XCTAssertTrue(text.contains("Files Deleted: 1"))
        XCTAssertTrue(text.contains("Files Skipped: 5"))
        XCTAssertTrue(text.contains("Added Files"))
        XCTAssertTrue(text.contains("new_file.txt"))
        XCTAssertTrue(text.contains("Modified Files"))
        XCTAssertTrue(text.contains("changed_file.txt"))
        XCTAssertTrue(text.contains("Deleted Files"))
        XCTAssertTrue(text.contains("old_file.txt"))
        XCTAssertTrue(text.contains("End of Report"))
    }

    func testCopyableReportTruncatesLargeFileLists() {
        var report = DeltaReport(jobId: UUID())
        report.filesAdded = (1...150).map { "file\($0).txt" }

        let text = report.copyableReport

        XCTAssertTrue(text.contains("file1.txt"), "First file should be listed")
        XCTAssertTrue(text.contains("file100.txt"), "100th file should be listed")
        XCTAssertTrue(text.contains("... and 50 more"), "Should indicate truncated count")
    }

    // MARK: - Delta Report Parsing (via AdvancedExecutionService)

    func testParseNewFilesFromItemizeOutput() {
        let service = AdvancedExecutionService.shared
        let jobId = UUID()

        let output = """
        >f+++++++++ documents/new_file.txt
        >f+++++++++ photos/vacation/img001.jpg
        >f+++++++++ config/settings.json
        """

        let report = service.generateDeltaReport(from: output, jobId: jobId)

        XCTAssertEqual(report.filesAdded.count, 3)
        XCTAssertTrue(report.filesAdded.contains("documents/new_file.txt"))
        XCTAssertTrue(report.filesAdded.contains("photos/vacation/img001.jpg"))
        XCTAssertTrue(report.filesAdded.contains("config/settings.json"))
    }

    func testParseModifiedFilesFromItemizeOutput() {
        let service = AdvancedExecutionService.shared
        let jobId = UUID()

        let output = """
        >f.st...... documents/updated.txt
        >f..t...... config/config.json
        """

        let report = service.generateDeltaReport(from: output, jobId: jobId)

        XCTAssertEqual(report.filesModified.count, 2)
    }

    func testParseDeletedFilesFromItemizeOutput() {
        let service = AdvancedExecutionService.shared
        let jobId = UUID()

        let output = """
        *deleting   old_file.txt
        *deleting   archive/legacy.zip
        """

        let report = service.generateDeltaReport(from: output, jobId: jobId)

        XCTAssertEqual(report.filesDeleted.count, 2)
    }

    func testParseSentBytesFromOutput() {
        let service = AdvancedExecutionService.shared
        let jobId = UUID()

        let output = """
        sent 123,456 bytes  received 789 bytes  234.56 bytes/sec
        """

        let report = service.generateDeltaReport(from: output, jobId: jobId)

        XCTAssertEqual(report.bytesAdded, 123456)
    }

    func testParseMixedOutput() {
        let service = AdvancedExecutionService.shared
        let jobId = UUID()

        let output = """
        sending incremental file list
        >f+++++++++ new_document.pdf
        >f.st...... modified_script.sh
        *deleting   obsolete_data.csv

        sent 45,678 bytes  received 123 bytes  456.78 bytes/sec
        total size is 1,234,567  speedup is 27.00
        """

        let report = service.generateDeltaReport(from: output, jobId: jobId)

        XCTAssertEqual(report.filesAdded.count, 1)
        XCTAssertEqual(report.filesModified.count, 1)
        XCTAssertEqual(report.filesDeleted.count, 1)
        XCTAssertEqual(report.totalChanges, 3)
        XCTAssertTrue(report.hasChanges)
        XCTAssertEqual(report.bytesAdded, 45678)
    }

    func testParseEmptyOutput() {
        let service = AdvancedExecutionService.shared
        let jobId = UUID()

        let report = service.generateDeltaReport(from: "", jobId: jobId)

        XCTAssertEqual(report.totalChanges, 0)
        XCTAssertFalse(report.hasChanges)
    }

    // MARK: - Codable

    func testDeltaReportCodableRoundtrip() throws {
        var report = DeltaReport(jobId: UUID())
        report.filesAdded = ["a.txt", "b.txt"]
        report.filesModified = ["c.txt"]
        report.filesDeleted = ["d.txt"]
        report.filesSkipped = 3
        report.bytesAdded = 1024
        report.bytesModified = 512
        report.bytesDeleted = 256

        let data = try JSONEncoder().encode(report)
        let decoded = try JSONDecoder().decode(DeltaReport.self, from: data)

        XCTAssertEqual(decoded.filesAdded, report.filesAdded)
        XCTAssertEqual(decoded.filesModified, report.filesModified)
        XCTAssertEqual(decoded.filesDeleted, report.filesDeleted)
        XCTAssertEqual(decoded.filesSkipped, report.filesSkipped)
        XCTAssertEqual(decoded.bytesAdded, report.bytesAdded)
        XCTAssertEqual(decoded.bytesModified, report.bytesModified)
        XCTAssertEqual(decoded.bytesDeleted, report.bytesDeleted)
    }
}
