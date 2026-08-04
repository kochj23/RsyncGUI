//
//  DestinationEditingTests.swift
//  RsyncGUITests
//
//  Created by Jordan Koch on 7/29/26.
//
//  Regression coverage for issue #4: "Browsing to a destination and hitting
//  Select does not populate the Destination Path" / "Manually entering a
//  Destination Path is not saved."
//
//  Root cause: SyncDestination declared a custom `static func ==` that compared
//  ONLY `.id`. SwiftUI uses Equatable for change detection, so mutating `.path`
//  on an existing destination (same id) looked like "no change" and the view
//  never refreshed — edits appeared lost. The path-setting logic was also buried
//  in the view, so it was untestable and kept regressing across three prior fixes.
//
//  The fix: (1) let Swift synthesize member-wise Equatable so a path change is a
//  real change, and (2) extract a pure `SyncJob.setDestinationPath(id:path:)`
//  helper that the view calls, so the logic is exercised by the tests below.
//
//  All 7 required categories are covered: Unit, Integration, Functional,
//  Security, Performance, Retry, Frame. Test paths use placeholder locations
//  (e.g. "/Volumes/Backup/...", "/tmp/...") — never real home directories.
//
//  Retry note: destination-path editing performs NO network or external call,
//  so there is no genuine retry to exercise. Rather than fabricate one, the
//  "Retry" section asserts graceful handling of the browse-cancel path (the
//  helper is simply never invoked, so the job is unchanged) and that a
//  security-scoped bookmark failure cannot lose the path that was already set.

import XCTest
@testable import RsyncGUI

final class DestinationEditingTests: XCTestCase {

    // MARK: - Unit

    /// setDestinationPath sets the exact path on the matching id.
    func testSetDestinationPathSetsExactPathOnMatchingID() {
        var job = SyncJob(name: "Test", sources: ["/tmp/src"],
                          destinations: [SyncDestination(path: "", type: .local)])
        let id = job.destinations[0].id

        job.setDestinationPath(id: id, path: "/Volumes/Backup/photos")

        XCTAssertEqual(job.destinations[0].path, "/Volumes/Backup/photos",
                       "Path should be set exactly on the matching destination")
    }

    /// setDestinationPath targets only the matching id when multiple exist.
    func testSetDestinationPathTargetsCorrectDestination() {
        let d1 = SyncDestination(path: "/tmp/one", type: .local)
        let d2 = SyncDestination(path: "/tmp/two", type: .local)
        let d3 = SyncDestination(path: "/tmp/three", type: .local)
        var job = SyncJob(name: "Multi", sources: ["/tmp/src"], destinations: [d1, d2, d3])

        job.setDestinationPath(id: d2.id, path: "/Volumes/Backup/changed")

        XCTAssertEqual(job.destinations[0].path, "/tmp/one", "Unrelated destination unchanged")
        XCTAssertEqual(job.destinations[1].path, "/Volumes/Backup/changed", "Only matching id updated")
        XCTAssertEqual(job.destinations[2].path, "/tmp/three", "Unrelated destination unchanged")
    }

    /// Unknown id is a no-op — no crash, no mutation.
    func testSetDestinationPathWithUnknownIDIsNoOp() {
        let original = SyncDestination(path: "/tmp/original", type: .local)
        var job = SyncJob(name: "Test", sources: ["/tmp/src"], destinations: [original])

        job.setDestinationPath(id: UUID(), path: "/Volumes/Backup/should-not-apply")

        XCTAssertEqual(job.destinations.count, 1, "No destination should be added")
        XCTAssertEqual(job.destinations[0].path, "/tmp/original",
                       "Unknown id must not mutate any destination")
    }

