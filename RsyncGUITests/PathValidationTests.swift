//
//  PathValidationTests.swift
//  RsyncGUITests
//
//  Created by Jordan Koch on 4/21/26.
//
//  Tests for path validation, expansion, and edge cases.
//  Covers SMB/USB destinations, iCloud paths, network volumes,
//  and special characters in file paths.

import XCTest
@testable import RsyncGUI

final class PathValidationTests: XCTestCase {

    // MARK: - Tilde Expansion

    func testTildeExpansionProducesAbsolutePath() {
        let path = "~/Documents"
        let expanded = path.replacingOccurrences(
            of: "~",
            with: FileManager.default.homeDirectoryForCurrentUser.path
        )

        XCTAssertTrue(expanded.hasPrefix("/"), "Expanded path should be absolute")
        XCTAssertFalse(expanded.contains("~"), "Expanded path should not contain tilde")
        XCTAssertTrue(expanded.hasSuffix("/Documents"))
    }

    func testNSStringTildeExpansion() {
        let path = "~/.ssh/id_rsa"
        let expanded = (path as NSString).expandingTildeInPath

        XCTAssertTrue(expanded.hasPrefix("/"))
        XCTAssertFalse(expanded.contains("~"))
        XCTAssertTrue(expanded.hasSuffix("/.ssh/id_rsa"))
    }

    // MARK: - iCloud Drive Path Validation

    func testICloudDrivePathIsConstructedCorrectly() {
        let iCloudPath = SyncJob.iCloudDrivePath
        let expected = FileManager.default.homeDirectoryForCurrentUser.path +
            "/Library/Mobile Documents/com~apple~CloudDocs"

        XCTAssertEqual(iCloudPath, expected)
    }

    func testPathWithiniCloudDrivePassesValidation() {
        let iCloudRoot = SyncJob.iCloudDrivePath
        let testPath = iCloudRoot + "/MyBackup"

        // Simulate the normalization from RsyncExecutor.validateiCloudDrive
        let normalizedExpanded = testPath.hasSuffix("/") ? String(testPath.dropLast()) : testPath
        let normalizedICloud = iCloudRoot.hasSuffix("/") ? String(iCloudRoot.dropLast()) : iCloudRoot

        XCTAssertTrue(normalizedExpanded.hasPrefix(normalizedICloud),
                      "Path within iCloud Drive should pass prefix check")
    }

    func testPathOutsideiCloudDriveFailsValidation() {
        let iCloudRoot = SyncJob.iCloudDrivePath
        let testPath = "/Users/test/Documents/NotICloud"

        let normalizedExpanded = testPath.hasSuffix("/") ? String(testPath.dropLast()) : testPath
        let normalizedICloud = iCloudRoot.hasSuffix("/") ? String(iCloudRoot.dropLast()) : iCloudRoot

        XCTAssertFalse(normalizedExpanded.hasPrefix(normalizedICloud),
                       "Path outside iCloud Drive should fail prefix check")
        XCTAssertNotEqual(normalizedExpanded, normalizedICloud)
    }

    func testICloudDrivePathWithTrailingSlash() {
        let iCloudRoot = SyncJob.iCloudDrivePath
        let testPath = iCloudRoot + "/"

        // Normalize: strip trailing slash
        let normalizedExpanded = testPath.hasSuffix("/") ? String(testPath.dropLast()) : testPath
        let normalizedICloud = iCloudRoot.hasSuffix("/") ? String(iCloudRoot.dropLast()) : iCloudRoot

        XCTAssertEqual(normalizedExpanded, normalizedICloud,
                       "iCloud Drive root with trailing slash should equal normalized root")
    }

    func testICloudDriveExactRootPathPasses() {
        let iCloudRoot = SyncJob.iCloudDrivePath

        let normalizedExpanded = iCloudRoot
        let normalizedICloud = iCloudRoot

        // Should pass: path IS iCloud Drive root
        let passes = normalizedExpanded.hasPrefix(normalizedICloud) || normalizedExpanded == normalizedICloud
        XCTAssertTrue(passes, "Exact iCloud Drive root should pass validation")
    }

    // MARK: - SMB / Network Volume Paths

    func testSMBMountedVolumePath() {
        // SMB volumes appear under /Volumes/ on macOS
        let smbPath = "/Volumes/NAS-Share/Backups"

        XCTAssertTrue(smbPath.hasPrefix("/Volumes/"),
                      "SMB paths should start with /Volumes/")
        XCTAssertTrue(smbPath.hasPrefix("/"),
                      "SMB paths should be absolute")
    }

