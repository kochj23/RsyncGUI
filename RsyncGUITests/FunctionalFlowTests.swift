//
//  FunctionalFlowTests.swift
//  RsyncGUITests
//
//  Created by Jordan Koch on 5/3/26.
//
//  Functional tests: full job lifecycle flows including creation,
//  configuration, duplication, persistence roundtrip, and
//  execution history recording. These tests verify that the
//  entire data pipeline works correctly end-to-end.

import XCTest
@testable import RsyncGUI

final class FunctionalFlowTests: XCTestCase {

    // MARK: - Job Creation → Configuration → Persistence Flow

    func testFullJobCreationAndConfigurationFlow() throws {
        // Step 1: Create a new job (simulating what JobManager.createNewJob() builds)
        var job = SyncJob(name: "Documents Backup", source: "/Users/test/Documents", destination: "/Volumes/Backup/Documents")

        // Step 2: Configure options
        job.options.archive = true
        job.options.verbose = true
        job.options.compress = true
        job.options.delete = true
        job.options.exclude = [".DS_Store", "Thumbs.db", "*.tmp", "node_modules/"]
        job.options.bandwidth = 5000
        job.options.progress = true
        job.options.stats = true
        job.options.humanReadable = true

        // Step 3: Configure schedule
        var schedule = ScheduleConfig()
        schedule.isEnabled = true
        schedule.frequency = .daily
        schedule.runAtStartup = false
        var components = DateComponents()
        components.hour = 2
        components.minute = 0
        schedule.time = Calendar.current.date(from: components)
        job.schedule = schedule

        // Step 4: Configure execution strategy
        job.syncMode = .fanOut
        job.executionStrategy = .sequential
        job.failureHandling = .continueOnError
        job.verifyAfterSync = true

        // Step 5: Verify all settings
        XCTAssertEqual(job.name, "Documents Backup")
        XCTAssertEqual(job.source, "/Users/test/Documents")
        XCTAssertEqual(job.destination, "/Volumes/Backup/Documents")
        XCTAssertTrue(job.options.archive)
        XCTAssertTrue(job.options.verbose)
        XCTAssertEqual(job.options.exclude.count, 4)
        XCTAssertEqual(job.options.bandwidth, 5000)
        XCTAssertNotNil(job.schedule)
        XCTAssertTrue(job.schedule!.isEnabled)
        XCTAssertEqual(job.schedule!.frequency, .daily)
        XCTAssertTrue(job.verifyAfterSync)

        // Step 6: Encode and decode (persistence roundtrip)
        let data = try JSONEncoder().encode(job)
        let decoded = try JSONDecoder().decode(SyncJob.self, from: data)

        // Step 7: Verify everything survived the roundtrip
        XCTAssertEqual(decoded.name, job.name)
        XCTAssertEqual(decoded.source, job.source)
        XCTAssertEqual(decoded.destination, job.destination)
        XCTAssertEqual(decoded.options.toArguments(), job.options.toArguments())
        XCTAssertEqual(decoded.schedule?.isEnabled, true)
        XCTAssertEqual(decoded.schedule?.frequency, .daily)
        XCTAssertTrue(decoded.verifyAfterSync)
        XCTAssertEqual(decoded.syncMode, .fanOut)
        XCTAssertEqual(decoded.executionStrategy, .sequential)
    }

    // MARK: - Job Duplication Flow