    /// REGRESSION LOCK (issue #4): two SyncDestinations with the SAME id but
    /// DIFFERENT path must now be NON-equal. Against the old id-only `==` these
    /// compared equal, which is exactly why SwiftUI ignored path edits. This
    /// assertion MUST fail on the old code path.
    func testSameIDDifferentPathAreNotEqual() {
        let dest1 = SyncDestination(path: "/Volumes/Backup/a", type: .local)
        var dest2 = dest1                 // copy → identical id
        dest2.path = "/Volumes/Backup/b"  // change only the path

        XCTAssertNotEqual(dest1, dest2,
                          "A path change must register as a real change (member-wise Equatable). "
                          + "If this fails, the id-only == regression has returned and SwiftUI "
                          + "will silently drop destination edits.")
    }

    /// Fully identical destinations (same id and all fields) remain equal.
    func testIdenticalDestinationsAreEqual() {
        let dest1 = SyncDestination(path: "/Volumes/Backup/a", type: .local)
        let dest2 = dest1
        XCTAssertEqual(dest1, dest2, "A destination should equal an unmodified copy of itself")
    }

    /// A change to a non-path field is also a real change (member-wise Equatable).
    func testSameIDDifferentTypeAreNotEqual() {
        let dest1 = SyncDestination(path: "/Volumes/Backup/a", type: .local)
        var dest2 = dest1
        dest2.type = .iCloudDrive
        XCTAssertNotEqual(dest1, dest2, "A type change on the same id must register as a change")
    }

    /// Empty and whitespace paths are stored literally (no trimming/normalization
    /// happens in the model layer — that is the executor's job).
    func testEmptyAndWhitespacePathHandling() {
        var job = SyncJob(name: "Test", sources: ["/tmp/src"],
                          destinations: [SyncDestination(path: "/tmp/start", type: .local)])
        let id = job.destinations[0].id

        job.setDestinationPath(id: id, path: "")
        XCTAssertEqual(job.destinations[0].path, "", "Empty path should be stored as-is")

        job.setDestinationPath(id: id, path: "   ")
        XCTAssertEqual(job.destinations[0].path, "   ", "Whitespace path should be stored literally")

        job.setDestinationPath(id: id, path: "/Volumes/Backup/final")
        XCTAssertEqual(job.destinations[0].path, "/Volumes/Backup/final",
                       "A subsequent real path should overwrite cleanly")
    }

    // MARK: - Integration

    /// Round-trip a destination path + type through the exact serialization
    /// JobManager.saveJobs/loadJobs use (JSONEncoder → JSONDecoder), for every
    /// DestinationType case.
    func testDestinationPathAndTypeSurviveJSONRoundTripAllTypes() throws {
        let cases: [DestinationType] = [.local, .iCloudDrive, .remoteSSH]

        for type in cases {
            var job = SyncJob(name: "RoundTrip \(type.rawValue)", sources: ["/tmp/src"],
                              destinations: [SyncDestination(path: "", type: type)])
            let id = job.destinations[0].id
            let path = "/Volumes/Backup/\(type.rawValue.replacingOccurrences(of: " ", with: "_"))"
            job.setDestinationPath(id: id, path: path)

            let data = try JSONEncoder().encode([job])
            let decoded = try JSONDecoder().decode([SyncJob].self, from: data)

            XCTAssertEqual(decoded.count, 1)
            XCTAssertEqual(decoded[0].destinations.first?.path, path,
                           "Path should survive encode/decode for \(type.rawValue)")
            XCTAssertEqual(decoded[0].destinations.first?.type, type,
                           "Type should survive encode/decode for \(type.rawValue)")
        }
    }

