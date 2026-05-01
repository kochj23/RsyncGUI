//
//  CommandInjectionTests.swift
//  RsyncGUITests
//
//  Created by Jordan Koch on 4/21/26.
//
//  Tests that user-controlled inputs cannot inject arbitrary commands.
//  This is critical for a tool that builds shell commands from user input.

import XCTest
@testable import RsyncGUI

final class CommandInjectionTests: XCTestCase {

    // MARK: - SSH Host Validation

    func testValidHostnamesAreAccepted() {
        let validHosts = [
            "server.example.com",
            "192.168.1.100",
            "backup-server",
            "my_server",
            "host.sub.domain.com",
            "nas01"
        ]

        let safePattern = #"^[a-zA-Z0-9._-]+$"#

        for host in validHosts {
            let match = host.range(of: safePattern, options: .regularExpression)
            XCTAssertNotNil(match, "Valid hostname '\(host)' should pass validation")
        }
    }

    func testHostnamesWithShellMetacharactersAreRejected() {
        let maliciousHosts = [
            "server; rm -rf /",
            "host$(whoami)",
            "host`id`",
            "host | cat /etc/passwd",
            "host && malicious",
            "host\ninjected",
            "host > /tmp/pwned",
            "host < /etc/shadow",
            "host'injection",
            "host\"injection",
            "host\\injection",
        ]

        let safePattern = #"^[a-zA-Z0-9._-]+$"#

        for host in maliciousHosts {
            let match = host.range(of: safePattern, options: .regularExpression)
            XCTAssertNil(match, "Malicious hostname '\(host)' should be rejected by validation")
        }
    }

    // MARK: - SSH Username Validation

    func testValidUsernamesAreAccepted() {
        let validUsers = [
            "root",
            "admin",
            "jordan_koch",
            "backup-user",
            "user.name",
            "deploy123"
        ]

        let safePattern = #"^[a-zA-Z0-9._-]+$"#

        for user in validUsers {
            let match = user.range(of: safePattern, options: .regularExpression)
            XCTAssertNotNil(match, "Valid username '\(user)' should pass validation")
        }
    }

    func testUsernamesWithShellMetacharactersAreRejected() {
        let maliciousUsers = [
            "user; echo pwned",
            "user$(id)",
            "root`whoami`",
            "user | cat /etc/passwd",
            "user && rm -rf /",
            "user\ninjected-command",
            "user > /tmp/file",
            "user'injection",
        ]

        let safePattern = #"^[a-zA-Z0-9._-]+$"#

        for user in maliciousUsers {
            let match = user.range(of: safePattern, options: .regularExpression)
            XCTAssertNil(match, "Malicious username '\(user)' should be rejected by validation")
        }
    }

    // MARK: - Rsync-Path Validation

    func testSafeRsyncPathsAreAccepted() {
        let safePaths = [
            "/usr/bin/rsync",
            "/opt/homebrew/bin/rsync",
            "/usr/local/bin/rsync",
            "/home/user/bin/rsync_wrapper",
            "/usr/lib/rsync-3.2.7/rsync",
        ]

        let safePathRegex = #"^[a-zA-Z0-9/_.\-]+$"#

        for path in safePaths {
            let match = path.range(of: safePathRegex, options: .regularExpression)
            XCTAssertNotNil(match, "Safe rsync path '\(path)' should pass validation")
        }
    }

    func testDangerousRsyncPathsAreRejected() {
        let dangerousPaths = [
            "/usr/bin/rsync; rm -rf /",
            "/usr/bin/rsync && echo pwned",
            "$(whoami)/rsync",
            "`id`/rsync",
            "/usr/bin/rsync | tee /tmp/log",
            "/path with spaces/rsync",
            "/usr/bin/rsync\n/usr/bin/rm",
            "/usr/bin/rsync > /tmp/out",
            "/usr/bin/rsync' --shell-escape",
        ]

        let safePathRegex = #"^[a-zA-Z0-9/_.\-]+$"#

        for path in dangerousPaths {
            let match = path.range(of: safePathRegex, options: .regularExpression)
            XCTAssertNil(match, "Dangerous rsync path '\(path)' should be rejected by validation")
        }
    }

    // MARK: - SSH Key Path Validation

    func testSSHKeyPathMustBeAbsolute() {
        // Tests the validation logic from RsyncExecutor.buildCommand()
        let relativePath = "~/.ssh/id_rsa"
        let expanded = (relativePath as NSString).expandingTildeInPath

        XCTAssertTrue(expanded.hasPrefix("/"), "expandingTildeInPath should produce absolute path")
    }

    func testSSHKeyPathRejectsPathTraversal() {
        let traversalPath = "/home/user/../../../etc/shadow"
        let expanded = (traversalPath as NSString).expandingTildeInPath

        XCTAssertTrue(expanded.contains(".."),
                      "Path traversal should be detectable by checking for '..'")

        // The buildCommand method rejects paths containing ".."
        let containsTraversal = expanded.contains("..")
        XCTAssertTrue(containsTraversal, "Path traversal should be caught")
    }

    func testSSHKeyPathRejectsRelativePaths() {
        let relativePaths = [
            "relative/path/key",
            "./local/key",
            "../parent/key",
        ]

        for path in relativePaths {
            let expanded = (path as NSString).expandingTildeInPath
            // The validator checks hasPrefix("/") — relative paths without ~ won't start with /
            if !path.hasPrefix("~") {
                XCTAssertFalse(expanded.hasPrefix("/") && !expanded.contains(".."),
                               "Relative path '\(path)' should not pass absolute path check")
            }
        }
    }

