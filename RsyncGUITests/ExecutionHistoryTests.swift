//
//  ExecutionHistoryTests.swift
//  RsyncGUITests
//
//  Created by Jordan Koch on 4/21/26.
//

import XCTest
@testable import RsyncGUI

final class ExecutionHistoryTests: XCTestCase {

    // MARK: - ExecutionHistoryEntry

    func testExecutionHistoryEntryFromResult() {
        let jobId = UUID()
        let resultId = UUID()
        let start = Date()
        let end = start.addingTimeInterval(60)

        let result = ExecutionResult(
            id: resultId,
            jobId: jobId,
            startTime: start,
            endTime: end,
            status: .success,
            filesTransferred: 42,
            bytesTransferred: 123456,
            errors: ["minor warning"],
            output: "test output"
        )

        let entry = ExecutionHistoryEntry(result: result, jobName: "Test Job")

        XCTAssertEqual(entry.id, resultId)
        XCTAssertEqual(entry.jobId, jobId)
        XCTAssertEqual(entry.jobName, "Test Job")
        XCTAssertEqual(entry.timestamp, start)
        XCTAssertEqual(entry.status, .success)
        XCTAssertEqual(entry.filesTransferred, 42)
        XCTAssertEqual(entry.bytesTransferred, 123456)
        XCTAssertEqual(entry.duration, 60, accuracy: 0.001)
        XCTAssertEqual(entry.errors.count, 1)
        XCTAssertEqual(entry.errors.first, "minor warning")
    }

    func testExecutionHistoryEntryCodable() throws {
        let result = ExecutionResult(
            id: UUID(),
            jobId: UUID(),
            startTime: Date(),
            endTime: Date().addingTimeInterval(30),
            status: .partialSuccess,
            filesTransferred: 10,
            bytesTransferred: 5000,
            errors: ["error 1", "error 2"],
            output: ""
        )

        let entry = ExecutionHistoryEntry(result: result, jobName: "Codable Test")

        let data = try JSONEncoder().encode(entry)
        let decoded = try JSONDecoder().decode(ExecutionHistoryEntry.self, from: data)

        XCTAssertEqual(decoded.id, entry.id)
        XCTAssertEqual(decoded.jobId, entry.jobId)
        XCTAssertEqual(decoded.jobName, entry.jobName)
        XCTAssertEqual(decoded.status, entry.status)
        XCTAssertEqual(decoded.filesTransferred, entry.filesTransferred)
        XCTAssertEqual(decoded.bytesTransferred, entry.bytesTransferred)
        XCTAssertEqual(decoded.errors, entry.errors)
    }

    // MARK: - ExecutionResult Properties

    func testExecutionResultDurationWithNoEndTime() {
        let result = ExecutionResult(
            id: UUID(),
            jobId: UUID(),
            startTime: Date(),
            endTime: nil,
            status: .success,
            filesTransferred: 0,
            bytesTransferred: 0,
            errors: [],
            output: ""
        )

        XCTAssertEqual(result.duration, 0)
        XCTAssertEqual(result.transferSpeed, 0)
    }

    func testExecutionResultTransferSpeed() {
        let start = Date()
        let end = start.addingTimeInterval(10)

        let result = ExecutionResult(
            id: UUID(),
            jobId: UUID(),
            startTime: start,
            endTime: end,
            status: .success,
            filesTransferred: 100,
            bytesTransferred: 10_000_000,  // 10 MB in 10 seconds = 1 MB/s
            errors: [],
            output: ""
        )

        XCTAssertEqual(result.transferSpeed, 1_000_000, accuracy: 1)
    }

    func testExecutionResultZeroDurationSpeed() {
        let now = Date()

        let result = ExecutionResult(
            id: UUID(),
            jobId: UUID(),
            startTime: now,
            endTime: now,  // Same time = 0 duration
            status: .success,
            filesTransferred: 100,
            bytesTransferred: 10_000_000,
            errors: [],
            output: ""
        )

        XCTAssertEqual(result.transferSpeed, 0,
                       "Zero duration should return zero speed, not infinity")
    }

    // MARK: - ConnectionTest Models

    func testConnectionCheckModel() {
        let check = ConnectionCheck(
            name: "SSH Connection",
            passed: true,
            message: "Connected successfully"
        )

        XCTAssertEqual(check.name, "SSH Connection")
        XCTAssertTrue(check.passed)
        XCTAssertEqual(check.message, "Connected successfully")
    }

    func testTestConnectionResult() {
        let checks = [
            ConnectionCheck(name: "DNS Resolution", passed: true, message: "OK"),
            ConnectionCheck(name: "SSH Auth", passed: false, message: "Key rejected"),
            ConnectionCheck(name: "Rsync Available", passed: true, message: "v3.2.7"),
        ]

        let result = TestConnectionResult(
            checks: checks,
            overallSuccess: false
        )

        XCTAssertEqual(result.summary, "2 / 3 checks passed")
        XCTAssertFalse(result.overallSuccess)
    }

