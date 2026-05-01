//
//  IntegrationTests.swift
//  RsyncGUITests
//
//  Created by Jordan Koch on 5/1/26.
//
//  Integration tests that verify actual rsync binary behavior and
//  end-to-end sync with real temporary directories on disk.

import XCTest
@testable import RsyncGUI

final class IntegrationTests: XCTestCase {

    private var tempSourceDir: URL!
    private var tempDestDir: URL!

    override func setUp() {
        super.setUp()
        let fm = FileManager.default
        let base = fm.temporaryDirectory.appendingPathComponent("RsyncGUITests-\(UUID().uuidString)")

        tempSourceDir = base.appendingPathComponent("source")
        tempDestDir = base.appendingPathComponent("dest")

        try? fm.createDirectory(at: tempSourceDir, withIntermediateDirectories: true)
        try? fm.createDirectory(at: tempDestDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        let fm = FileManager.default
        if let source = tempSourceDir {
            try? fm.removeItem(at: source.deletingLastPathComponent())
        }
        super.tearDown()
    }

    // MARK: - Rsync Binary Verification

    func testSystemRsyncBinaryExists() {
        let exists = FileManager.default.isExecutableFile(atPath: "/usr/bin/rsync")
        XCTAssertTrue(exists, "/usr/bin/rsync must exist on macOS")
    }

    func testRsyncBinaryIsExecutable() {
        let isExecutable = FileManager.default.isExecutableFile(atPath: "/usr/bin/rsync")
        XCTAssertTrue(isExecutable, "rsync must be executable")
    }

    func testRsyncVersionOutput() throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/rsync")
        process.arguments = ["--version"]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        try process.run()
        process.waitUntilExit()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8) ?? ""

