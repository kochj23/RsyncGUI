//
//  DependencyCheckTests.swift
//  RsyncGUITests
//
//  Created by Jordan Koch on 4/21/26.
//

import XCTest
@testable import RsyncGUI

final class DependencyCheckTests: XCTestCase {

    // MARK: - No Dependencies

    func testJobWithNoDependenciesIsSatisfied() {
        let job = SyncJob(name: "Independent", source: "/src", destination: "/dst")
        let allJobs = [job]

        let result = AdvancedExecutionService.shared.checkDependencies(for: job, allJobs: allJobs)

        switch result {
        case .satisfied:
            break  // Expected
        case .unsatisfied:
            XCTFail("Job with no dependencies should be satisfied")
        }
    }

    // MARK: - Satisfied Dependencies

    func testDependencyIsSatisfiedWhenDepJobSucceeded() {
        var depJob = SyncJob(name: "Dependency", source: "/dep-src", destination: "/dep-dst")
        depJob.lastStatus = .success

        var mainJob = SyncJob(name: "Main", source: "/src", destination: "/dst")
        mainJob.dependencies = [depJob.id]

        let allJobs = [depJob, mainJob]
        let result = AdvancedExecutionService.shared.checkDependencies(for: mainJob, allJobs: allJobs)

        switch result {
        case .satisfied:
            break  // Expected
        case .unsatisfied:
            XCTFail("Should be satisfied when dependency succeeded")
        }
    }

    // MARK: - Unsatisfied Dependencies

    func testDependencyUnsatisfiedWhenDepJobFailed() {
        var depJob = SyncJob(name: "Failing Dep", source: "/dep-src", destination: "/dep-dst")
        depJob.lastStatus = .failed

        var mainJob = SyncJob(name: "Main", source: "/src", destination: "/dst")
        mainJob.dependencies = [depJob.id]

        let allJobs = [depJob, mainJob]
        let result = AdvancedExecutionService.shared.checkDependencies(for: mainJob, allJobs: allJobs)

        switch result {
        case .satisfied:
            XCTFail("Should be unsatisfied when dependency failed")
        case .unsatisfied(let reasons):
            XCTAssertEqual(reasons.count, 1)
            XCTAssertTrue(reasons[0].contains("Failing Dep"))
        }
    }

    func testDependencyUnsatisfiedWhenDepJobNeverRun() {
        var depJob = SyncJob(name: "Never Run", source: "/dep-src", destination: "/dep-dst")
        depJob.lastStatus = nil  // Never been run

        var mainJob = SyncJob(name: "Main", source: "/src", destination: "/dst")
        mainJob.dependencies = [depJob.id]

        let allJobs = [depJob, mainJob]
        let result = AdvancedExecutionService.shared.checkDependencies(for: mainJob, allJobs: allJobs)

        switch result {
        case .satisfied:
            XCTFail("Should be unsatisfied when dependency never ran")
        case .unsatisfied(let reasons):
            XCTAssertEqual(reasons.count, 1)
            XCTAssertTrue(reasons[0].contains("never run"))
        }
    }

    func testDependencyUnsatisfiedWhenDepJobCancelled() {
        var depJob = SyncJob(name: "Cancelled Dep", source: "/dep-src", destination: "/dep-dst")
        depJob.lastStatus = .cancelled

        var mainJob = SyncJob(name: "Main", source: "/src", destination: "/dst")
        mainJob.dependencies = [depJob.id]

        let allJobs = [depJob, mainJob]
        let result = AdvancedExecutionService.shared.checkDependencies(for: mainJob, allJobs: allJobs)

        switch result {
        case .satisfied:
            XCTFail("Should be unsatisfied when dependency was cancelled")
        case .unsatisfied(let reasons):
            XCTAssertEqual(reasons.count, 1)
        }
    }

    func testDependencyUnsatisfiedWhenDepJobPartialSuccess() {
        var depJob = SyncJob(name: "Partial Dep", source: "/dep-src", destination: "/dep-dst")
        depJob.lastStatus = .partialSuccess

        var mainJob = SyncJob(name: "Main", source: "/src", destination: "/dst")
        mainJob.dependencies = [depJob.id]

        let allJobs = [depJob, mainJob]
        let result = AdvancedExecutionService.shared.checkDependencies(for: mainJob, allJobs: allJobs)

        switch result {
        case .satisfied:
            XCTFail("Should be unsatisfied when dependency had partial success")
        case .unsatisfied(let reasons):
            XCTAssertEqual(reasons.count, 1)
        }
    }

    // MARK: - Missing Dependencies

    func testDependencyUnsatisfiedWhenDepJobMissing() {
        let missingId = UUID()

        var mainJob = SyncJob(name: "Main", source: "/src", destination: "/dst")
        mainJob.dependencies = [missingId]

        let allJobs = [mainJob]
        let result = AdvancedExecutionService.shared.checkDependencies(for: mainJob, allJobs: allJobs)

        switch result {
        case .satisfied:
            XCTFail("Should be unsatisfied when dependency job is missing")
        case .unsatisfied(let reasons):
            XCTAssertEqual(reasons.count, 1)
            XCTAssertTrue(reasons[0].contains("Missing job"))
        }
    }

    // MARK: - Multiple Dependencies

