//
//  RsyncOptionsTests.swift
//  RsyncGUITests
//
//  Created by Jordan Koch on 4/21/26.
//

import XCTest
@testable import RsyncGUI

final class RsyncOptionsTests: XCTestCase {

    /// Creates an RsyncOptions with ALL flags disabled and ALL optionals nil.
    /// Use this as a blank slate when testing individual options in isolation.
    private func minimalOptions() -> RsyncOptions {
        var opts = RsyncOptions()
        opts.archive = false
        opts.recursive = false
        opts.preservePermissions = false
        opts.preserveTimes = false
        opts.preserveLinks = false
        opts.stats = false
        opts.humanReadable = false
        opts.progress = false
        return opts
    }

    // MARK: - Default Options

    func testDefaultOptionsProduceExpectedArguments() {
        let options = RsyncOptions()
        let args = options.toArguments()

        // Default: archive=true, stats=true, humanReadable=true, progress=true
        XCTAssertTrue(args.contains("-a"), "Default options should include archive flag")
        XCTAssertTrue(args.contains("--stats"), "Default options should include --stats")
        XCTAssertTrue(args.contains("-h"), "Default options should include -h (human-readable)")
        XCTAssertTrue(args.contains("--progress"), "Default options should include --progress")

        // These should NOT be present by default
        XCTAssertFalse(args.contains("-v"), "Verbose should be off by default")
        XCTAssertFalse(args.contains("-z"), "Compress should be off by default")
        XCTAssertFalse(args.contains("--delete"), "Delete should be off by default")
        XCTAssertFalse(args.contains("-n"), "Dry run should be off by default")
    }

    func testEmptyOptionsProduceMinimalArguments() {
        let options = minimalOptions()

        let args = options.toArguments()
        XCTAssertTrue(args.isEmpty, "All options disabled should produce empty argument list, got: \(args)")
    }

    // MARK: - Archive Mode Interaction

    func testArchiveModeSupersetsPreserveFlags() {
        // When archive is on, individual preserve flags under !archive block should NOT appear
        var options = RsyncOptions()
        options.archive = true
        options.preservePermissions = true
        options.preserveOwner = true
        options.preserveGroup = true
        options.preserveTimes = true
        options.preserveLinks = true

        let args = options.toArguments()

        // -a implies -rlptgoD, so individual -p -o -g -t -l should not appear
        XCTAssertTrue(args.contains("-a"))
        XCTAssertFalse(args.contains("-p"), "Archive mode already includes -p")
        XCTAssertFalse(args.contains("-o"), "Archive mode already includes -o")
        XCTAssertFalse(args.contains("-g"), "Archive mode already includes -g")
        XCTAssertFalse(args.contains("-t"), "Archive mode already includes -t")
        XCTAssertFalse(args.contains("-l"), "Archive mode already includes -l")
    }

    func testNoArchiveEmitsIndividualPreserveFlags() {
        var options = minimalOptions()
        options.preservePermissions = true
        options.preserveOwner = true
        options.preserveGroup = true
        options.preserveTimes = true
        options.preserveLinks = true

        let args = options.toArguments()

        XCTAssertFalse(args.contains("-a"))
        XCTAssertTrue(args.contains("-p"), "Without archive, -p should appear")
        XCTAssertTrue(args.contains("-o"), "Without archive, -o should appear")
        XCTAssertTrue(args.contains("-g"), "Without archive, -g should appear")
        XCTAssertTrue(args.contains("-t"), "Without archive, -t should appear")
        XCTAssertTrue(args.contains("-l"), "Without archive, -l should appear")
    }

    func testRecursiveOnlyAppearsWithoutArchive() {
        var options = RsyncOptions()
        options.archive = true
        options.recursive = true
        options.stats = false
        options.humanReadable = false
        options.progress = false

        var args = options.toArguments()
        XCTAssertFalse(args.contains("-r"), "With archive=true, -r should not appear separately")

        options.archive = false
        options.preservePermissions = false
        options.preserveTimes = false
        options.preserveLinks = false
        args = options.toArguments()
        XCTAssertTrue(args.contains("-r"), "With archive=false, -r should appear when recursive=true")
    }

    // MARK: - Delete Options

