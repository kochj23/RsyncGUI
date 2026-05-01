//
//  SyncJobTests.swift
//  RsyncGUITests
//
//  Created by Jordan Koch on 4/21/26.
//

import XCTest
@testable import RsyncGUI

final class SyncJobTests: XCTestCase {

    // MARK: - Initialization

    func testSingleSourceDestinationInit() {
        let job = SyncJob(name: "Test Job", source: "/src", destination: "/dst")

        XCTAssertEqual(job.name, "Test Job")
        XCTAssertEqual(job.source, "/src")
        XCTAssertEqual(job.destination, "/dst")
        XCTAssertEqual(job.sources.count, 1)
        XCTAssertEqual(job.destinations.count, 1)
        XCTAssertEqual(job.destinations.first?.type, .local)
        XCTAssertTrue(job.isEnabled)
        XCTAssertEqual(job.totalRuns, 0)
        XCTAssertEqual(job.successfulRuns, 0)
        XCTAssertEqual(job.failedRuns, 0)
        XCTAssertNil(job.lastRun)
        XCTAssertNil(job.lastStatus)
    }

    func testMultiSourceDestinationInit() {
        let dests = [
            SyncDestination(path: "/backup1", type: .local),
            SyncDestination(path: "/backup2", type: .local)
        ]
        let job = SyncJob(name: "Multi Job", sources: ["/src1", "/src2"], destinations: dests)

        XCTAssertEqual(job.sources.count, 2)
        XCTAssertEqual(job.destinations.count, 2)
        XCTAssertEqual(job.source, "/src1", "Legacy source accessor should return first source")
        XCTAssertEqual(job.destination, "/backup1", "Legacy destination accessor should return first path")
    }

    func testEmptySourcesFallbackToSingleEmpty() {
        let job = SyncJob(name: "Empty", sources: [], destinations: [])

        XCTAssertEqual(job.sources.count, 1)
        XCTAssertEqual(job.sources.first, "")
        XCTAssertEqual(job.destinations.count, 1)
    }

    // MARK: - Legacy Accessors

    func testLegacySourceSetterUpdatesFirstSource() {
        var job = SyncJob(name: "Test", source: "/original", destination: "/dst")

        job.source = "/updated"
        XCTAssertEqual(job.sources.first, "/updated")
        XCTAssertEqual(job.sources.count, 1)
    }

    func testLegacySourceSetterOnEmptySourcesCreatesNew() {
        var job = SyncJob(name: "Test", sources: [], destinations: [])
        // Constructor adds empty string as fallback
        job.source = "/new-source"
        XCTAssertEqual(job.sources.first, "/new-source")
    }

    func testLegacyDestinationSetterUpdatesFirstDestination() {
        var job = SyncJob(name: "Test", source: "/src", destination: "/original")

        job.destination = "/updated"
        XCTAssertEqual(job.destinations.first?.path, "/updated")
    }

    func testLegacyIsRemoteGetter() {
        let localJob = SyncJob(name: "Local", source: "/src", destination: "/dst", destinationType: .local)
        XCTAssertFalse(localJob.isRemote)

        let remoteJob = SyncJob(name: "Remote", source: "/src", destination: "/dst", destinationType: .remoteSSH)
        XCTAssertTrue(remoteJob.isRemote)
    }

    func testLegacyIsRemoteSetter() {
        var job = SyncJob(name: "Test", source: "/src", destination: "/dst")
        XCTAssertFalse(job.isRemote)

        job.isRemote = true
        XCTAssertEqual(job.destinations.first?.type, .remoteSSH)

        job.isRemote = false
        XCTAssertEqual(job.destinations.first?.type, .local)
    }

    // MARK: - Effective Destination Type

    func testEffectiveDestinationTypeReturnsActualType() {
        let job = SyncJob(name: "Test", source: "/src", destination: "/dst", destinationType: .iCloudDrive)
        XCTAssertEqual(job.effectiveDestinationType, .iCloudDrive)
    }

    func testEffectiveDestinationTypeFallsBackToIsRemote() {
        // When destinationType is nil (pre-migration), should use isRemote
        var job = SyncJob(name: "Test", source: "/src", destination: "/dst")
        // Set via legacy accessor
        job.isRemote = true
        XCTAssertEqual(job.effectiveDestinationType, .remoteSSH)
    }