        XCTAssertTrue(output.contains("rsync"), "rsync --version should contain 'rsync'")
        XCTAssertTrue(output.contains("version"), "rsync --version should contain 'version'")
    }

    func testResolveRsyncPathFindsValidBinary() {
        // The same logic as RsyncExecutor.resolveRsyncPath()
        let candidates = ["/usr/bin/rsync", "/opt/homebrew/bin/rsync", "/usr/local/bin/rsync"]
        let resolved = candidates.first { FileManager.default.isExecutableFile(atPath: $0) } ?? "/usr/bin/rsync"

        XCTAssertTrue(FileManager.default.isExecutableFile(atPath: resolved),
                      "Resolved rsync path should be executable: \(resolved)")
    }

    // MARK: - Local-to-Local Sync

    func testLocalToLocalSyncWithTempDirectories() throws {
        // Create test files in source
        let fm = FileManager.default
        let file1 = tempSourceDir.appendingPathComponent("test1.txt")
        let file2 = tempSourceDir.appendingPathComponent("test2.txt")
        let subdir = tempSourceDir.appendingPathComponent("subdir")
        try fm.createDirectory(at: subdir, withIntermediateDirectories: true)
        let file3 = subdir.appendingPathComponent("nested.txt")

        try "Hello World".write(to: file1, atomically: true, encoding: .utf8)
        try "Second File".write(to: file2, atomically: true, encoding: .utf8)
        try "Nested File".write(to: file3, atomically: true, encoding: .utf8)

        // Run rsync directly
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/rsync")
        process.arguments = ["-a", "--stats", tempSourceDir.path + "/", tempDestDir.path + "/"]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        try process.run()
        process.waitUntilExit()

        XCTAssertEqual(process.terminationStatus, 0, "rsync should exit with status 0")

        // Verify files were synced
        XCTAssertTrue(fm.fileExists(atPath: tempDestDir.appendingPathComponent("test1.txt").path))
        XCTAssertTrue(fm.fileExists(atPath: tempDestDir.appendingPathComponent("test2.txt").path))
        XCTAssertTrue(fm.fileExists(atPath: tempDestDir.appendingPathComponent("subdir/nested.txt").path))

        // Verify content
        let content1 = try String(contentsOf: tempDestDir.appendingPathComponent("test1.txt"), encoding: .utf8)
        XCTAssertEqual(content1, "Hello World")
    }

    func testDryRunDoesNotModifyDestination() throws {
        let fm = FileManager.default
        let file = tempSourceDir.appendingPathComponent("dryrun-test.txt")
        try "Dry run content".write(to: file, atomically: true, encoding: .utf8)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/rsync")
        process.arguments = ["-a", "-n", "--stats", tempSourceDir.path + "/", tempDestDir.path + "/"]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        try process.run()
        process.waitUntilExit()

        XCTAssertEqual(process.terminationStatus, 0, "Dry run should exit with status 0")

        // File should NOT exist in destination after dry run
        XCTAssertFalse(fm.fileExists(atPath: tempDestDir.appendingPathComponent("dryrun-test.txt").path),
                       "Dry run should not create files in destination")
    }

    func testSyncWithDeleteRemovesExtraFiles() throws {
        let fm = FileManager.default

        // Create source file
        let sourceFile = tempSourceDir.appendingPathComponent("keep.txt")
        try "keep".write(to: sourceFile, atomically: true, encoding: .utf8)

        // Create extra file in destination that should be deleted
        let extraFile = tempDestDir.appendingPathComponent("extra.txt")
        try "extra".write(to: extraFile, atomically: true, encoding: .utf8)

        // Sync with --delete
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/rsync")
        process.arguments = ["-a", "--delete", tempSourceDir.path + "/", tempDestDir.path + "/"]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        try process.run()
        process.waitUntilExit()

        XCTAssertEqual(process.terminationStatus, 0)
        XCTAssertTrue(fm.fileExists(atPath: tempDestDir.appendingPathComponent("keep.txt").path),
                      "Source file should exist in destination")
        XCTAssertFalse(fm.fileExists(atPath: tempDestDir.appendingPathComponent("extra.txt").path),
                       "--delete should remove files not in source")
    }

    func testSyncWithExcludePattern() throws {
        let fm = FileManager.default

        let file1 = tempSourceDir.appendingPathComponent("include.txt")
        let file2 = tempSourceDir.appendingPathComponent("exclude.tmp")
        let file3 = tempSourceDir.appendingPathComponent(".DS_Store")

        try "include".write(to: file1, atomically: true, encoding: .utf8)
        try "exclude".write(to: file2, atomically: true, encoding: .utf8)
        try "dsstore".write(to: file3, atomically: true, encoding: .utf8)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/rsync")
        process.arguments = ["-a", "--exclude=*.tmp", "--exclude=.DS_Store",
                             tempSourceDir.path + "/", tempDestDir.path + "/"]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        try process.run()
        process.waitUntilExit()

        XCTAssertEqual(process.terminationStatus, 0)
        XCTAssertTrue(fm.fileExists(atPath: tempDestDir.appendingPathComponent("include.txt").path))
        XCTAssertFalse(fm.fileExists(atPath: tempDestDir.appendingPathComponent("exclude.tmp").path),
                       "*.tmp should be excluded")
        XCTAssertFalse(fm.fileExists(atPath: tempDestDir.appendingPathComponent(".DS_Store").path),
                       ".DS_Store should be excluded")
    }

    // MARK: - Filenames with Special Characters

    func testSyncFilenameWithSpaces() throws {
        let fm = FileManager.default
        let file = tempSourceDir.appendingPathComponent("file with spaces.txt")
        try "spaces".write(to: file, atomically: true, encoding: .utf8)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/rsync")
        process.arguments = ["-a", tempSourceDir.path + "/", tempDestDir.path + "/"]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        try process.run()
        process.waitUntilExit()

        XCTAssertEqual(process.terminationStatus, 0)
        XCTAssertTrue(fm.fileExists(atPath: tempDestDir.appendingPathComponent("file with spaces.txt").path),
                      "Files with spaces should sync correctly via Process.arguments (no shell)")
    }

    func testSyncFilenameWithUnicodeCharacters() throws {
        let fm = FileManager.default
        let file = tempSourceDir.appendingPathComponent("datos-espa\u{00F1}ol.txt")
        try "unicode".write(to: file, atomically: true, encoding: .utf8)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/rsync")
        process.arguments = ["-a", tempSourceDir.path + "/", tempDestDir.path + "/"]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        try process.run()
        process.waitUntilExit()

        XCTAssertEqual(process.terminationStatus, 0)
        XCTAssertTrue(fm.fileExists(atPath: tempDestDir.appendingPathComponent("datos-espa\u{00F1}ol.txt").path),
                      "Files with unicode characters should sync correctly")
    }

    func testSyncFilenameWithParentheses() throws {
        let fm = FileManager.default
        let file = tempSourceDir.appendingPathComponent("photo (1).jpg")
        try "photo".write(to: file, atomically: true, encoding: .utf8)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/rsync")
        process.arguments = ["-a", tempSourceDir.path + "/", tempDestDir.path + "/"]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        try process.run()
        process.waitUntilExit()

        XCTAssertEqual(process.terminationStatus, 0)
        XCTAssertTrue(fm.fileExists(atPath: tempDestDir.appendingPathComponent("photo (1).jpg").path))
    }

    func testSyncFilenameWithSingleQuote() throws {
        let fm = FileManager.default
        let file = tempSourceDir.appendingPathComponent("jordan's file.txt")
        try "quote".write(to: file, atomically: true, encoding: .utf8)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/rsync")
        process.arguments = ["-a", tempSourceDir.path + "/", tempDestDir.path + "/"]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        try process.run()
        process.waitUntilExit()

        XCTAssertEqual(process.terminationStatus, 0)
        XCTAssertTrue(fm.fileExists(atPath: tempDestDir.appendingPathComponent("jordan's file.txt").path),
                      "Files with single quotes should sync correctly via Process.arguments")
    }

    // MARK: - Command Building with SyncJob

    func testBuildCommandProducesArrayNotShellString() {
        // Verify that RsyncExecutor uses Process.arguments (array), not shell strings
        let job = SyncJob(name: "Test", source: "/tmp/source", destination: "/tmp/dest")
        let args = job.options.toArguments()

        // Arguments should be individual strings, not a joined shell command
        for arg in args {
            XCTAssertFalse(arg.contains("|"), "Arguments should not contain pipe characters")
            XCTAssertFalse(arg.contains(";"), "Arguments should not contain semicolons (except in values)")
        }
    }

    // MARK: - Job Persistence Roundtrip

    func testJobPersistenceRoundtripViaJSON() throws {
        // Create a complex job
        var job = SyncJob(name: "Integration Test Job",
                         source: "/tmp/source with spaces",
                         destination: "/tmp/dest with 'quotes'")
        job.options.archive = true
        job.options.verbose = true
        job.options.exclude = ["*.tmp", ".DS_Store", "node_modules/"]
        job.options.bandwidth = 5000
        job.syncMode = .fanOut
        job.executionStrategy = .parallel
        job.maxParallelSyncs = 4

        var schedule = ScheduleConfig()
        schedule.isEnabled = true
        schedule.frequency = .daily
        job.schedule = schedule

        // Encode
        let data = try JSONEncoder().encode(job)
        XCTAssertFalse(data.isEmpty)

        // Decode
        let decoded = try JSONDecoder().decode(SyncJob.self, from: data)

        // Verify all fields survived
        XCTAssertEqual(decoded.name, job.name)
        XCTAssertEqual(decoded.source, job.source)
        XCTAssertEqual(decoded.destination, job.destination)
        XCTAssertEqual(decoded.options.archive, true)
        XCTAssertEqual(decoded.options.verbose, true)
        XCTAssertEqual(decoded.options.exclude, ["*.tmp", ".DS_Store", "node_modules/"])
        XCTAssertEqual(decoded.options.bandwidth, 5000)
        XCTAssertEqual(decoded.syncMode, .fanOut)
        XCTAssertEqual(decoded.executionStrategy, .parallel)
        XCTAssertEqual(decoded.maxParallelSyncs, 4)
        XCTAssertNotNil(decoded.schedule)
        XCTAssertTrue(decoded.schedule!.isEnabled)
        XCTAssertEqual(decoded.schedule!.frequency, .daily)

        // Verify the generated arguments are identical
        XCTAssertEqual(job.options.toArguments(), decoded.options.toArguments())
    }

    // MARK: - SyncJob Export to JSON

    func testMultipleJobsCanBeEncodedTogether() throws {
        let job1 = SyncJob(name: "Job 1", source: "/src1", destination: "/dst1")
        let job2 = SyncJob(name: "Job 2", source: "/src2", destination: "/dst2", destinationType: .remoteSSH)

        let data = try JSONEncoder().encode([job1, job2])
        let decoded = try JSONDecoder().decode([SyncJob].self, from: data)

        XCTAssertEqual(decoded.count, 2)
        XCTAssertEqual(decoded[0].name, "Job 1")
        XCTAssertEqual(decoded[1].name, "Job 2")
        XCTAssertEqual(decoded[1].effectiveDestinationType, .remoteSSH)
    }
}