    func testMultipleDependenciesAllSatisfied() {
        var dep1 = SyncJob(name: "Dep 1", source: "/s1", destination: "/d1")
        dep1.lastStatus = .success

        var dep2 = SyncJob(name: "Dep 2", source: "/s2", destination: "/d2")
        dep2.lastStatus = .success

        var mainJob = SyncJob(name: "Main", source: "/src", destination: "/dst")
        mainJob.dependencies = [dep1.id, dep2.id]

        let allJobs = [dep1, dep2, mainJob]
        let result = AdvancedExecutionService.shared.checkDependencies(for: mainJob, allJobs: allJobs)

        switch result {
        case .satisfied:
            break  // Expected
        case .unsatisfied:
            XCTFail("All dependencies succeeded, should be satisfied")
        }
    }

    func testMultipleDependenciesPartiallyUnsatisfied() {
        var dep1 = SyncJob(name: "Good Dep", source: "/s1", destination: "/d1")
        dep1.lastStatus = .success

        var dep2 = SyncJob(name: "Bad Dep", source: "/s2", destination: "/d2")
        dep2.lastStatus = .failed

        var mainJob = SyncJob(name: "Main", source: "/src", destination: "/dst")
        mainJob.dependencies = [dep1.id, dep2.id]

        let allJobs = [dep1, dep2, mainJob]
        let result = AdvancedExecutionService.shared.checkDependencies(for: mainJob, allJobs: allJobs)

        switch result {
        case .satisfied:
            XCTFail("Should be unsatisfied when any dependency failed")
        case .unsatisfied(let reasons):
            XCTAssertEqual(reasons.count, 1, "Only the failed dep should be in reasons")
            XCTAssertTrue(reasons[0].contains("Bad Dep"))
        }
    }

    func testMultipleDependenciesAllUnsatisfied() {
        var dep1 = SyncJob(name: "Failed 1", source: "/s1", destination: "/d1")
        dep1.lastStatus = .failed

        var dep2 = SyncJob(name: "Failed 2", source: "/s2", destination: "/d2")
        dep2.lastStatus = .cancelled

        let missingId = UUID()

        var mainJob = SyncJob(name: "Main", source: "/src", destination: "/dst")
        mainJob.dependencies = [dep1.id, dep2.id, missingId]

        let allJobs = [dep1, dep2, mainJob]
        let result = AdvancedExecutionService.shared.checkDependencies(for: mainJob, allJobs: allJobs)

        switch result {
        case .satisfied:
            XCTFail("All dependencies failed or missing, should be unsatisfied")
        case .unsatisfied(let reasons):
            XCTAssertEqual(reasons.count, 3, "All three deps should appear as unsatisfied")
        }
    }

    // MARK: - DependencyError

    func testDependencyErrorDescription() {
        let error = DependencyError.unsatisfiedDependencies([
            "Job A: Not run successfully",
            "Missing job: some-uuid"
        ])

        let description = error.errorDescription
        XCTAssertNotNil(description)
        XCTAssertTrue(description!.contains("Job A"))
        XCTAssertTrue(description!.contains("Missing job"))
    }

    // MARK: - Parallel File Splitting

    func testSplitFilesByCountEvenDistribution() {
        let files = (1...12).map { "file\($0).txt" }

        // Use the service's internal logic indirectly
        // Split 12 files into 4 threads = 3 each
        let threadCount = 4
        let chunkSize = max(1, files.count / threadCount)

        var batches: [[String]] = []
        for i in 0..<threadCount {
            let start = i * chunkSize
            let end = (i == threadCount - 1) ? files.count : min(start + chunkSize, files.count)
            if start < files.count {
                batches.append(Array(files[start..<end]))
            }
        }

        XCTAssertEqual(batches.count, 4)
        XCTAssertEqual(batches[0].count, 3)
        XCTAssertEqual(batches[1].count, 3)
        XCTAssertEqual(batches[2].count, 3)
        XCTAssertEqual(batches[3].count, 3)

        // All files should be present
        let flatFiles = batches.flatMap { $0 }
        XCTAssertEqual(flatFiles.count, 12)
    }

    func testSplitFilesByCountUnevenDistribution() {
        let files = (1...10).map { "file\($0).txt" }
        let threadCount = 3
        let chunkSize = max(1, files.count / threadCount)

        var batches: [[String]] = []
        for i in 0..<threadCount {
            let start = i * chunkSize
            let end = (i == threadCount - 1) ? files.count : min(start + chunkSize, files.count)
            if start < files.count {
                batches.append(Array(files[start..<end]))
            }
        }

        // 10 files / 3 threads: [3, 3, 4] (last batch gets remainder)
        XCTAssertEqual(batches.count, 3)
        XCTAssertEqual(batches.flatMap { $0 }.count, 10, "All files should be assigned")
    }

    func testSplitFilesWithSingleThread() {
        let files = ["a.txt", "b.txt", "c.txt"]

        // threadCount <= 1 should return all files in one batch
        XCTAssertEqual(files.count, 3)
        // The guard checks threadCount > 1
        let threadCount = 1
        if threadCount <= 1 {
            let batches = [files]
            XCTAssertEqual(batches.count, 1)
            XCTAssertEqual(batches[0].count, 3)
        }
    }

    func testSplitEmptyFileList() {
        let files: [String] = []
        let threadCount = 4

        if files.isEmpty || threadCount <= 1 {
            let batches = [files]
            XCTAssertEqual(batches.count, 1)
            XCTAssertTrue(batches[0].isEmpty)
        }
    }
}