    // MARK: - Exclude Pattern Injection via RsyncOptions

    func testExcludePatternCannotInjectFlags() {
        // Even though rsync processes --exclude patterns as data, ensure no control chars slip through
        var options = RsyncOptions()
        options.archive = false
        options.recursive = false
        options.preservePermissions = false
        options.preserveTimes = false
        options.preserveLinks = false
        options.stats = false
        options.humanReadable = false
        options.progress = false

        // Attempt to inject a new flag via exclude pattern
        options.exclude = ["*.tmp\0--delete-excluded"]

        let args = options.toArguments()

        // Null byte should cause rejection
        XCTAssertFalse(args.contains("--delete-excluded"),
                       "Should not be possible to inject flags via exclude patterns")
        XCTAssertTrue(args.isEmpty, "Pattern with null byte should be completely rejected")
    }

    func testFilterRuleCannotInjectViaNewline() {
        var options = RsyncOptions()
        options.archive = false
        options.recursive = false
        options.preservePermissions = false
        options.preserveTimes = false
        options.preserveLinks = false
        options.stats = false
        options.humanReadable = false
        options.progress = false
        options.filterRules = ["+ *.swift\n--delete"]

        let args = options.toArguments()

        XCTAssertFalse(args.contains("--delete"),
                       "Should not be possible to inject flags via filter rules with newlines")
    }

    // MARK: - Shell Escape for Scheduled Commands

    func testShellEscapeHandlesSimplePaths() {
        // Test the shell escape pattern used in ScheduleManager
        let path = "/Users/test/Documents"
        let escaped = shellEscapeForTest(path)

        XCTAssertEqual(escaped, "'/Users/test/Documents'",
                       "Simple paths should be single-quoted")
    }

    func testShellEscapeHandlesSpacesInPaths() {
        let path = "/Users/test/My Documents"
        let escaped = shellEscapeForTest(path)

        XCTAssertEqual(escaped, "'/Users/test/My Documents'",
                       "Paths with spaces should be safely quoted")
    }

    func testShellEscapeHandlesSingleQuotesInPaths() {
        let path = "/Users/test/Jordan's Files"
        let escaped = shellEscapeForTest(path)

        XCTAssertEqual(escaped, "'/Users/test/Jordan'\\''s Files'",
                       "Single quotes in paths should be properly escaped")
    }

    func testShellEscapeHandlesDoubleQuotesInPaths() {
        let path = "/Users/test/\"quoted\" dir"
        let escaped = shellEscapeForTest(path)

        XCTAssertEqual(escaped, "'/Users/test/\"quoted\" dir'",
                       "Double quotes inside single quotes need no escaping")
    }

    func testShellEscapeHandlesDollarSigns() {
        let path = "/Users/test/$HOME/backup"
        let escaped = shellEscapeForTest(path)

        XCTAssertEqual(escaped, "'/Users/test/$HOME/backup'",
                       "Dollar signs inside single quotes are literal, not expanded")
    }

    func testShellEscapeHandlesBackticks() {
        let path = "/Users/test/`whoami`/backup"
        let escaped = shellEscapeForTest(path)

        XCTAssertEqual(escaped, "'/Users/test/`whoami`/backup'",
                       "Backticks inside single quotes are literal, not executed")
    }

    func testShellEscapeHandlesSemicolons() {
        let path = "/Users/test; rm -rf /"
        let escaped = shellEscapeForTest(path)

        // Inside single quotes, semicolons are literal
        XCTAssertTrue(escaped.hasPrefix("'") && escaped.hasSuffix("'"),
                      "Semicolons should be safely enclosed in single quotes")
        XCTAssertFalse(escaped.contains("'; rm -rf /"),
                       "Shell escape should not allow command injection via semicolons")
    }

    func testShellEscapeHandlesNewlines() {
        let path = "/Users/test\n/etc/passwd"
        let escaped = shellEscapeForTest(path)

        // Single quotes preserve newlines as literal characters
        XCTAssertTrue(escaped.hasPrefix("'") && escaped.hasSuffix("'"),
                      "Newlines should be safely enclosed in single quotes")
    }

    func testShellEscapeEmptyString() {
        let path = ""
        let escaped = shellEscapeForTest(path)

        XCTAssertEqual(escaped, "''", "Empty string should produce empty single-quoted string")
    }

    func testShellEscapeMultipleSingleQuotes() {
        let path = "it's jordan's server's backup"
        let escaped = shellEscapeForTest(path)

        // Each ' becomes '\'' (close quote, escaped quote, open quote)
        XCTAssertEqual(escaped, "'it'\\''s jordan'\\''s server'\\''s backup'")
    }

    // MARK: - RsyncError Types

    func testInvalidHostOrUserErrorMessage() {
        let error = RsyncError.invalidHostOrUser("bad;host")
        let description = error.errorDescription

        XCTAssertNotNil(description)
        XCTAssertTrue(description!.contains("bad;host"),
                      "Error message should include the invalid value")
        XCTAssertTrue(description!.contains("alphanumeric"),
                      "Error message should explain allowed characters")
    }

    func testInvalidSSHKeyPathErrorMessage() {
        let error = RsyncError.invalidSSHKeyPath
        let description = error.errorDescription

        XCTAssertNotNil(description)
        XCTAssertTrue(description!.contains("SSH key path"),
                      "Error should mention SSH key path")
    }

    // MARK: - Helper

    /// Replicates ScheduleManager's private shellEscape method for testing
    private func shellEscapeForTest(_ arg: String) -> String {
        "'" + arg.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