    /// Multiple destinations with distinct paths all round-trip independently.
    func testMultipleDestinationPathsSurviveRoundTrip() throws {
        var job = SyncJob(name: "Multi", sources: ["/tmp/src"], destinations: [
            SyncDestination(path: "", type: .local),
            SyncDestination(path: "", type: .local),
            SyncDestination(path: "", type: .iCloudDrive)
        ])
        job.setDestinationPath(id: job.destinations[0].id, path: "/Volumes/Backup/one")
        job.setDestinationPath(id: job.destinations[1].id, path: "/Volumes/Backup/two")
        job.setDestinationPath(id: job.destinations[2].id, path: "/tmp/icloud/three")

        let data = try JSONEncoder().encode(job)
        let decoded = try JSONDecoder().decode(SyncJob.self, from: data)

        XCTAssertEqual(decoded.destinations.map { $0.path },
                       ["/Volumes/Backup/one", "/Volumes/Backup/two", "/tmp/icloud/three"])
    }

    /// End-to-end through JobManager's real add/update/save path. Snapshots and
    /// restores the shared manager's job list so the developer's real jobs.json
    /// is never left mutated.
    @MainActor
    func testJobManagerPersistsDestinationPathEndToEnd() throws {
        let manager = JobManager.shared
        let snapshot = manager.jobs
        defer {
            manager.jobs = snapshot
            manager.saveJobs()
        }

        var job = SyncJob(name: "DEST-EDIT-INTEGRATION-\(UUID().uuidString)",
                          sources: ["/tmp/src"],
                          destinations: [SyncDestination(path: "", type: .local)])
        let destID = job.destinations[0].id

        manager.addJob(job)   // persists via saveJobs()

        job.setDestinationPath(id: destID, path: "/Volumes/Backup/integration")
        manager.updateJob(job) // persists via saveJobs()

        // Re-decode the persisted representation (same serialization loadJobs uses).
        let data = try JSONEncoder().encode(manager.jobs)
        let reloaded = try JSONDecoder().decode([SyncJob].self, from: data)
        let found = reloaded.first { $0.id == job.id }

        XCTAssertNotNil(found, "Saved job should be present after add/update")
        XCTAssertEqual(found?.destinations.first?.path, "/Volumes/Backup/integration",
                       "Destination path must persist across the JobManager save path")
    }

    // MARK: - Functional

    /// Golden path from a caller's perspective: add a destination, set its path,
    /// persist, and verify the persisted job reflects the edit.
    func testFunctionalGoldenPathAddSetSavePersists() throws {
        var job = SyncJob(name: "Functional", source: "/tmp/src", destination: "")

        // Add a second destination the way the editor's "+" button does.
        var newDest = SyncDestination(path: "", type: .local)
        job.destinations.append(newDest)
        newDest = job.destinations[1] // capture the appended instance's id

        job.setDestinationPath(id: newDest.id, path: "/Volumes/Backup/added")

        // "Save" == serialize (JobManager.saveJobs) then reload (loadJobs).
        let data = try JSONEncoder().encode(job)
        let persisted = try JSONDecoder().decode(SyncJob.self, from: data)

        XCTAssertEqual(persisted.destinations.count, 2)
        XCTAssertEqual(persisted.destinations[1].path, "/Volumes/Backup/added",
                       "The added-and-edited destination should be persisted")
    }

    /// Cancel / no-op path: if the user cancels the panel, the helper is never
    /// invoked and the destination keeps whatever it had.
    func testFunctionalCancelLeavesDestinationUnchanged() throws {
        let job = SyncJob(name: "Functional", source: "/tmp/src", destination: "/Volumes/Backup/existing")
        let before = job.destinations[0].path

        // Simulate a cancelled NSOpenPanel: setDestinationPath is simply not called.
        // (Nothing happens here on purpose.)

        let data = try JSONEncoder().encode(job)
        let persisted = try JSONDecoder().decode(SyncJob.self, from: data)

        XCTAssertEqual(persisted.destinations[0].path, before,
                       "A cancelled browse must leave the existing path intact")
    }