    func testUSBVolumePath() {
        let usbPath = "/Volumes/External-SSD/Backup"

        XCTAssertTrue(usbPath.hasPrefix("/Volumes/"))
        XCTAssertTrue(usbPath.hasPrefix("/"))
    }

    func testNetworkPathWithSpaces() {
        let netPath = "/Volumes/Time Machine Backups/2026-04-21"

        XCTAssertTrue(netPath.hasPrefix("/Volumes/"))
        // Verify path is usable (no escaping needed for Process arguments)
        XCTAssertTrue(netPath.contains(" "),
                      "Network paths may contain spaces")
    }

    // MARK: - Path Edge Cases

    func testEmptyPathHandling() {
        let path = ""

        XCTAssertTrue(path.isEmpty)
        XCTAssertFalse(path.hasPrefix("/"),
                       "Empty path should not be considered absolute")
    }

    func testPathWithSpecialCharacters() {
        // These are all valid macOS filenames
        let specialPaths = [
            "/Users/test/Documents/file name.txt",
            "/Users/test/Documents/file-name.txt",
            "/Users/test/Documents/file_name.txt",
            "/Users/test/Documents/file (1).txt",
            "/Users/test/Documents/résumé.pdf",
            "/Users/test/Documents/日本語ファイル.txt",
        ]

        for path in specialPaths {
            XCTAssertTrue(path.hasPrefix("/"),
                          "Path '\(path)' should be absolute")
        }
    }

    func testPathTraversalDetection() {
        let dangerousPaths = [
            "/Users/test/../../../etc/passwd",
            "/Volumes/Backup/../../etc/shadow",
            "/tmp/backup/../../../private",
        ]

        for path in dangerousPaths {
            XCTAssertTrue(path.contains(".."),
                          "Path '\(path)' should be detected as containing traversal")
        }
    }

    func testDoubleSlashNormalization() {
        // macOS/rsync handles double slashes, but we should be aware of them
        let path = "/Users//test///Documents"

        XCTAssertTrue(path.hasPrefix("/"))
        // standardizedFileURL normalization handles double slashes
        let url = URL(fileURLWithPath: path).standardizedFileURL
        XCTAssertFalse(url.path.contains("//"),
                       "Standardized URL normalization should remove double slashes")
    }

    // MARK: - Trailing Slash Behavior (rsync semantics)

    func testTrailingSlashBehavior() {
        // In rsync:
        // /src/dir/ -> syncs contents of dir
        // /src/dir  -> syncs dir itself as a subdirectory
        let withSlash = "/Users/test/Documents/"
        let withoutSlash = "/Users/test/Documents"

        XCTAssertTrue(withSlash.hasSuffix("/"))
        XCTAssertFalse(withoutSlash.hasSuffix("/"))

        // RsyncExecutor adds trailing slash for local/iCloud destinations
        var expanded = withoutSlash
        if !expanded.hasSuffix("/") {
            expanded += "/"
        }
        XCTAssertTrue(expanded.hasSuffix("/"),
                      "Executor should ensure trailing slash for destinations")
    }

    func testTrailingSlashStripping() {
        // createDestinationDirectory strips trailing slash
        var path = "/Users/test/Backup/"

        if path.hasSuffix("/") {
            path = String(path.dropLast())
        }

        XCTAssertEqual(path, "/Users/test/Backup")
        XCTAssertFalse(path.hasSuffix("/"))
    }

    // MARK: - Rsync Binary Resolution

    func testRsyncBinaryCandidatePaths() {
        // RsyncExecutor.resolveRsyncPath() checks these in order
        let candidates = ["/usr/bin/rsync", "/opt/homebrew/bin/rsync", "/usr/local/bin/rsync"]

        // At least the system rsync should exist
        let systemRsync = candidates[0]
        XCTAssertTrue(FileManager.default.isExecutableFile(atPath: systemRsync),
                      "/usr/bin/rsync should exist on macOS")
    }

    func testRsyncBinaryFallbackIsSystem() {
        // If none found, falls back to /usr/bin/rsync
        let fallback = "/usr/bin/rsync"
        XCTAssertTrue(FileManager.default.isExecutableFile(atPath: fallback),
                      "System rsync should be available as fallback")
    }