    func testDeleteFlags() {
        var options = minimalOptions()
        options.delete = true
        options.deleteBefore = true
        options.deleteExcluded = true
        options.forceDelete = true
        options.maxDelete = 100

        let args = options.toArguments()

        XCTAssertTrue(args.contains("--delete"))
        XCTAssertTrue(args.contains("--delete-before"))
        XCTAssertTrue(args.contains("--delete-excluded"))
        XCTAssertTrue(args.contains("--force"))
        XCTAssertTrue(args.contains("--max-delete=100"))
    }

    func testDeleteMutuallyExclusiveTimingFlags() {
        // All delete timing flags can be set simultaneously in the model.
        // rsync itself handles conflicts, but we should verify they all get emitted.
        var options = minimalOptions()
        options.deleteBefore = true
        options.deleteDuring = true
        options.deleteDelay = true
        options.deleteAfter = true

        let args = options.toArguments()

        XCTAssertTrue(args.contains("--delete-before"))
        XCTAssertTrue(args.contains("--delete-during"))
        XCTAssertTrue(args.contains("--delete-delay"))
        XCTAssertTrue(args.contains("--delete-after"))
    }

    // MARK: - Transfer Options

    func testTransferOptions() {
        var options = minimalOptions()
        options.update = true
        options.existing = true
        options.ignoreExisting = true
        options.removeSourceFiles = true
        options.partial = true
        options.partialDir = ".rsync-partial"
        options.inplace = true

        let args = options.toArguments()

        XCTAssertTrue(args.contains("-u"))
        XCTAssertTrue(args.contains("--existing"))
        XCTAssertTrue(args.contains("--ignore-existing"))
        XCTAssertTrue(args.contains("--remove-source-files"))
        XCTAssertTrue(args.contains("--partial"))
        XCTAssertTrue(args.contains("--partial-dir=.rsync-partial"))
        XCTAssertTrue(args.contains("--inplace"))
    }

    // MARK: - Filter / Exclude / Include Patterns

    func testExcludePatterns() {
        var options = minimalOptions()
        options.exclude = ["*.tmp", ".DS_Store", "node_modules/"]

        let args = options.toArguments()

        XCTAssertTrue(args.contains("--exclude=*.tmp"))
        XCTAssertTrue(args.contains("--exclude=.DS_Store"))
        XCTAssertTrue(args.contains("--exclude=node_modules/"))
    }

    func testIncludePatterns() {
        var options = minimalOptions()
        options.include = ["*.swift", "*.h"]

        let args = options.toArguments()

        XCTAssertTrue(args.contains("--include=*.swift"))
        XCTAssertTrue(args.contains("--include=*.h"))
    }

    func testFilterRules() {
        var options = minimalOptions()
        options.filterRules = ["+ *.swift", "- *.o"]

        let args = options.toArguments()

        XCTAssertTrue(args.contains("--filter=+ *.swift"))
        XCTAssertTrue(args.contains("--filter=- *.o"))
    }

    func testExcludeFromFile() {
        var options = minimalOptions()
        options.excludeFrom = "/path/to/excludes.txt"

        let args = options.toArguments()

        XCTAssertTrue(args.contains("--exclude-from=/path/to/excludes.txt"))
    }

    func testIncludeFromFile() {
        var options = minimalOptions()
        options.includeFrom = "/path/to/includes.txt"

        let args = options.toArguments()

        XCTAssertTrue(args.contains("--include-from=/path/to/includes.txt"))
    }

    func testCVSExclude() {
        var options = minimalOptions()
        options.cvsExclude = true

        let args = options.toArguments()

        XCTAssertTrue(args.contains("-C"))
    }

    // MARK: - Filter Sanitization (Command Injection Prevention)

    func testExcludePatternsWithControlCharactersAreRejected() {
        var options = minimalOptions()

        // Null byte injection attempt
        options.exclude = ["*.tmp\0; rm -rf /"]

        let args = options.toArguments()

        // The pattern with the null byte should be rejected entirely
        XCTAssertTrue(args.isEmpty, "Patterns with null bytes should be rejected, got: \(args)")
    }

    func testExcludePatternsWithNewlinesAreRejected() {
        var options = minimalOptions()
        options.exclude = ["*.tmp\n--delete"]

        let args = options.toArguments()

        XCTAssertTrue(args.isEmpty, "Patterns with newlines should be rejected, got: \(args)")
    }

    func testExcludePatternsWithCarriageReturnAreRejected() {
        var options = minimalOptions()
        options.exclude = ["test\rpattern"]

        let args = options.toArguments()

        XCTAssertTrue(args.isEmpty, "Patterns with carriage returns should be rejected")
    }

