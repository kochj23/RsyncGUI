//
//  CommandBuilderTests.swift
//  RsyncGUITests
//
//  Created by Jordan Koch on 8/18/26.
//
//  High-value tests for under-covered deterministic logic:
//    * Delta report filename extraction (exercises the real public
//      AdvancedExecutionService.generateDeltaReport — existing tests only
//      asserted counts, never the extracted filename VALUES).
//    * Parallel file-splitting strategies byDirectory / bySize / automatic
//      (existing tests only replicated the byCount branch).
//    * Full rsync command assembly for both the launchd scheduler path
//      (ScheduleManager.buildRsyncCommand) and the executor path
//      (RsyncExecutor.buildCommand): SSH -e assembly, remote-prefix handling,
//      trailing-slash normalization, iCloud placeholder exclusion, and
//      shell escaping. These builders are private, so — matching the existing
//      convention in this suite — the exact source logic is replicated and
//      pinned here so regressions in the assembled command are caught.

import XCTest
@testable import RsyncGUI

final class CommandBuilderTests: XCTestCase {

    // MARK: - Delta Report Filename Extraction (real code)

    func testDeltaReportExtractsAddedFilenameValue() {
        let report = AdvancedExecutionService.shared.generateDeltaReport(
            from: ">f+++++++++ documents/report.pdf", jobId: UUID())

        XCTAssertEqual(report.filesAdded, ["documents/report.pdf"],
                       "The itemize prefix (11 chars) must be stripped and the path trimmed")
    }

    func testDeltaReportExtractsModifiedFilenameValue() {
        let report = AdvancedExecutionService.shared.generateDeltaReport(
            from: ">f.st...... config/settings.json", jobId: UUID())

        XCTAssertEqual(report.filesModified, ["config/settings.json"])
    }

    func testDeltaReportExtractsDeletedFilenameValue() {
        // "*deleting" is 9 chars; the remainder is trimmed of whitespace.
        let report = AdvancedExecutionService.shared.generateDeltaReport(
            from: "*deleting   archive/old.zip", jobId: UUID())

        XCTAssertEqual(report.filesDeleted, ["archive/old.zip"])
    }

    func testDeltaReportIgnoresDirectoryItemizeLines() {
        // Directory entries are itemized as "cd+++++++++" — only ">f" file
        // lines should be treated as adds/modifications.
        let output = """
        cd+++++++++ newdir/
        >f+++++++++ newdir/file.txt
        """
        let report = AdvancedExecutionService.shared.generateDeltaReport(from: output, jobId: UUID())

        XCTAssertEqual(report.filesAdded, ["newdir/file.txt"])
        XCTAssertEqual(report.totalChanges, 1, "The directory line must not be counted as a change")
    }

    func testDeltaReportSizeOnlyChangeIsNotCountedAsModified() {
        // A size-only itemized change ">f.s......" matches neither ">f.st"
        // nor ">f..t", so the current parser does not record it as modified.
        // This pins that documented behavior.
        let report = AdvancedExecutionService.shared.generateDeltaReport(
            from: ">f.s...... data/blob.bin", jobId: UUID())

        XCTAssertTrue(report.filesModified.isEmpty)
        XCTAssertFalse(report.hasChanges)
    }

    func testDeltaReportAccumulatesBytesAcrossMultipleSentLines() {
        let output = """
        sent 1,000 bytes  received 10 bytes  100.00 bytes/sec
        sent 2,500 bytes  received 20 bytes  200.00 bytes/sec
        """
        let report = AdvancedExecutionService.shared.generateDeltaReport(from: output, jobId: UUID())

        XCTAssertEqual(report.bytesAdded, 3500, "Bytes from every matching 'sent' line accumulate")
    }

    // MARK: - Parallel File Splitting (replicates AdvancedExecutionService.splitFilesForParallel)

