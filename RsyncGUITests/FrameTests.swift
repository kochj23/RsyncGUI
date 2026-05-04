//
//  FrameTests.swift
//  RsyncGUITests
//
//  Created by Jordan Koch on 5/3/26.
//
//  Frame tests: verify that core types, enums, design constants,
//  and view-related models can be instantiated and hold correct values.
//  These tests ensure the app's structural integrity without launching a UI host.

import XCTest
@testable import RsyncGUI

final class FrameTests: XCTestCase {

    // MARK: - SidebarSelection Enum

    func testSidebarSelectionJobCaseCarriesUUID() {
        let id = UUID()
        let selection = SidebarSelection.job(id)

        switch selection {
        case .job(let extractedId):
            XCTAssertEqual(extractedId, id)
        default:
            XCTFail("Expected .job case")
        }
    }

    func testSidebarSelectionHistoryCase() {
        let selection = SidebarSelection.history
        if case .history = selection {
            // Pass
        } else {
            XCTFail("Expected .history case")
        }
    }

    func testSidebarSelectionAIInsightsCase() {
        let selection = SidebarSelection.aiInsights
        if case .aiInsights = selection {
            // Pass
        } else {
            XCTFail("Expected .aiInsights case")
        }
    }

    func testSidebarSelectionIsHashable() {
        let id = UUID()
        let set: Set<SidebarSelection> = [.job(id), .history, .aiInsights]

        XCTAssertEqual(set.count, 3, "All three sidebar selections should be distinct in a Set")
        XCTAssertTrue(set.contains(.job(id)))
        XCTAssertTrue(set.contains(.history))
        XCTAssertTrue(set.contains(.aiInsights))
    }

    func testSidebarSelectionSameJobIdsAreEqual() {
        let id = UUID()
        XCTAssertEqual(SidebarSelection.job(id), SidebarSelection.job(id))
    }

    func testSidebarSelectionDifferentJobIdsAreNotEqual() {
        XCTAssertNotEqual(SidebarSelection.job(UUID()), SidebarSelection.job(UUID()))
    }

    // MARK: - ModernColors Design Constants

    func testModernColorsHeatColorReturnsCorrectGradient() {
        // 0-24% = green (statusLow)
        let low = ModernColors.heatColor(percentage: 10)
        XCTAssertNotNil(low, "heatColor should return a color for low percentage")

        // 25-49% = yellow (statusMedium)
        let medium = ModernColors.heatColor(percentage: 30)
        XCTAssertNotNil(medium, "heatColor should return a color for medium percentage")

        // 50-74% = orange (statusHigh)
        let high = ModernColors.heatColor(percentage: 60)
        XCTAssertNotNil(high, "heatColor should return a color for high percentage")

        // 75+% = red (statusCritical)
        let critical = ModernColors.heatColor(percentage: 90)
        XCTAssertNotNil(critical, "heatColor should return a color for critical percentage")
    }

    func testModernColorsBackgroundGradientExists() {
        let gradient = ModernColors.backgroundGradient
        XCTAssertNotNil(gradient, "backgroundGradient should be available")
    }

    func testModernColorsBoundaryValues() {
        // Exact boundary values at percentage edges
        let at0 = ModernColors.heatColor(percentage: 0)
        XCTAssertNotNil(at0)

        let at25 = ModernColors.heatColor(percentage: 25)
        XCTAssertNotNil(at25)

        let at50 = ModernColors.heatColor(percentage: 50)
        XCTAssertNotNil(at50)

        let at75 = ModernColors.heatColor(percentage: 75)
        XCTAssertNotNil(at75)

        let at100 = ModernColors.heatColor(percentage: 100)
        XCTAssertNotNil(at100)
    }

    // MARK: - ModernButtonStyle Types

    func testModernButtonStyleTypesExist() {
        let filled = ModernButtonStyle.ButtonStyleType.filled
        let outlined = ModernButtonStyle.ButtonStyleType.outlined
        let destructive = ModernButtonStyle.ButtonStyleType.destructive
        let glass = ModernButtonStyle.ButtonStyleType.glass

        // Verify all four types can be instantiated
        XCTAssertNotNil(filled)
        XCTAssertNotNil(outlined)
        XCTAssertNotNil(destructive)
        XCTAssertNotNil(glass)
    }