    /// Manual text entry is modeled as a direct assignment into the binding, then
    /// a save — verify it persists (the second half of issue #4).
    func testFunctionalManualEntryPersists() throws {
        var job = SyncJob(name: "Functional", source: "/tmp/src", destination: "")

        // The TextField binds to destination.path — model that as a direct write.
        job.destinations[0].path = "/Volumes/Backup/typed-by-hand"

        let data = try JSONEncoder().encode(job)
        let persisted = try JSONDecoder().decode(SyncJob.self, from: data)

        XCTAssertEqual(persisted.destinations[0].path, "/Volumes/Backup/typed-by-hand",
                       "Manually entered destination path must be saved")
    }

    // MARK: - Security

    /// A destination path containing shell metacharacters is stored LITERALLY —
    /// byte-for-byte — and survives persistence unchanged. Nothing in the model
    /// layer evaluates it.
    func testShellMetacharacterPathStoredLiterally() throws {
        let malicious = "/Volumes/Backup/$(rm -rf ~); echo pwned && `id` | tee /tmp/x"
        var job = SyncJob(name: "Security", sources: ["/tmp/src"],
                          destinations: [SyncDestination(path: "", type: .local)])
        job.setDestinationPath(id: job.destinations[0].id, path: malicious)

        XCTAssertEqual(job.destinations[0].path, malicious, "Path must be stored verbatim")

        let data = try JSONEncoder().encode(job)
        let decoded = try JSONDecoder().decode(SyncJob.self, from: data)
        XCTAssertEqual(decoded.destinations[0].path, malicious,
                       "Metacharacter path must survive persistence byte-for-byte, never evaluated")
    }

    /// A newline in the path is preserved literally and does not split into a
    /// second logical value.
    func testNewlineInPathStoredLiterally() throws {
        let withNewline = "/Volumes/Backup/dir\n/etc/passwd"
        var job = SyncJob(name: "Security", sources: ["/tmp/src"],
                          destinations: [SyncDestination(path: "", type: .local)])
        job.setDestinationPath(id: job.destinations[0].id, path: withNewline)

        let data = try JSONEncoder().encode(job)
        let decoded = try JSONDecoder().decode(SyncJob.self, from: data)
        XCTAssertEqual(decoded.destinations[0].path, withNewline,
                       "Newlines must be preserved literally, not treated as a value separator")
    }

    /// End-to-end proof that a metacharacter destination is never shell-evaluated:
    /// run the REAL rsync binary (the same way RsyncExecutor does — via
    /// Process.arguments, no shell) into a directory whose name contains shell
    /// metacharacters, and confirm the data lands in that literal directory and
    /// the injected command did NOT execute.
    func testRsyncTreatsMetacharacterDestinationAsLiteralPath() throws {
        let fm = FileManager.default
        guard fm.isExecutableFile(atPath: "/usr/bin/rsync") else {
            throw XCTSkip("/usr/bin/rsync not available")
        }

        let base = fm.temporaryDirectory.appendingPathComponent("RsyncDestSec-\(UUID().uuidString)")
        let source = base.appendingPathComponent("source")
        // A directory literally named with shell metacharacters.
        let dest = base.appendingPathComponent("dest; touch INJECTED && echo x")
        try fm.createDirectory(at: source, withIntermediateDirectories: true)
        try fm.createDirectory(at: dest, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: base) }

        try "payload".write(to: source.appendingPathComponent("file.txt"),
                            atomically: true, encoding: .utf8)

        // Mirror RsyncExecutor: arguments as an array, no shell interpretation.
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/rsync")
        process.arguments = ["-a", source.path + "/", dest.path + "/"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        process.waitUntilExit()

        XCTAssertEqual(process.terminationStatus, 0, "rsync should succeed with a literal metachar path")
        XCTAssertTrue(fm.fileExists(atPath: dest.appendingPathComponent("file.txt").path),
                      "Data must land inside the literally-named destination directory")
        // The injected `touch INJECTED` must NOT have run in the working directory.
        XCTAssertFalse(fm.fileExists(atPath: base.appendingPathComponent("INJECTED").path),
                       "Injected command must never execute — path is a literal argument")
        XCTAssertFalse(fm.fileExists(atPath: fm.currentDirectoryPath + "/INJECTED"),
                       "Injected command must never execute in the current directory")
    }