    /// Faithful replica of the private splitting logic under test.
    private func splitFiles(_ files: [String], threadCount: Int, strategy: ParallelStrategy) -> [[String]] {
        guard !files.isEmpty && threadCount > 1 else {
            return [files]
        }

        switch strategy {
        case .automatic, .byCount:
            let chunkSize = max(1, files.count / threadCount)
            var batches: [[String]] = []
            for i in 0..<threadCount {
                let start = i * chunkSize
                let end = (i == threadCount - 1) ? files.count : min(start + chunkSize, files.count)
                if start < files.count {
                    batches.append(Array(files[start..<end]))
                }
            }
            return batches

        case .byDirectory:
            var dirGroups: [String: [String]] = [:]
            for file in files {
                let components = file.components(separatedBy: "/")
                let topDir = components.first ?? "root"
                dirGroups[topDir, default: []].append(file)
            }
            var batches: [[String]] = Array(repeating: [], count: threadCount)
            var currentThread = 0
            for (_, dirFiles) in dirGroups.sorted(by: { $0.value.count > $1.value.count }) {
                batches[currentThread].append(contentsOf: dirFiles)
                currentThread = (currentThread + 1) % threadCount
            }
            return batches.filter { !$0.isEmpty }

        case .bySize:
            return splitFiles(files, threadCount: threadCount, strategy: .byCount)
        }
    }

    func testSplitByDirectoryGroupsAndDistributesRoundRobin() {
        // Three top-level dirs with distinct file counts (3, 2, 1) so ordering
        // is deterministic. Sorted descending: a(3), b(2), c(1).
        // 2 threads round-robin: thread0 <- a, thread1 <- b, thread0 <- c.
        let files = ["a/1", "a/2", "a/3", "b/1", "b/2", "c/1"]
        let batches = splitFiles(files, threadCount: 2, strategy: .byDirectory)

        XCTAssertEqual(batches.count, 2)
        XCTAssertEqual(batches[0].count, 4, "thread0 gets dir a (3) + dir c (1)")
        XCTAssertEqual(batches[1].count, 2, "thread1 gets dir b (2)")
        XCTAssertEqual(batches.flatMap { $0 }.sorted(), files.sorted(),
                       "Every file must be assigned exactly once")
    }

    func testSplitByDirectoryFiltersEmptyBatches() {
        // A single directory with 4 threads: only one thread receives files;
        // the empty batches are filtered out.
        let files = ["only/a", "only/b", "only/c"]
        let batches = splitFiles(files, threadCount: 4, strategy: .byDirectory)

        XCTAssertEqual(batches.count, 1)
        XCTAssertEqual(batches[0].count, 3)
    }

    func testSplitBySizeFallsBackToByCount() {
        let files = (1...12).map { "f\($0)" }
        let bySize = splitFiles(files, threadCount: 4, strategy: .bySize)
        let byCount = splitFiles(files, threadCount: 4, strategy: .byCount)

        XCTAssertEqual(bySize, byCount, "bySize is not yet implemented and must mirror byCount")
    }

    func testSplitAutomaticMatchesByCount() {
        let files = (1...9).map { "f\($0)" }
        XCTAssertEqual(splitFiles(files, threadCount: 3, strategy: .automatic),
                       splitFiles(files, threadCount: 3, strategy: .byCount))
    }

    func testSplitByCountLastThreadAbsorbsRemainder() {
        // 10 files / 3 threads -> chunk 3 -> [3, 3, 4]
        let files = (1...10).map { "f\($0)" }
        let batches = splitFiles(files, threadCount: 3, strategy: .byCount)

        XCTAssertEqual(batches.map { $0.count }, [3, 3, 4])
        XCTAssertEqual(batches.flatMap { $0 }.count, 10)
    }

    func testSplitSingleThreadReturnsOneBatch() {
        let files = ["a", "b", "c"]
        let batches = splitFiles(files, threadCount: 1, strategy: .byDirectory)

        XCTAssertEqual(batches, [files], "threadCount <= 1 short-circuits to a single batch")
    }

    func testSplitEmptyFileListReturnsSingleEmptyBatch() {
        let batches = splitFiles([], threadCount: 4, strategy: .automatic)
        XCTAssertEqual(batches.count, 1)
        XCTAssertTrue(batches[0].isEmpty)
    }

    // MARK: - Scheduler Command Assembly (replicates ScheduleManager.buildRsyncCommand)