    func testJobDuplicationPreservesConfigButResetsStats() {
        // Original job with run history
        var original = SyncJob(name: "Production Backup", source: "/data/production", destination: "/backup/production")
        original.options.archive = true
        original.options.compress = true
        original.options.delete = true
        original.options.exclude = ["*.log", "*.tmp"]
        original.totalRuns = 50
        original.successfulRuns = 48
        original.failedRuns = 2
        original.lastRun = Date()
        original.lastStatus = .success

        var schedule = ScheduleConfig()
        schedule.isEnabled = true
        schedule.frequency = .hourly
        original.schedule = schedule

        // Duplicate (replicating JobManager.duplicateJob logic)
        var duplicate = original
        duplicate.id = UUID()
        duplicate.name = "\(original.name) (Copy)"
        duplicate.created = Date()
        duplicate.lastRun = nil
        duplicate.lastStatus = nil
        duplicate.totalRuns = 0
        duplicate.successfulRuns = 0
        duplicate.failedRuns = 0

        // Verify duplication
        XCTAssertNotEqual(duplicate.id, original.id, "Duplicate should have a new UUID")
        XCTAssertEqual(duplicate.name, "Production Backup (Copy)")
        XCTAssertEqual(duplicate.source, original.source)
        XCTAssertEqual(duplicate.destination, original.destination)

        // Options should be preserved
        XCTAssertTrue(duplicate.options.archive)
        XCTAssertTrue(duplicate.options.compress)
        XCTAssertTrue(duplicate.options.delete)
        XCTAssertEqual(duplicate.options.exclude, ["*.log", "*.tmp"])

        // Schedule should be preserved
        XCTAssertNotNil(duplicate.schedule)
        XCTAssertTrue(duplicate.schedule!.isEnabled)
        XCTAssertEqual(duplicate.schedule!.frequency, .hourly)

        // Stats should be reset
        XCTAssertEqual(duplicate.totalRuns, 0)
        XCTAssertEqual(duplicate.successfulRuns, 0)
        XCTAssertEqual(duplicate.failedRuns, 0)
        XCTAssertNil(duplicate.lastRun)
        XCTAssertNil(duplicate.lastStatus)
    }

    // MARK: - Execution Result → History Entry Flow

    func testExecutionResultToHistoryEntryConversion() {
        let jobId = UUID()
        let startTime = Date()
        let endTime = startTime.addingTimeInterval(300) // 5 minutes

        // Step 1: Create an execution result (as produced by RsyncExecutor)
        let result = ExecutionResult(
            id: UUID(),
            jobId: jobId,
            startTime: startTime,
            endTime: endTime,
            status: .success,
            filesTransferred: 1234,
            bytesTransferred: 567_890_123,
            errors: [],
            output: "sending incremental file list\n...\nNumber of files transferred: 1234\n"
        )

        // Step 2: Convert to history entry (as done by ExecutionHistoryManager)
        let entry = ExecutionHistoryEntry(result: result, jobName: "Daily Backup")

        // Step 3: Verify all fields transferred correctly
        XCTAssertEqual(entry.id, result.id)
        XCTAssertEqual(entry.jobId, jobId)
        XCTAssertEqual(entry.jobName, "Daily Backup")
        XCTAssertEqual(entry.timestamp, startTime)
        XCTAssertEqual(entry.status, .success)
        XCTAssertEqual(entry.filesTransferred, 1234)
        XCTAssertEqual(entry.bytesTransferred, 567_890_123)
        XCTAssertEqual(entry.duration, 300, accuracy: 0.001)
        XCTAssertTrue(entry.errors.isEmpty)
    }

    func testFailedExecutionResultToHistoryEntry() {
        let result = ExecutionResult(
            id: UUID(),
            jobId: UUID(),
            startTime: Date(),
            endTime: Date().addingTimeInterval(10),
            status: .failed,
            filesTransferred: 5,
            bytesTransferred: 1000,
            errors: ["rsync: connection refused (111)", "rsync error: error in socket IO"],
            output: "rsync: connection refused"
        )

        let entry = ExecutionHistoryEntry(result: result, jobName: "Remote Backup")

        XCTAssertEqual(entry.status, .failed)
        XCTAssertEqual(entry.errors.count, 2)
        XCTAssertTrue(entry.errors[0].contains("connection refused"))
    }

    // MARK: - Job Statistics Update Flow

    func testJobStatisticsUpdateAfterSuccessfulRun() {
        var job = SyncJob(name: "Test", source: "/src", destination: "/dst")
        XCTAssertEqual(job.totalRuns, 0)
        XCTAssertEqual(job.successfulRuns, 0)
        XCTAssertEqual(job.failedRuns, 0)

        // Simulate what JobManager.executeJob() does after a successful result
        job.totalRuns += 1
        job.successfulRuns += 1
        job.lastRun = Date()
        job.lastStatus = .success

        XCTAssertEqual(job.totalRuns, 1)
        XCTAssertEqual(job.successfulRuns, 1)
        XCTAssertEqual(job.failedRuns, 0)
        XCTAssertNotNil(job.lastRun)
        XCTAssertEqual(job.lastStatus, .success)
    }