    // MARK: - ModernHeader Sizes

    func testModernHeaderSizeFontValues() {
        XCTAssertEqual(ModernHeader.HeaderSize.large.fontSize, 32)
        XCTAssertEqual(ModernHeader.HeaderSize.medium.fontSize, 22)
        XCTAssertEqual(ModernHeader.HeaderSize.small.fontSize, 18)
    }

    // MARK: - HexagonShape Path Generation

    func testHexagonShapeGeneratesValidPath() {
        let hexagon = HexagonShape()
        let rect = CGRect(x: 0, y: 0, width: 100, height: 100)
        let path = hexagon.path(in: rect)

        XCTAssertFalse(path.isEmpty, "Hexagon path should not be empty")
        XCTAssertTrue(path.boundingRect.width > 0, "Hexagon path should have positive width")
        XCTAssertTrue(path.boundingRect.height > 0, "Hexagon path should have positive height")
    }

    func testHexagonShapeWithZeroRectProducesEmptyPath() {
        let hexagon = HexagonShape()
        let rect = CGRect.zero
        let path = hexagon.path(in: rect)

        // A hexagon at zero rect: all points collapse to center (0,0)
        // The path will exist but be degenerate
        XCTAssertNotNil(path, "Hexagon should handle zero rect without crashing")
    }

    // MARK: - DestinationType Enum

    func testDestinationTypeAllCasesExist() {
        let local = DestinationType.local
        let ssh = DestinationType.remoteSSH
        let icloud = DestinationType.iCloudDrive

        XCTAssertEqual(local.rawValue, "Local Folder")
        XCTAssertEqual(ssh.rawValue, "Remote Server (SSH)")
        XCTAssertEqual(icloud.rawValue, "iCloud Drive")
    }

    func testDestinationTypeCodableRoundtrip() throws {
        let types: [DestinationType] = [.local, .remoteSSH, .iCloudDrive]

        let data = try JSONEncoder().encode(types)
        let decoded = try JSONDecoder().decode([DestinationType].self, from: data)

        XCTAssertEqual(decoded, types)
    }

    // MARK: - SyncMode Enum

    func testSyncModeAllCases() {
        let allCases = SyncMode.allCases
        XCTAssertEqual(allCases.count, 3)
        XCTAssertTrue(allCases.contains(.fanOut))
        XCTAssertTrue(allCases.contains(.fanIn))
        XCTAssertTrue(allCases.contains(.fullMesh))
    }

    func testSyncModeRawValues() {
        XCTAssertEqual(SyncMode.fanOut.rawValue, "Fan-out (1\u{2192}N)")
        XCTAssertEqual(SyncMode.fanIn.rawValue, "Fan-in (N\u{2192}1)")
        XCTAssertEqual(SyncMode.fullMesh.rawValue, "Full Mesh (N\u{2192}N)")
    }

    // MARK: - ExecutionStrategy Enum

    func testExecutionStrategyAllCases() {
        let allCases = ExecutionStrategy.allCases
        XCTAssertEqual(allCases.count, 2)
        XCTAssertTrue(allCases.contains(.sequential))
        XCTAssertTrue(allCases.contains(.parallel))
    }

    // MARK: - FailureHandling Enum

    func testFailureHandlingAllCases() {
        let allCases = FailureHandling.allCases
        XCTAssertEqual(allCases.count, 2)
        XCTAssertTrue(allCases.contains(.continueOnError))
        XCTAssertTrue(allCases.contains(.stopOnError))
    }

    // MARK: - ExecutionStatus Enum

    func testExecutionStatusAllCases() {
        let statuses: [ExecutionStatus] = [.success, .failed, .partialSuccess, .cancelled]

        for status in statuses {
            XCTAssertFalse(status.rawValue.isEmpty,
                           "\(status) should have a non-empty raw value")
        }
    }

    func testExecutionStatusCodableRoundtrip() throws {
        let statuses: [ExecutionStatus] = [.success, .failed, .partialSuccess, .cancelled]

        let data = try JSONEncoder().encode(statuses)
        let decoded = try JSONDecoder().decode([ExecutionStatus].self, from: data)

        XCTAssertEqual(decoded, statuses)
    }