    func testEffectiveDestinationTypeSetterUpdatesIsRemote() {
        var job = SyncJob(name: "Test", source: "/src", destination: "/dst")

        job.effectiveDestinationType = .remoteSSH
        XCTAssertTrue(job.isRemote)

        job.effectiveDestinationType = .local
        XCTAssertFalse(job.isRemote)

        job.effectiveDestinationType = .iCloudDrive
        XCTAssertFalse(job.isRemote)
    }

    // MARK: - Remote Host/User Accessors

    func testRemoteHostAndUserAccessors() {
        var job = SyncJob(name: "SSH Job", source: "/src", destination: "/dst", destinationType: .remoteSSH)

        job.remoteHost = "server.example.com"
        job.remoteUser = "admin"
        job.sshKeyPath = "~/.ssh/id_rsa"

        XCTAssertEqual(job.remoteHost, "server.example.com")
        XCTAssertEqual(job.remoteUser, "admin")
        XCTAssertEqual(job.sshKeyPath, "~/.ssh/id_rsa")

        // These should map to first destination
        XCTAssertEqual(job.destinations.first?.remoteHost, "server.example.com")
        XCTAssertEqual(job.destinations.first?.remoteUser, "admin")
        XCTAssertEqual(job.destinations.first?.sshKeyPath, "~/.ssh/id_rsa")
    }

    // MARK: - iCloud Drive Path

    func testICloudDrivePathIsWithinHomeDirectory() {
        let iCloudPath = SyncJob.iCloudDrivePath
        let homeDir = FileManager.default.homeDirectoryForCurrentUser.path

        XCTAssertTrue(iCloudPath.hasPrefix(homeDir),
                      "iCloud Drive path should be within home directory")
        XCTAssertTrue(iCloudPath.contains("Library/Mobile Documents/com~apple~CloudDocs"),
                      "iCloud Drive path should point to CloudDocs")
    }

    // MARK: - Sync Mode

    func testSyncModeDefaultIsFanOut() {
        let job = SyncJob(name: "Test", source: "/src", destination: "/dst")
        XCTAssertEqual(job.syncMode, .fanOut)
    }

    func testSyncModeDescriptions() {
        XCTAssertFalse(SyncMode.fanOut.description.isEmpty)
        XCTAssertFalse(SyncMode.fanIn.description.isEmpty)
        XCTAssertFalse(SyncMode.fullMesh.description.isEmpty)
    }

    func testSyncModeIcons() {
        XCTAssertFalse(SyncMode.fanOut.icon.isEmpty)
        XCTAssertFalse(SyncMode.fanIn.icon.isEmpty)
        XCTAssertFalse(SyncMode.fullMesh.icon.isEmpty)
    }

    // MARK: - Execution Strategy

    func testExecutionStrategyDefaultIsSequential() {
        let job = SyncJob(name: "Test", source: "/src", destination: "/dst")
        XCTAssertEqual(job.executionStrategy, .sequential)
    }

    func testExecutionStrategyDescriptions() {
        XCTAssertFalse(ExecutionStrategy.sequential.description.isEmpty)
        XCTAssertFalse(ExecutionStrategy.parallel.description.isEmpty)
    }

    // MARK: - Failure Handling

    func testFailureHandlingDefaultIsContinue() {
        let job = SyncJob(name: "Test", source: "/src", destination: "/dst")
        XCTAssertEqual(job.failureHandling, .continueOnError)
    }

    func testFailureHandlingDescriptions() {
        XCTAssertFalse(FailureHandling.continueOnError.description.isEmpty)
        XCTAssertFalse(FailureHandling.stopOnError.description.isEmpty)
    }

    // MARK: - Destination Type Enum

    func testDestinationTypeRawValues() {
        XCTAssertEqual(DestinationType.local.rawValue, "Local Folder")
        XCTAssertEqual(DestinationType.remoteSSH.rawValue, "Remote Server (SSH)")
        XCTAssertEqual(DestinationType.iCloudDrive.rawValue, "iCloud Drive")
    }

    // MARK: - SyncDestination

    func testSyncDestinationDefaultValues() {
        let dest = SyncDestination()

        XCTAssertEqual(dest.path, "")
        XCTAssertEqual(dest.type, .local)
        XCTAssertTrue(dest.isEnabled)
        XCTAssertNil(dest.remoteHost)
        XCTAssertNil(dest.remoteUser)
        XCTAssertNil(dest.sshKeyPath)
        XCTAssertNil(dest.bookmark)
    }