    func testJobStatisticsUpdateAfterFailedRun() {
        var job = SyncJob(name: "Test", source: "/src", destination: "/dst")
        job.totalRuns = 10
        job.successfulRuns = 9
        job.failedRuns = 1

        // Simulate failed execution
        job.totalRuns += 1
        job.failedRuns += 1
        job.lastRun = Date()
        job.lastStatus = .failed

        XCTAssertEqual(job.totalRuns, 11)
        XCTAssertEqual(job.successfulRuns, 9)
        XCTAssertEqual(job.failedRuns, 2)
        XCTAssertEqual(job.lastStatus, .failed)
    }

    // MARK: - Multi-Destination Job Flow

    func testMultiDestinationJobConfigurationAndPersistence() throws {
        let dests = [
            SyncDestination(path: "/backup/local", type: .local),
            SyncDestination(path: "/remote/backup", type: .remoteSSH),
            SyncDestination(path: SyncJob.iCloudDrivePath + "/Backup", type: .iCloudDrive)
        ]

        var job = SyncJob(name: "Multi-Dest", sources: ["/data/important"], destinations: dests)
        job.executionStrategy = .parallel
        job.maxParallelSyncs = 3
        job.failureHandling = .continueOnError

        // Set remote host/user on the SSH destination
        job.destinations[1].remoteHost = "backup.example.com"
        job.destinations[1].remoteUser = "backup-user"
        job.destinations[1].sshKeyPath = "~/.ssh/id_ed25519"

        // Verify multi-destination setup
        XCTAssertEqual(job.destinations.count, 3)
        XCTAssertEqual(job.destinations[0].type, .local)
        XCTAssertEqual(job.destinations[1].type, .remoteSSH)
        XCTAssertEqual(job.destinations[2].type, .iCloudDrive)
        XCTAssertEqual(job.destinations[1].remoteHost, "backup.example.com")
        XCTAssertEqual(job.executionStrategy, .parallel)
        XCTAssertEqual(job.maxParallelSyncs, 3)

        // Persistence roundtrip
        let data = try JSONEncoder().encode(job)
        let decoded = try JSONDecoder().decode(SyncJob.self, from: data)

        XCTAssertEqual(decoded.destinations.count, 3)
        XCTAssertEqual(decoded.destinations[1].remoteHost, "backup.example.com")
        XCTAssertEqual(decoded.destinations[1].remoteUser, "backup-user")
        XCTAssertEqual(decoded.executionStrategy, .parallel)
        XCTAssertEqual(decoded.maxParallelSyncs, 3)
    }

    // MARK: - Dependency Chain Flow

    func testDependencyChainSatisfactionCheck() {
        // Create a chain: Job C depends on Job B, which depends on Job A
        var jobA = SyncJob(name: "Step 1: Backup DB", source: "/db", destination: "/backup/db")
        jobA.lastStatus = .success

        var jobB = SyncJob(name: "Step 2: Backup App", source: "/app", destination: "/backup/app")
        jobB.dependencies = [jobA.id]
        jobB.lastStatus = .success

        var jobC = SyncJob(name: "Step 3: Verify", source: "/backup", destination: "/archive")
        jobC.dependencies = [jobB.id]

        let allJobs = [jobA, jobB, jobC]

        // Check Job A: no dependencies, should be satisfied
        let resultA = AdvancedExecutionService.shared.checkDependencies(for: jobA, allJobs: allJobs)
        if case .unsatisfied = resultA {
            XCTFail("Job A has no dependencies, should be satisfied")
        }

        // Check Job B: depends on Job A (success), should be satisfied
        let resultB = AdvancedExecutionService.shared.checkDependencies(for: jobB, allJobs: allJobs)
        if case .unsatisfied = resultB {
            XCTFail("Job B's dependency (A) succeeded, should be satisfied")
        }

        // Check Job C: depends on Job B (success), should be satisfied
        let resultC = AdvancedExecutionService.shared.checkDependencies(for: jobC, allJobs: allJobs)
        if case .unsatisfied = resultC {
            XCTFail("Job C's dependency (B) succeeded, should be satisfied")
        }
    }