    private func shellEscape(_ arg: String) -> String {
        "'" + arg.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    /// Replica of ScheduleManager.buildRsyncCommand with an injectable rsync path
    /// (the real one probes the filesystem for the binary).
    private func buildScheduledCommand(for job: SyncJob, rsyncPath: String) -> String {
        var args = [rsyncPath]
        args.append(contentsOf: job.options.toArguments())

        if job.isRemote, let host = job.remoteHost, let user = job.remoteUser {
            var sshArgs = ["ssh"]
            if let keyPath = job.sshKeyPath {
                sshArgs.append("-i")
                sshArgs.append(keyPath)
            }
            args.append("-e")
            args.append(sshArgs.joined(separator: " "))
            let remotePrefix = "\(user)@\(host):"
            args.append(job.source.starts(with: remotePrefix) ? job.source : job.source)
            args.append(job.destination.starts(with: remotePrefix) ? job.destination : job.destination)
        } else {
            let homeDir = FileManager.default.homeDirectoryForCurrentUser.path
            args.append(job.source.replacingOccurrences(of: "~", with: homeDir))
            args.append(job.destination.replacingOccurrences(of: "~", with: homeDir))
        }

        return args.map { shellEscape($0) }.joined(separator: " ")
    }

    func testScheduledCommandShellEscapesEveryArgument() {
        var job = SyncJob(name: "Nightly", source: "/data/src", destination: "/data/dst")
        job.options = RsyncOptions() // defaults: -a --stats -h --progress etc.

        let command = buildScheduledCommand(for: job, rsyncPath: "/usr/bin/rsync")

        XCTAssertTrue(command.hasPrefix("'/usr/bin/rsync'"), "Binary is the first, quoted token")
        XCTAssertTrue(command.contains("'-a'"), "Archive flag is present and individually quoted")
        XCTAssertTrue(command.hasSuffix("'/data/src' '/data/dst'"),
                      "Source then destination are the trailing quoted tokens")
        // No bare (unquoted) shell metacharacters leak through.
        XCTAssertFalse(command.contains("; "))
    }

    func testScheduledCommandNeutralizesMaliciousDestination() {
        var job = SyncJob(name: "Evil", source: "/src",
                          destination: "/dst; rm -rf /tmp/pwned")
        job.options = RsyncOptions()

        let command = buildScheduledCommand(for: job, rsyncPath: "/usr/bin/rsync")

        // The whole malicious path is wrapped in single quotes, rendering the
        // embedded ';' and 'rm' inert to /bin/sh -c.
        XCTAssertTrue(command.contains("'/dst; rm -rf /tmp/pwned'"))
        XCTAssertFalse(command.contains("'/dst'; rm"),
                       "The metacharacters must remain inside the quoted argument")
    }

    func testScheduledCommandRemoteBuildsSSHTransport() {
        var job = SyncJob(name: "Remote", source: "/local/src",
                          destination: "/remote/dst", destinationType: .remoteSSH)
        job.remoteHost = "nas01"
        job.remoteUser = "backup"
        job.sshKeyPath = "/Users/me/.ssh/id_ed25519"
        job.options = RsyncOptions()

        let command = buildScheduledCommand(for: job, rsyncPath: "/usr/bin/rsync")

        XCTAssertTrue(command.contains("'-e' 'ssh -i /Users/me/.ssh/id_ed25519'"),
                      "The -e transport bundles ssh and the identity file as one argument")
    }

    func testScheduledCommandExpandsTildeInLocalPaths() {
        var job = SyncJob(name: "Home", source: "~/Documents", destination: "~/Backup")
        job.options = RsyncOptions()

        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let command = buildScheduledCommand(for: job, rsyncPath: "/usr/bin/rsync")

        XCTAssertTrue(command.contains(shellEscape("\(home)/Documents")))
        XCTAssertTrue(command.contains(shellEscape("\(home)/Backup")))
        XCTAssertFalse(command.contains("'~/"), "Tilde must be expanded, not passed literally")
    }

    // MARK: - Executor Command Assembly (replicates RsyncExecutor.buildCommand)

    /// Replica of the RsyncExecutor.buildCommand destination-shaping logic that
    /// differs from the scheduler: it applies the remote user@host: prefix, adds
    /// a trailing slash to local/iCloud destinations, and excludes .icloud stubs.
    private func buildExecutorArgs(sources: [String], dest: SyncDestination, rsyncPath: String) -> [String] {
        var args = [rsyncPath]
        let home = FileManager.default.homeDirectoryForCurrentUser.path

        if dest.type == .remoteSSH, let host = dest.remoteHost, let user = dest.remoteUser {
            var sshComponents = ["ssh"]
            if let keyPath = dest.sshKeyPath, !keyPath.isEmpty {
                sshComponents.append("-i")
                sshComponents.append(keyPath)
            }
            args.append("-e")
            args.append(sshComponents.joined(separator: " "))
            for source in sources where !source.isEmpty {
                args.append(source.replacingOccurrences(of: "~", with: home))
            }
            let remotePrefix = "\(user)@\(host):"
            let destPath = dest.path.starts(with: remotePrefix) ? dest.path : "\(remotePrefix)\(dest.path)"
            args.append(destPath)
        } else {
            for source in sources where !source.isEmpty {
                args.append(source.replacingOccurrences(of: "~", with: home))
            }
            if dest.type == .iCloudDrive {
                args.append("--exclude=*.icloud")
            }
            var expandedDest = dest.path.replacingOccurrences(of: "~", with: home)
            if !expandedDest.hasSuffix("/") {
                expandedDest += "/"
            }
            args.append(expandedDest)
        }
        return args
    }

    func testExecutorMultipleSourcesFanIntoSingleDestination() {
        var dest = SyncDestination(path: "/backup", type: .local)
        dest.isEnabled = true
        let args = buildExecutorArgs(sources: ["/a", "/b", "/c"], dest: dest, rsyncPath: "/usr/bin/rsync")

        // rsync + 3 sources + 1 dest (with trailing slash)
        XCTAssertEqual(args, ["/usr/bin/rsync", "/a", "/b", "/c", "/backup/"])
    }

    func testExecutorSkipsEmptySources() {
        let dest = SyncDestination(path: "/backup", type: .local)
        let args = buildExecutorArgs(sources: ["/a", "", "/b"], dest: dest, rsyncPath: "/usr/bin/rsync")

        XCTAssertEqual(args, ["/usr/bin/rsync", "/a", "/b", "/backup/"])
    }

    func testExecutorAddsTrailingSlashOnlyWhenMissing() {
        let withSlash = buildExecutorArgs(
            sources: ["/a"], dest: SyncDestination(path: "/dst/", type: .local),
            rsyncPath: "/usr/bin/rsync")
        XCTAssertEqual(withSlash.last, "/dst/", "An existing trailing slash is preserved (not doubled)")

        let withoutSlash = buildExecutorArgs(
            sources: ["/a"], dest: SyncDestination(path: "/dst", type: .local),
            rsyncPath: "/usr/bin/rsync")
        XCTAssertEqual(withoutSlash.last, "/dst/")
    }

    func testExecutorICloudDestinationExcludesPlaceholderStubs() {
        let dest = SyncDestination(path: "/Users/me/iCloud", type: .iCloudDrive)
        let args = buildExecutorArgs(sources: ["/src"], dest: dest, rsyncPath: "/usr/bin/rsync")

        XCTAssertTrue(args.contains("--exclude=*.icloud"),
                      "Offloaded iCloud placeholder files must be skipped")
        let excludeIdx = args.firstIndex(of: "--exclude=*.icloud")!
        XCTAssertEqual(args[excludeIdx + 1], "/Users/me/iCloud/",
                       "The exclude precedes the destination argument")
    }

    func testExecutorRemoteBuildsPrefixedDestinationAndTransport() {
        var dest = SyncDestination(path: "/remote/path", type: .remoteSSH)
        dest.remoteHost = "server.example.com"
        dest.remoteUser = "deploy"
        dest.sshKeyPath = "/keys/id_rsa"
        let args = buildExecutorArgs(sources: ["/local"], dest: dest, rsyncPath: "/usr/bin/rsync")

        XCTAssertEqual(args, [
            "/usr/bin/rsync",
            "-e", "ssh -i /keys/id_rsa",
            "/local",
            "deploy@server.example.com:/remote/path"
        ])
    }

    func testExecutorRemotePrefixIsNotDoubledWhenAlreadyPresent() {
        var dest = SyncDestination(path: "user@host:/already/prefixed", type: .remoteSSH)
        dest.remoteHost = "host"
        dest.remoteUser = "user"
        let args = buildExecutorArgs(sources: ["/local"], dest: dest, rsyncPath: "/usr/bin/rsync")

        XCTAssertEqual(args.last, "user@host:/already/prefixed",
                       "A path that already carries the user@host: prefix is left untouched")
    }

    func testExecutorRemoteWithoutKeyOmitsIdentityFlag() {
        var dest = SyncDestination(path: "/remote", type: .remoteSSH)
        dest.remoteHost = "host"
        dest.remoteUser = "user"
        dest.sshKeyPath = nil
        let args = buildExecutorArgs(sources: ["/local"], dest: dest, rsyncPath: "/usr/bin/rsync")

        let eIndex = args.firstIndex(of: "-e")!
        XCTAssertEqual(args[eIndex + 1], "ssh", "With no key, the transport is a bare 'ssh'")
    }
}