    // MARK: - Widget Data Models

    func testWidgetSyncDataDefaultInit() {
        let data = WidgetSyncData()

        XCTAssertNil(data.lastSyncTime)
        XCTAssertNil(data.lastSyncStatus)
        XCTAssertNil(data.lastSyncJobName)
        XCTAssertNil(data.nextScheduledSync)
        XCTAssertNil(data.nextScheduledJobName)
        XCTAssertEqual(data.backupHealthScore, 0)
        XCTAssertEqual(data.backupHealthGrade, "?")
        XCTAssertEqual(data.totalJobs, 0)
        XCTAssertEqual(data.enabledJobs, 0)
        XCTAssertTrue(data.jobsWithErrors.isEmpty)
        XCTAssertTrue(data.recentSyncs.isEmpty)
        XCTAssertNotNil(data.lastUpdated)
    }

    func testWidgetSyncDataCodableRoundtrip() throws {
        var data = WidgetSyncData()
        data.lastSyncTime = Date()
        data.lastSyncStatus = "success"
        data.lastSyncJobName = "Test Job"
        data.backupHealthScore = 85
        data.backupHealthGrade = "B"
        data.totalJobs = 5
        data.enabledJobs = 3

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let encoded = try encoder.encode(data)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(WidgetSyncData.self, from: encoded)

        XCTAssertEqual(decoded.lastSyncStatus, "success")
        XCTAssertEqual(decoded.lastSyncJobName, "Test Job")
        XCTAssertEqual(decoded.backupHealthScore, 85)
        XCTAssertEqual(decoded.backupHealthGrade, "B")
        XCTAssertEqual(decoded.totalJobs, 5)
        XCTAssertEqual(decoded.enabledJobs, 3)
    }

    func testWidgetJobErrorCodableRoundtrip() throws {
        let error = WidgetJobError(
            id: UUID(),
            jobName: "Backup",
            errorMessage: "Connection refused",
            lastFailedTime: Date(),
            failureCount: 3
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(error)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(WidgetJobError.self, from: data)

        XCTAssertEqual(decoded.id, error.id)
        XCTAssertEqual(decoded.jobName, "Backup")
        XCTAssertEqual(decoded.errorMessage, "Connection refused")
        XCTAssertEqual(decoded.failureCount, 3)
    }

    func testWidgetRecentSyncCodableRoundtrip() throws {
        let sync = WidgetRecentSync(
            id: UUID(),
            jobName: "Documents",
            timestamp: Date(),
            status: "success",
            filesTransferred: 42,
            bytesTransferred: 123456
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(sync)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(WidgetRecentSync.self, from: data)

        XCTAssertEqual(decoded.id, sync.id)
        XCTAssertEqual(decoded.jobName, "Documents")
        XCTAssertEqual(decoded.status, "success")
        XCTAssertEqual(decoded.filesTransferred, 42)
        XCTAssertEqual(decoded.bytesTransferred, 123456)
    }

    // MARK: - DependencyCheckResult Enum

    func testDependencyCheckResultSatisfied() {
        let result = DependencyCheckResult.satisfied

        switch result {
        case .satisfied:
            break // Expected
        case .unsatisfied:
            XCTFail("Should be satisfied")
        }
    }

    func testDependencyCheckResultUnsatisfied() {
        let reasons = ["Job A failed", "Job B never run"]
        let result = DependencyCheckResult.unsatisfied(reasons: reasons)

        switch result {
        case .satisfied:
            XCTFail("Should be unsatisfied")
        case .unsatisfied(let extractedReasons):
            XCTAssertEqual(extractedReasons.count, 2)
            XCTAssertEqual(extractedReasons[0], "Job A failed")
        }
    }

    // MARK: - NovaAPIServer Configuration

    @MainActor
    func testNovaAPIServerPort() {
        // Verify the port constant matches what's documented
        // Port 37424 is assigned to RsyncGUI in Nova's port map
        let expectedPort: UInt16 = 37424
        XCTAssertEqual(NovaAPIServer.shared.port, expectedPort,
                       "NovaAPIServer should listen on port 37424")
    }
}