    func testSyncDestinationEquality() {
        let dest1 = SyncDestination(path: "/backup1", type: .local)
        var dest2 = dest1
        // Same ID = equal
        XCTAssertEqual(dest1, dest2)

        // Different ID (new instance) = not equal
        dest2 = SyncDestination(path: "/backup1", type: .local)
        XCTAssertNotEqual(dest1, dest2, "Different UUIDs should not be equal")
    }

    // MARK: - Execution Status

    func testExecutionStatusRawValues() {
        XCTAssertEqual(ExecutionStatus.success.rawValue, "success")
        XCTAssertEqual(ExecutionStatus.failed.rawValue, "failed")
        XCTAssertEqual(ExecutionStatus.partialSuccess.rawValue, "partialSuccess")
        XCTAssertEqual(ExecutionStatus.cancelled.rawValue, "cancelled")
    }

    // MARK: - ExecutionResult

    func testExecutionResultDuration() {
        let start = Date()
        let end = start.addingTimeInterval(120)  // 2 minutes later

        var result = ExecutionResult(
            id: UUID(),
            jobId: UUID(),
            startTime: start,
            endTime: end,
            status: .success,
            filesTransferred: 100,
            bytesTransferred: 1_000_000,
            errors: [],
            output: ""
        )

        XCTAssertEqual(result.duration, 120, accuracy: 0.001)

        // Test transfer speed
        XCTAssertEqual(result.transferSpeed, 1_000_000 / 120, accuracy: 0.1)

        // No end time means zero duration
        result.endTime = nil
        XCTAssertEqual(result.duration, 0)
        XCTAssertEqual(result.transferSpeed, 0)
    }

    // MARK: - Codable Roundtrip

    func testSyncJobCodableRoundtrip() throws {
        var job = SyncJob(name: "Backup Docs", source: "/Users/test/Documents", destination: "/backup/docs")
        job.options.verbose = true
        job.options.compress = true
        job.syncMode = .fanOut
        job.executionStrategy = .parallel
        job.maxParallelSyncs = 4
        job.verifyAfterSync = true

        let encoder = JSONEncoder()
        let data = try encoder.encode(job)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(SyncJob.self, from: data)

        XCTAssertEqual(decoded.name, job.name)
        XCTAssertEqual(decoded.source, job.source)
        XCTAssertEqual(decoded.destination, job.destination)
        XCTAssertEqual(decoded.syncMode, job.syncMode)
        XCTAssertEqual(decoded.executionStrategy, job.executionStrategy)
        XCTAssertEqual(decoded.maxParallelSyncs, job.maxParallelSyncs)
        XCTAssertEqual(decoded.verifyAfterSync, job.verifyAfterSync)
        XCTAssertTrue(decoded.options.verbose)
        XCTAssertTrue(decoded.options.compress)
    }

    func testSyncJobWithScheduleCodableRoundtrip() throws {
        var job = SyncJob(name: "Scheduled Backup", source: "/src", destination: "/dst")
        var schedule = ScheduleConfig()
        schedule.isEnabled = true
        schedule.frequency = .daily
        schedule.runAtStartup = true
        job.schedule = schedule

        let data = try JSONEncoder().encode(job)
        let decoded = try JSONDecoder().decode(SyncJob.self, from: data)

        XCTAssertNotNil(decoded.schedule)
        XCTAssertTrue(decoded.schedule!.isEnabled)
        XCTAssertEqual(decoded.schedule!.frequency, .daily)
        XCTAssertTrue(decoded.schedule!.runAtStartup)
    }

    // MARK: - Default Options

    func testNewJobHasDefaultRsyncOptions() {
        let job = SyncJob(name: "Test", source: "/src", destination: "/dst")

        // Verify defaults match RsyncOptions defaults
        XCTAssertTrue(job.options.archive)
        XCTAssertFalse(job.options.verbose)
        XCTAssertFalse(job.options.compress)
        XCTAssertFalse(job.options.delete)
        XCTAssertTrue(job.options.stats)
        XCTAssertTrue(job.options.humanReadable)
        XCTAssertTrue(job.options.progress)
    }

    // MARK: - Dependencies

    func testNewJobHasNoDependencies() {
        let job = SyncJob(name: "Test", source: "/src", destination: "/dst")
        XCTAssertTrue(job.dependencies.isEmpty)
        XCTAssertFalse(job.runOnlyIfChanged)
        XCTAssertNil(job.lastSourceChecksum)
    }
}