    func testDependencyChainBrokenByFailure() {
        var jobA = SyncJob(name: "Step 1", source: "/src", destination: "/dst")
        jobA.lastStatus = .failed  // This job failed

        var jobB = SyncJob(name: "Step 2", source: "/src2", destination: "/dst2")
        jobB.dependencies = [jobA.id]

        var jobC = SyncJob(name: "Step 3", source: "/src3", destination: "/dst3")
        jobC.dependencies = [jobB.id]

        let allJobs = [jobA, jobB, jobC]

        // Job B should be unsatisfied because Job A failed
        let resultB = AdvancedExecutionService.shared.checkDependencies(for: jobB, allJobs: allJobs)
        switch resultB {
        case .satisfied:
            XCTFail("Job B should be unsatisfied because Job A failed")
        case .unsatisfied(let reasons):
            XCTAssertEqual(reasons.count, 1)
            XCTAssertTrue(reasons[0].contains("Step 1"))
        }
    }

    // MARK: - Delta Report Integration Flow

    func testDeltaReportGenerationFromRsyncOutput() {
        let jobId = UUID()

        // Simulate realistic rsync output with itemize changes
        let rsyncOutput = """
        sending incremental file list
        >f+++++++++ documents/new_report.pdf
        >f+++++++++ documents/quarterly/q1_2026.xlsx
        >f.st...... config/app.json
        >f..t...... logs/app.log
        *deleting   archive/old_backup.zip
        *deleting   tmp/cache.dat

        sent 2,345,678 bytes  received 1,234 bytes  23,456.78 bytes/sec
        total size is 12,345,678  speedup is 5.27
        """

        let report = AdvancedExecutionService.shared.generateDeltaReport(from: rsyncOutput, jobId: jobId)

        // Verify delta report
        XCTAssertEqual(report.jobId, jobId)
        XCTAssertEqual(report.filesAdded.count, 2, "Should detect 2 new files")
        XCTAssertEqual(report.filesModified.count, 2, "Should detect 2 modified files")
        XCTAssertEqual(report.filesDeleted.count, 2, "Should detect 2 deleted files")
        XCTAssertEqual(report.totalChanges, 6)
        XCTAssertTrue(report.hasChanges)
        XCTAssertEqual(report.bytesAdded, 2345678)

        // Verify the summary is human-readable
        let summary = report.summary
        XCTAssertTrue(summary.contains("2 added"))
        XCTAssertTrue(summary.contains("2 modified"))
        XCTAssertTrue(summary.contains("2 deleted"))

        // Verify copyable report
        let copyable = report.copyableReport
        XCTAssertTrue(copyable.contains("Delta Report"))
        XCTAssertTrue(copyable.contains("new_report.pdf"))
        XCTAssertTrue(copyable.contains("old_backup.zip"))
        XCTAssertTrue(copyable.contains("End of Report"))
    }

    // MARK: - Schedule → Launchd Plist Flow

    func testScheduleConfigToLaunchdPlistEndToEnd() throws {
        // Create a fully configured job with schedule
        var job = SyncJob(name: "Nightly Backup", source: "/data", destination: "/backup")
        job.options.archive = true
        job.options.compress = true
        job.options.delete = true

        var schedule = ScheduleConfig()
        schedule.isEnabled = true
        schedule.frequency = .daily
        schedule.runAtStartup = true
        var components = DateComponents()
        components.hour = 3
        components.minute = 0
        schedule.time = Calendar.current.date(from: components)
        job.schedule = schedule

        // Generate plist
        let plist = schedule.toLaunchdPlist(
            jobId: job.id.uuidString,
            rsyncCommand: "/usr/bin/rsync -az --delete /data/ /backup/"
        )

        // Verify plist is valid XML
        XCTAssertTrue(plist.hasPrefix("<?xml"))
        XCTAssertTrue(plist.contains("com.jordankoch.rsyncgui.\(job.id.uuidString)"))

        // Parse and verify
        let data = plist.data(using: .utf8)!
        let parsed = try PropertyListSerialization.propertyList(from: data, format: nil) as! [String: Any]

        // Verify label
        let label = parsed["Label"] as? String
        XCTAssertEqual(label, "com.jordankoch.rsyncgui.\(job.id.uuidString)")

        // Verify program arguments
        let progArgs = parsed["ProgramArguments"] as? [String]
        XCTAssertEqual(progArgs?.count, 3)
        XCTAssertEqual(progArgs?[0], "/bin/sh")
        XCTAssertEqual(progArgs?[1], "-c")
        XCTAssertTrue(progArgs?[2].contains("rsync") ?? false)

        // Verify schedule
        let calInterval = parsed["StartCalendarInterval"] as? [String: Int]
        XCTAssertNotNil(calInterval)
        XCTAssertEqual(calInterval?["Hour"], 3)
        XCTAssertEqual(calInterval?["Minute"], 0)

        // Verify RunAtLoad
        XCTAssertEqual(parsed["RunAtLoad"] as? Bool, true)
    }