    func testExcludePatternsWithDELCharacterAreRejected() {
        var options = minimalOptions()
        options.exclude = ["test\u{7F}pattern"]

        let args = options.toArguments()

        XCTAssertTrue(args.isEmpty, "Patterns with DEL character should be rejected")
    }

    func testFilterRulesWithControlCharactersAreRejected() {
        var options = minimalOptions()
        options.filterRules = ["+ *.swift\0; echo pwned"]

        let args = options.toArguments()

        XCTAssertTrue(args.isEmpty, "Filter rules with null bytes should be rejected")
    }

    func testIncludePatternsWithControlCharactersAreRejected() {
        var options = minimalOptions()
        options.include = ["\u{01}malicious"]

        let args = options.toArguments()

        XCTAssertTrue(args.isEmpty, "Include patterns with control characters should be rejected")
    }

    func testTabsInPatternsAreAllowed() {
        // The sanitizer explicitly allows tabs
        var options = minimalOptions()
        options.exclude = ["dir\twith\ttabs"]

        let args = options.toArguments()

        XCTAssertEqual(args.count, 1)
        XCTAssertTrue(args.contains("--exclude=dir\twith\ttabs"), "Tabs should be allowed in patterns")
    }

    func testMixedValidAndInvalidPatternsOnlyEmitsValid() {
        var options = minimalOptions()
        options.exclude = ["*.tmp", "bad\0pattern", "*.log", "\nmoreinjection"]

        let args = options.toArguments()

        XCTAssertEqual(args.count, 2, "Should only emit 2 valid patterns, got \(args.count): \(args)")
        XCTAssertTrue(args.contains("--exclude=*.tmp"))
        XCTAssertTrue(args.contains("--exclude=*.log"))
    }

    // MARK: - Bandwidth & Performance Options

    func testBandwidthLimit() {
        var options = minimalOptions()
        options.bandwidth = 1000

        let args = options.toArguments()

        XCTAssertTrue(args.contains("--bwlimit=1000"))
    }

    func testTimeoutOption() {
        var options = minimalOptions()
        options.timeout = 60

        let args = options.toArguments()

        XCTAssertTrue(args.contains("--timeout=60"))
    }

    func testBlockSizeOption() {
        var options = minimalOptions()
        options.blockSize = 128

        let args = options.toArguments()

        XCTAssertTrue(args.contains("-B=128"))
    }

    func testWholeFileAndNoWholeFileFlags() {
        var options = minimalOptions()
        options.wholeFile = true

        var args = options.toArguments()
        XCTAssertTrue(args.contains("-W"))

        options.wholeFile = false
        options.noWholeFile = true
        args = options.toArguments()
        XCTAssertTrue(args.contains("--no-whole-file"))
    }

    // MARK: - Comparison Options

    func testComparisonOptions() {
        var options = minimalOptions()
        options.ignoreTime = true
        options.sizeOnly = true
        options.checksum = true
        options.fuzzy = true

        let args = options.toArguments()

        XCTAssertTrue(args.contains("-I"))
        XCTAssertTrue(args.contains("--size-only"))
        XCTAssertTrue(args.contains("-c"))
        XCTAssertTrue(args.contains("-y"))
    }

    // MARK: - SSH & Remote Options

    func testRsyncPathWithSafeCharacters() {
        var options = minimalOptions()
        options.rsyncPath = "/usr/local/bin/rsync"

        let args = options.toArguments()

        XCTAssertTrue(args.contains("--rsync-path=/usr/local/bin/rsync"))
    }

    func testRsyncPathWithUnsafeCharactersIsRejected() {
        var options = minimalOptions()
        options.rsyncPath = "/usr/bin/rsync; rm -rf /"

        let args = options.toArguments()

        // Should not contain the rsync-path since it has semicolons and spaces
        XCTAssertFalse(args.contains { $0.contains("rsync-path") },
                       "rsync-path with shell metacharacters should be rejected")
    }

    func testRsyncPathWithSpacesIsRejected() {
        var options = minimalOptions()
        options.rsyncPath = "/path with spaces/rsync"

        let args = options.toArguments()

        XCTAssertFalse(args.contains { $0.contains("rsync-path") },
                       "rsync-path with spaces should be rejected by safe path regex")
    }

    func testRsyncPathWithBackticksIsRejected() {
        var options = minimalOptions()
        options.rsyncPath = "`whoami`/rsync"

        let args = options.toArguments()

        XCTAssertFalse(args.contains { $0.contains("rsync-path") },
                       "rsync-path with backticks should be rejected")
    }