    func testTestConnectionResultAllPassed() {
        let checks = [
            ConnectionCheck(name: "Check 1", passed: true, message: "OK"),
            ConnectionCheck(name: "Check 2", passed: true, message: "OK"),
        ]

        let result = TestConnectionResult(checks: checks, overallSuccess: true)

        XCTAssertEqual(result.summary, "2 / 2 checks passed")
        XCTAssertTrue(result.overallSuccess)
    }

    func testTestConnectionResultEmpty() {
        let result = TestConnectionResult(checks: [], overallSuccess: true)

        XCTAssertEqual(result.summary, "0 / 0 checks passed")
    }

    // MARK: - RsyncProgress

    func testRsyncProgressSpeedFormatted() {
        let progress = RsyncProgress(
            currentFile: "test.txt",
            filesTransferred: 10,
            totalFiles: 100,
            bytesTransferred: 1_048_576,
            totalBytes: 10_485_760,
            percentage: 50.0,
            overallPercentage: 10.0,
            speed: 1_048_576,  // 1 MB/s
            timeRemaining: 90
        )

        XCTAssertFalse(progress.speedFormatted.isEmpty)
        XCTAssertTrue(progress.speedFormatted.hasSuffix("/s"))
    }

    func testRsyncProgressTimeRemainingFormatted() {
        var progress = RsyncProgress(
            currentFile: "",
            filesTransferred: 0,
            totalFiles: 0,
            bytesTransferred: 0,
            totalBytes: 0,
            percentage: 0,
            overallPercentage: 0,
            speed: 0,
            timeRemaining: 3661  // 1 hour, 1 minute, 1 second
        )

        XCTAssertEqual(progress.timeRemainingFormatted, "1:01:01")

        progress.timeRemaining = 65  // 1 minute, 5 seconds
        XCTAssertEqual(progress.timeRemainingFormatted, "1:05")

        progress.timeRemaining = 0
        XCTAssertEqual(progress.timeRemainingFormatted, "0:00")
    }

    func testRsyncProgressBytesFormatted() {
        let progress = RsyncProgress(
            currentFile: "large_file.iso",
            filesTransferred: 1,
            totalFiles: 1,
            bytesTransferred: 1_073_741_824,  // 1 GB
            totalBytes: 4_294_967_296,         // 4 GB
            percentage: 25.0,
            overallPercentage: 25.0,
            speed: 10_485_760,
            timeRemaining: 300
        )

        XCTAssertFalse(progress.bytesTransferredFormatted.isEmpty)
        XCTAssertFalse(progress.totalBytesFormatted.isEmpty)
    }

    // MARK: - ParallelismConfig

    func testParallelismConfigDefaults() {
        let config = ParallelismConfig()

        XCTAssertFalse(config.isEnabled)
        XCTAssertEqual(config.numberOfThreads, 4)
        XCTAssertNil(config.filesPerThread)
        XCTAssertEqual(config.strategy, .automatic)
    }

    func testParallelStrategyAllCases() {
        let cases = ParallelStrategy.allCases
        XCTAssertEqual(cases.count, 4)

        for strategy in cases {
            XCTAssertFalse(strategy.description.isEmpty,
                           "Strategy \(strategy.rawValue) should have a description")
        }
    }

    func testParallelismConfigCodable() throws {
        var config = ParallelismConfig()
        config.isEnabled = true
        config.numberOfThreads = 8
        config.filesPerThread = 1000
        config.strategy = .byDirectory

        let data = try JSONEncoder().encode(config)
        let decoded = try JSONDecoder().decode(ParallelismConfig.self, from: data)

        XCTAssertEqual(decoded.isEnabled, true)
        XCTAssertEqual(decoded.numberOfThreads, 8)
        XCTAssertEqual(decoded.filesPerThread, 1000)
        XCTAssertEqual(decoded.strategy, .byDirectory)
    }

    // MARK: - ParallelExecutionResult

    func testParallelExecutionResultAggregation() {
        let result = ParallelExecutionResult(
            threadResults: [
                .init(threadId: 0, filesTransferred: 100, bytesTransferred: 1000, duration: 10, errors: []),
                .init(threadId: 1, filesTransferred: 200, bytesTransferred: 2000, duration: 15, errors: ["warning"]),
                .init(threadId: 2, filesTransferred: 50, bytesTransferred: 500, duration: 8, errors: []),
            ],
            totalDuration: 15,
            averageSpeed: 233.3,
            peakSpeed: 250
        )

        XCTAssertEqual(result.totalFilesTransferred, 350)
        XCTAssertEqual(result.totalBytesTransferred, 3500)
        XCTAssertTrue(result.hadErrors)
    }

    func testParallelExecutionResultNoErrors() {
        let result = ParallelExecutionResult(
            threadResults: [
                .init(threadId: 0, filesTransferred: 100, bytesTransferred: 1000, duration: 10, errors: []),
            ],
            totalDuration: 10,
            averageSpeed: 100,
            peakSpeed: 100
        )

        XCTAssertFalse(result.hadErrors)
    }
}