    /// A metacharacter path routed through the scheduler's shell-escape (the one
    /// place a path reaches a shell, inside a launchd plist) is single-quoted so
    /// the metacharacters are inert. Mirrors ScheduleManager.shellEscape.
    func testScheduledCommandShellEscapeNeutralizesMetacharacters() {
        let path = "/Volumes/Backup/x; rm -rf ~ && echo pwned"
        let escaped = shellEscapeForTest(path)

        XCTAssertTrue(escaped.hasPrefix("'") && escaped.hasSuffix("'"),
                      "Escaped path must be fully single-quoted")
        XCTAssertFalse(escaped.contains("'; rm"),
                       "Single-quoting must prevent the semicolon from ending the argument")
    }

    /// Path traversal via ".." is stored verbatim (the model does not silently
    /// rewrite it); traversal enforcement lives in the executor/validation layer,
    /// consistent with existing PathValidation/CommandInjection tests.
    func testParentTraversalPathStoredVerbatim() {
        let traversal = "/Volumes/Backup/../../etc"
        var job = SyncJob(name: "Security", sources: ["/tmp/src"],
                          destinations: [SyncDestination(path: "", type: .local)])
        job.setDestinationPath(id: job.destinations[0].id, path: traversal)

        XCTAssertEqual(job.destinations[0].path, traversal,
                       "Model stores the path verbatim; traversal is enforced downstream")
        XCTAssertTrue(job.destinations[0].path.contains(".."),
                      "The '..' remains detectable by downstream validation")
    }

    // MARK: - Performance

    /// setDestinationPath on a job with a large number of destinations must be
    /// cheap (single O(n) firstIndex lookup — no accidental O(n²)).
    func testSetDestinationPathPerformanceLargeJob() {
        let count = 1_000
        var destinations: [SyncDestination] = []
        destinations.reserveCapacity(count)
        for i in 0..<count {
            destinations.append(SyncDestination(path: "/tmp/dest\(i)", type: .local))
        }
        var job = SyncJob(name: "Large", sources: ["/tmp/src"], destinations: destinations)
        let lastID = job.destinations[count - 1].id

        measure {
            for _ in 0..<1_000 {
                job.setDestinationPath(id: lastID, path: "/Volumes/Backup/updated")
            }
        }

        XCTAssertEqual(job.destinations[count - 1].path, "/Volumes/Backup/updated")
    }

    /// Setting a distinct path on every one of 1,000 destinations completes well
    /// under a modest wall-clock bound.
    func testSetPathAcrossAllDestinationsIsLinearEnough() {
        let count = 1_000
        var destinations: [SyncDestination] = []
        destinations.reserveCapacity(count)
        for i in 0..<count {
            destinations.append(SyncDestination(path: "/tmp/dest\(i)", type: .local))
        }
        var job = SyncJob(name: "Large", sources: ["/tmp/src"], destinations: destinations)
        let ids = job.destinations.map { $0.id }

        let start = Date()
        for (i, id) in ids.enumerated() {
            job.setDestinationPath(id: id, path: "/Volumes/Backup/d\(i)")
        }
        let elapsed = Date().timeIntervalSince(start)

        XCTAssertLessThan(elapsed, 1.0,
                          "Editing 1,000 destinations by id should finish in well under a second")
        XCTAssertEqual(job.destinations[500].path, "/Volumes/Backup/d500")
    }

    // MARK: - Retry
    //
    // Destination-path editing makes NO network or external call, so there is no
    // genuine retry to test. Instead we assert graceful handling of the two
    // real failure modes in this flow: (1) a cancelled browse panel, and (2) a
    // security-scoped bookmark creation failure.