    func testRsyncPathWithDollarSignIsRejected() {
        var options = minimalOptions()
        options.rsyncPath = "$(whoami)/rsync"

        let args = options.toArguments()

        XCTAssertFalse(args.contains { $0.contains("rsync-path") },
                       "rsync-path with $() should be rejected")
    }

    func testPortOption() {
        var options = minimalOptions()
        options.port = 2222

        let args = options.toArguments()

        XCTAssertTrue(args.contains("--port=2222"))
    }

    // MARK: - Backup Options

    func testBackupOptions() {
        var options = minimalOptions()
        options.backup = true
        options.backupDir = "/backup/dir"
        options.suffix = ".bak"

        let args = options.toArguments()

        XCTAssertTrue(args.contains("-b"))
        XCTAssertTrue(args.contains("--backup-dir=/backup/dir"))
        XCTAssertTrue(args.contains("--suffix=.bak"))
    }

    // MARK: - Ownership & Permissions

    func testChmodOption() {
        var options = minimalOptions()
        options.chmod = "Du+rwx,go-rwx"

        let args = options.toArguments()

        XCTAssertTrue(args.contains("--chmod=Du+rwx,go-rwx"))
    }

    func testFakeSuperOption() {
        var options = minimalOptions()
        options.fakeSuper = true

        let args = options.toArguments()

        XCTAssertTrue(args.contains("--fake-super"))
    }

    // MARK: - Miscellaneous Options

    func testMinMaxSizeOptions() {
        var options = minimalOptions()
        options.minSize = "1K"
        options.maxSize = "100M"

        let args = options.toArguments()

        XCTAssertTrue(args.contains("--min-size=1K"))
        XCTAssertTrue(args.contains("--max-size=100M"))
    }

    func testLinkDestOption() {
        var options = minimalOptions()
        options.linkDest = "/previous-backup"

        let args = options.toArguments()

        XCTAssertTrue(args.contains("--link-dest=/previous-backup"))
    }

    // MARK: - Network Options

    func testIPv4AndIPv6Flags() {
        var options = minimalOptions()
        options.ipv4 = true

        var args = options.toArguments()
        XCTAssertTrue(args.contains("-4"))

        options.ipv4 = false
        options.ipv6 = true
        args = options.toArguments()
        XCTAssertTrue(args.contains("-6"))
    }

    func testConnectionTimeout() {
        var options = minimalOptions()
        options.contimeout = 30

        let args = options.toArguments()

        XCTAssertTrue(args.contains("--contimeout=30"))
    }

    // MARK: - Advanced Transfer Options

    func testOneFileSystem() {
        var options = minimalOptions()
        options.oneFileSystem = true

        let args = options.toArguments()

        XCTAssertTrue(args.contains("-x"))
    }

    func testSparseFileHandling() {
        var options = minimalOptions()
        options.sparse = true

        let args = options.toArguments()

        XCTAssertTrue(args.contains("-S"))
    }

    func testFilesFromOption() {
        var options = minimalOptions()
        options.filesFrom = "/tmp/file-list.txt"
        options.from0 = true

        let args = options.toArguments()

        XCTAssertTrue(args.contains("--files-from=/tmp/file-list.txt"))
        XCTAssertTrue(args.contains("--from0"))
    }

    // MARK: - Logging Options

    func testLogFileOptions() {
        var options = minimalOptions()
        options.logFile = "/var/log/rsync.log"
        options.logFileFormat = "%t %f %l"

        let args = options.toArguments()

        XCTAssertTrue(args.contains("--log-file=/var/log/rsync.log"))
        XCTAssertTrue(args.contains("--log-file-format=%t %f %l"))
    }

    // MARK: - Checksum Options

    func testChecksumChoice() {
        var options = minimalOptions()
        options.checksumChoice = "xxh128"

        let args = options.toArguments()

        XCTAssertTrue(args.contains("--checksum-choice=xxh128"))
    }

    // MARK: - Comprehensive Options Combination