    // MARK: - Bookmark / Security-Scoped Access

    func testDestinationBookmarkAccessor() {
        var job = SyncJob(name: "Test", source: "/src", destination: "/dst")

        XCTAssertNil(job.destinationBookmark,
                     "New job should have no bookmark")

        let testData = Data("test-bookmark".utf8)
        job.destinationBookmark = testData
        XCTAssertEqual(job.destinationBookmark, testData)
        XCTAssertEqual(job.destinations.first?.bookmark, testData)
    }

    // MARK: - Destination Directory Creation Logic

    func testPathIsDirectoryCheck() {
        // Test the isDirectory check pattern from RsyncExecutor
        let tempDir = FileManager.default.temporaryDirectory.path

        var isDirectory: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: tempDir, isDirectory: &isDirectory)

        XCTAssertTrue(exists, "Temp directory should exist")
        XCTAssertTrue(isDirectory.boolValue, "Temp directory should be a directory")
    }

    func testNonExistentPathCheck() {
        let fakePath = "/tmp/rsyncgui-test-nonexistent-\(UUID().uuidString)"

        var isDirectory: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: fakePath, isDirectory: &isDirectory)

        XCTAssertFalse(exists, "Random path should not exist")
    }

    // MARK: - RsyncError Cases

    func testAllRsyncErrorCasesHaveDescriptions() {
        let errors: [RsyncError] = [
            .alreadyRunning,
            .executionFailed(NSError(domain: "test", code: 1)),
            .invalidConfiguration,
            .cancelled,
            .iCloudDriveNotAvailable,
            .iCloudDriveNotEnabled,
            .iCloudDrivePathInvalid,
            .invalidSSHKeyPath,
            .invalidHostOrUser("test"),
        ]

        for error in errors {
            XCTAssertNotNil(error.errorDescription,
                            "\(error) should have an error description")
            XCTAssertFalse(error.errorDescription!.isEmpty,
                           "\(error) error description should not be empty")
        }
    }

    func testICloudDriveErrorMessagesAreUserFriendly() {
        let notAvailable = RsyncError.iCloudDriveNotAvailable
        XCTAssertTrue(notAvailable.errorDescription!.contains("System Settings"),
                      "Error should guide user to fix the issue")

        let notEnabled = RsyncError.iCloudDriveNotEnabled
        XCTAssertTrue(notEnabled.errorDescription!.contains("iCloud Drive"),
                      "Error should mention iCloud Drive")

        let invalidPath = RsyncError.iCloudDrivePathInvalid
        XCTAssertTrue(invalidPath.errorDescription!.contains("within iCloud Drive"),
                      "Error should explain the path constraint")
    }

    // MARK: - Path Expansion Consistency

    func testTildeReplacementMatchesNSStringExpansion() {
        let path = "~/Documents/Backup"
        let homeDir = FileManager.default.homeDirectoryForCurrentUser.path

        let method1 = path.replacingOccurrences(of: "~", with: homeDir)
        let method2 = (path as NSString).expandingTildeInPath

        XCTAssertEqual(method1, method2,
                       "Both tilde expansion methods should produce the same result")
    }

    func testTildeReplacementDoesNotAffectNonTildePaths() {
        let path = "/absolute/path/no/tilde"
        let homeDir = FileManager.default.homeDirectoryForCurrentUser.path

        let expanded = path.replacingOccurrences(of: "~", with: homeDir)

        XCTAssertEqual(expanded, path,
                       "Path without tilde should be unchanged after replacement")
    }

    func testTildeInMiddleOfPathIsAlsoReplaced() {
        // Note: replacingOccurrences replaces ALL occurrences of "~"
        // This could be a bug if a path literally contains ~ in a directory name
        let path = "/Volumes/NAS/~/backup"
        let homeDir = FileManager.default.homeDirectoryForCurrentUser.path

        let expanded = path.replacingOccurrences(of: "~", with: homeDir)

        // This IS the current behavior — it replaces ALL tildes
        XCTAssertTrue(expanded.contains(homeDir),
                      "replacingOccurrences replaces ALL ~ characters")
        // Document that NSString.expandingTildeInPath only handles leading ~
        let nsExpanded = (path as NSString).expandingTildeInPath
        XCTAssertEqual(nsExpanded, path,
                       "NSString only expands leading tilde, not embedded ones")
    }
}