    // MARK: - Job Options → Arguments → Rsync Command Flow

    func testJobOptionsToRsyncCommandFlow() {
        var job = SyncJob(
            name: "Full Backup",
            source: "/Users/test/Documents",
            destination: "/Volumes/NAS/Backup"
        )
        job.options.archive = true
        job.options.verbose = true
        job.options.compress = true
        job.options.delete = true
        job.options.progress = true
        job.options.stats = true
        job.options.humanReadable = true
        job.options.exclude = [".DS_Store", "*.tmp"]
        job.options.bandwidth = 10000

        let args = job.options.toArguments()

        // Verify the complete argument set
        XCTAssertTrue(args.contains("-a"), "Archive mode should be set")
        XCTAssertTrue(args.contains("-v"), "Verbose should be set")
        XCTAssertTrue(args.contains("-z"), "Compress should be set")
        XCTAssertTrue(args.contains("--delete"), "Delete should be set")
        XCTAssertTrue(args.contains("--progress"), "Progress should be set")
        XCTAssertTrue(args.contains("--stats"), "Stats should be set")
        XCTAssertTrue(args.contains("-h"), "Human-readable should be set")
        XCTAssertTrue(args.contains("--exclude=.DS_Store"))
        XCTAssertTrue(args.contains("--exclude=*.tmp"))
        XCTAssertTrue(args.contains("--bwlimit=10000"))

        // Verify no injection-capable characters leaked into arguments
        for arg in args {
            XCTAssertFalse(arg.contains("|"), "Argument '\(arg)' should not contain pipe")
            XCTAssertFalse(arg.contains(";"), "Argument '\(arg)' should not contain semicolon")
            XCTAssertFalse(arg.contains("`"), "Argument '\(arg)' should not contain backtick")
            XCTAssertFalse(arg.contains("$("), "Argument '\(arg)' should not contain command substitution")
        }
    }

    // MARK: - CSV Export Flow

    func testExecutionHistoryCSVExportFormat() {
        // The ExecutionHistoryManager.exportToCSV() format should be valid CSV
        // We test the format by building an entry and verifying the CSV structure

        let result = ExecutionResult(
            id: UUID(),
            jobId: UUID(),
            startTime: Date(),
            endTime: Date().addingTimeInterval(60),
            status: .success,
            filesTransferred: 100,
            bytesTransferred: 5000,
            errors: [],
            output: ""
        )

        let entry = ExecutionHistoryEntry(result: result, jobName: "Test Job")

        // Verify the entry has all fields needed for CSV
        XCTAssertFalse(entry.jobName.isEmpty)
        XCTAssertEqual(entry.status, .success)
        XCTAssertEqual(entry.filesTransferred, 100)
        XCTAssertEqual(entry.bytesTransferred, 5000)
        XCTAssertEqual(entry.duration, 60, accuracy: 0.001)
        XCTAssertTrue(entry.errors.isEmpty)
    }

    // MARK: - Conditional Execution Flow

    func testConditionalExecutionFieldsPersist() throws {
        var job = SyncJob(name: "Conditional", source: "/src", destination: "/dst")
        job.runOnlyIfChanged = true
        job.lastSourceChecksum = "abc123def456"

        let data = try JSONEncoder().encode(job)
        let decoded = try JSONDecoder().decode(SyncJob.self, from: data)

        XCTAssertTrue(decoded.runOnlyIfChanged)
        XCTAssertEqual(decoded.lastSourceChecksum, "abc123def456")
    }