    func testTypicalBackupJobOptions() {
        var options = RsyncOptions()
        // Typical backup job configuration
        options.archive = true
        options.verbose = true
        options.compress = true
        options.delete = true
        options.exclude = [".DS_Store", "Thumbs.db", "*.tmp"]
        options.bandwidth = 5000
        options.stats = true
        options.humanReadable = true
        options.progress = true

        let args = options.toArguments()

        XCTAssertTrue(args.contains("-a"))
        XCTAssertTrue(args.contains("-v"))
        XCTAssertTrue(args.contains("-z"))
        XCTAssertTrue(args.contains("--delete"))
        XCTAssertTrue(args.contains("--exclude=.DS_Store"))
        XCTAssertTrue(args.contains("--exclude=Thumbs.db"))
        XCTAssertTrue(args.contains("--exclude=*.tmp"))
        XCTAssertTrue(args.contains("--bwlimit=5000"))
        XCTAssertTrue(args.contains("--stats"))
        XCTAssertTrue(args.contains("-h"))
        XCTAssertTrue(args.contains("--progress"))
    }

    func testDryRunOption() {
        var options = minimalOptions()
        options.dryRun = true

        let args = options.toArguments()

        XCTAssertTrue(args.contains("-n"))
    }

    // MARK: - Codable Roundtrip

    func testCodableRoundtrip() throws {
        var options = RsyncOptions()
        options.archive = true
        options.verbose = true
        options.compress = true
        options.delete = true
        options.exclude = ["*.tmp", ".git/"]
        options.bandwidth = 2500
        options.port = 22
        options.backup = true
        options.suffix = ".old"

        let encoder = JSONEncoder()
        let data = try encoder.encode(options)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(RsyncOptions.self, from: data)

        // Verify the roundtrip preserved all values
        XCTAssertEqual(options.toArguments(), decoded.toArguments(),
                       "Codable roundtrip should produce identical arguments")
    }

    // MARK: - Nil Optional Values

    func testNilOptionalsProduceNoArguments() {
        let options = minimalOptions()

        // All optional string/int fields default to nil
        XCTAssertNil(options.maxDelete)
        XCTAssertNil(options.partialDir)
        XCTAssertNil(options.bandwidth)
        XCTAssertNil(options.timeout)
        XCTAssertNil(options.blockSize)
        XCTAssertNil(options.port)
        XCTAssertNil(options.rsh)
        XCTAssertNil(options.rsyncPath)

        let args = options.toArguments()
        XCTAssertTrue(args.isEmpty, "All-nil options should produce no arguments")
    }

    // MARK: - Extended Attribute Options

    func testPreserveACLsAndXattrs() {
        var options = minimalOptions()
        options.preserveAcls = true
        options.preserveXattrs = true
        options.preserveExecutability = true

        let args = options.toArguments()

        XCTAssertTrue(args.contains("-A"))
        XCTAssertTrue(args.contains("-X"))
        XCTAssertTrue(args.contains("-E"))
    }

    // MARK: - Symlink Options

    func testSymlinkOptions() {
        var options = minimalOptions()
        options.copyLinks = true
        options.safeLinks = true
        options.hardLinks = true

        let args = options.toArguments()

        XCTAssertTrue(args.contains("-L"))
        XCTAssertTrue(args.contains("--safe-links"))
        XCTAssertTrue(args.contains("-H"))
    }

    // MARK: - Output Options

    func testQuietOption() {
        var options = minimalOptions()
        options.quiet = true

        let args = options.toArguments()

        XCTAssertTrue(args.contains("-q"))
    }

    func testItemizeOption() {
        var options = minimalOptions()
        options.itemize = true

        let args = options.toArguments()

        XCTAssertTrue(args.contains("-i"))
    }

    func testOutFormatOption() {
        var options = minimalOptions()
        options.outFormat = "%t %f %b"

        let args = options.toArguments()

        XCTAssertTrue(args.contains("--out-format=%t %f %b"))
    }

    // MARK: - Batch Options

    func testBatchReadWrite() {
        var options = minimalOptions()
        options.readBatch = "/tmp/batch-in"
        options.writeBatch = "/tmp/batch-out"

        let args = options.toArguments()

        XCTAssertTrue(args.contains("--read-batch=/tmp/batch-in"))
        XCTAssertTrue(args.contains("--write-batch=/tmp/batch-out"))
    }

    // MARK: - Iconv Option

    func testIconvOption() {
        var options = minimalOptions()
        options.iconv = "UTF-8"

        let args = options.toArguments()

        XCTAssertTrue(args.contains("--iconv=UTF-8"))
    }

    // MARK: - Protect Args

    func testProtectArgsOption() {
        var options = minimalOptions()
        options.protectArgs = true

        let args = options.toArguments()

        XCTAssertTrue(args.contains("--protect-args"))
    }
}