    /// Browse-cancel: the helper is never called, so the job is unchanged and
    /// nothing crashes. (Also verifies an unknown-id call — e.g. the destination
    /// was removed while the panel was open — is a safe no-op.)
    func testRetryBrowseCancelIsGraceful() {
        var job = SyncJob(name: "Retry", source: "/tmp/src", destination: "/Volumes/Backup/keep")
        let goneID = UUID() // an id no longer present (destination removed mid-panel)

        // Cancel path: helper not invoked. Stale-id path: invoked but no-op.
        job.setDestinationPath(id: goneID, path: "/Volumes/Backup/should-not-apply")

        XCTAssertEqual(job.destinations[0].path, "/Volumes/Backup/keep",
                       "Neither a cancel nor a stale-id edit may alter the job")
    }

    /// Bookmark-failure resilience: the editor sets the path FIRST and creates the
    /// security-scoped bookmark SECOND, so a bookmark failure cannot lose the path.
    /// Here we drive a bookmark creation that fails (non-existent URL) and confirm
    /// the path set beforehand is retained.
    func testRetryBookmarkFailureDoesNotLosePath() {
        var job = SyncJob(name: "Retry", sources: ["/tmp/src"],
                          destinations: [SyncDestination(path: "", type: .iCloudDrive)])
        let id = job.destinations[0].id

        // Step 1 (as JobEditorView does): set the path.
        job.setDestinationPath(id: id, path: "/Volumes/Backup/icloud-dest")

        // Step 2: attempt a security-scoped bookmark that will fail.
        let bogus = URL(fileURLWithPath: "/nonexistent-\(UUID().uuidString)/dir")
        var bookmarkFailed = false
        do {
            let data = try bogus.bookmarkData(options: [.withSecurityScope],
                                              includingResourceValuesForKeys: nil, relativeTo: nil)
            if let index = job.destinations.firstIndex(where: { $0.id == id }) {
                job.destinations[index].bookmark = data
            }
        } catch {
            bookmarkFailed = true // swallowed, exactly like the editor does
        }

        XCTAssertTrue(bookmarkFailed, "Bookmark creation on a bogus URL should fail")
        XCTAssertEqual(job.destinations[0].path, "/Volumes/Backup/icloud-dest",
                       "A failed bookmark must not clear the path already set")
        XCTAssertNil(job.destinations[0].bookmark, "No bookmark should be stored on failure")
    }

    // MARK: - Frame

    /// Core models construct without crashing.
    func testFrameModelsConstruct() {
        let dest = SyncDestination(path: "/tmp/dest", type: .local)
        XCTAssertEqual(dest.path, "/tmp/dest")

        let job = SyncJob(name: "Frame", source: "/tmp/src", destination: "/tmp/dest")
        XCTAssertEqual(job.destinations.count, 1)
        XCTAssertNotNil(job.id)
    }

    /// A destination edit through the helper works on a freshly constructed job —
    /// the JobEditorView-adjacent model path instantiates and mutates cleanly.
    func testFrameDestinationEditPathInstantiates() {
        var job = SyncJob(name: "Frame", sources: ["/tmp/src"],
                          destinations: [SyncDestination(path: "", type: .local)])
        job.setDestinationPath(id: job.destinations[0].id, path: "/Volumes/Backup/frame")
        XCTAssertEqual(job.destinations[0].path, "/Volumes/Backup/frame")
    }

    /// JobManager (the persistence coordinator behind the editor's Save) is
    /// reachable and holds a jobs array — the test bundle launches with it wired up.
    @MainActor
    func testFrameJobManagerReachable() {
        let manager = JobManager.shared
        XCTAssertNotNil(manager)
        XCTAssertNotNil(manager.jobs)
    }

    // MARK: - Helper

    /// Replicates ScheduleManager's private shellEscape method for testing,
    /// matching the pattern used in CommandInjectionTests.
    private func shellEscapeForTest(_ arg: String) -> String {
        "'" + arg.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