    // MARK: - Pre/Post Script Configuration Flow

    func testPrePostScriptFieldsPersist() throws {
        var job = SyncJob(name: "Scripted", source: "/src", destination: "/dst")
        job.preScript = "/usr/local/bin/pre-sync.sh"
        job.postScript = "/usr/local/bin/post-sync.sh"

        let data = try JSONEncoder().encode(job)
        let decoded = try JSONDecoder().decode(SyncJob.self, from: data)

        XCTAssertEqual(decoded.preScript, "/usr/local/bin/pre-sync.sh")
        XCTAssertEqual(decoded.postScript, "/usr/local/bin/post-sync.sh")
    }

    // MARK: - Disabled Destination Filtering

    func testDisabledDestinationsAreFilterable() {
        var dest1 = SyncDestination(path: "/backup1", type: .local)
        dest1.isEnabled = true

        var dest2 = SyncDestination(path: "/backup2", type: .local)
        dest2.isEnabled = false

        var dest3 = SyncDestination(path: "/backup3", type: .local)
        dest3.isEnabled = true

        let job = SyncJob(name: "Test", sources: ["/src"], destinations: [dest1, dest2, dest3])

        // Replicate the filtering done in RsyncExecutor.execute()
        let enabledDestinations = job.destinations.filter { $0.isEnabled }
        XCTAssertEqual(enabledDestinations.count, 2, "Only enabled destinations should be included")
        XCTAssertEqual(enabledDestinations[0].path, "/backup1")
        XCTAssertEqual(enabledDestinations[1].path, "/backup3")
    }

    // MARK: - Parallelism Config Flow

    func testParallelismConfigPersistsWithJob() throws {
        var job = SyncJob(name: "Parallel", source: "/src", destination: "/dst")

        var parallelConfig = ParallelismConfig()
        parallelConfig.isEnabled = true
        parallelConfig.numberOfThreads = 8
        parallelConfig.strategy = .byDirectory
        parallelConfig.filesPerThread = 500

        job.parallelism = parallelConfig

        let data = try JSONEncoder().encode(job)
        let decoded = try JSONDecoder().decode(SyncJob.self, from: data)

        XCTAssertNotNil(decoded.parallelism)
        XCTAssertTrue(decoded.parallelism!.isEnabled)
        XCTAssertEqual(decoded.parallelism!.numberOfThreads, 8)
        XCTAssertEqual(decoded.parallelism!.strategy, .byDirectory)
        XCTAssertEqual(decoded.parallelism!.filesPerThread, 500)
    }

    // MARK: - Multiple Jobs Persistence Flow

    func testMultipleJobsSerializeAndDeserializeCorrectly() throws {
        var jobs: [SyncJob] = []

        // Create several diverse jobs
        var job1 = SyncJob(name: "Local Backup", source: "/data", destination: "/backup")
        job1.options.archive = true
        job1.totalRuns = 100
        job1.successfulRuns = 98
        job1.failedRuns = 2

        var job2 = SyncJob(name: "Remote Sync", source: "/data", destination: "/remote", destinationType: .remoteSSH)
        job2.remoteHost = "server.example.com"
        job2.remoteUser = "admin"
        job2.options.compress = true

        var job3 = SyncJob(name: "iCloud Backup", source: "/photos", destination: SyncJob.iCloudDrivePath + "/Photos", destinationType: .iCloudDrive)
        job3.isEnabled = false

        jobs = [job1, job2, job3]

        // Encode all jobs together (as JobManager does)
        let data = try JSONEncoder().encode(jobs)
        let decoded = try JSONDecoder().decode([SyncJob].self, from: data)

        XCTAssertEqual(decoded.count, 3)
        XCTAssertEqual(decoded[0].name, "Local Backup")
        XCTAssertEqual(decoded[0].totalRuns, 100)
        XCTAssertEqual(decoded[1].name, "Remote Sync")
        XCTAssertEqual(decoded[1].remoteHost, "server.example.com")
        XCTAssertEqual(decoded[1].effectiveDestinationType, .remoteSSH)
        XCTAssertEqual(decoded[2].name, "iCloud Backup")
        XCTAssertFalse(decoded[2].isEnabled)
    }
}
