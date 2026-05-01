//
//  ProgressParsingTests.swift
//  RsyncGUITests
//
//  Created by Jordan Koch on 5/1/26.
//
//  Tests for rsync output parsing: speed, time, bytes, and progress line extraction.
//  RsyncExecutor has private parsing methods, so we test via the public RsyncProgress model
//  and by replicating the parsing logic to verify correctness.

import XCTest
@testable import RsyncGUI

final class ProgressParsingTests: XCTestCase {

    // MARK: - Speed Parsing

    /// Replicates RsyncExecutor.parseSpeed() for unit testing
    private func parseSpeed(_ speedString: String) -> Double {
        let cleaned = speedString.replacingOccurrences(of: "/s", with: "")

        if cleaned.hasSuffix("GB") || cleaned.hasSuffix("G") {
            let stripped = cleaned.hasSuffix("GB") ? String(cleaned.dropLast(2)) : String(cleaned.dropLast())
            return Double(stripped).map { $0 * 1_073_741_824 } ?? 0
        } else if cleaned.hasSuffix("MB") || cleaned.hasSuffix("M") {
            let stripped = cleaned.hasSuffix("MB") ? String(cleaned.dropLast(2)) : String(cleaned.dropLast())
            return Double(stripped).map { $0 * 1_048_576 } ?? 0
        } else if cleaned.hasSuffix("KB") || cleaned.hasSuffix("K") {
            let stripped = cleaned.hasSuffix("KB") ? String(cleaned.dropLast(2)) : String(cleaned.dropLast())
            return Double(stripped).map { $0 * 1024 } ?? 0
        } else if cleaned.hasSuffix("B") {
            return Double(String(cleaned.dropLast())) ?? 0
        }

        return 0
    }

    func testParseSpeedMBPerSecond() {
        let speed = parseSpeed("123.45MB/s")
        XCTAssertEqual(speed, 123.45 * 1_048_576, accuracy: 1)
    }

    func testParseSpeedMBPerSecondShortForm() {
        // rsync -h can output "M/s" without the trailing B
        let speed = parseSpeed("50.5M/s")
        XCTAssertEqual(speed, 50.5 * 1_048_576, accuracy: 1)
    }

    func testParseSpeedGBPerSecond() {
        let speed = parseSpeed("1.5GB/s")
        XCTAssertEqual(speed, 1.5 * 1_073_741_824, accuracy: 1)
    }

    func testParseSpeedGBPerSecondShortForm() {
        let speed = parseSpeed("2.0G/s")
        XCTAssertEqual(speed, 2.0 * 1_073_741_824, accuracy: 1)
    }

    func testParseSpeedKBPerSecond() {
        let speed = parseSpeed("512KB/s")
        XCTAssertEqual(speed, 512 * 1024, accuracy: 1)
    }

    func testParseSpeedKBPerSecondShortForm() {
        let speed = parseSpeed("256K/s")
        XCTAssertEqual(speed, 256 * 1024, accuracy: 1)
    }

    func testParseSpeedBytesPerSecond() {
        let speed = parseSpeed("1024B/s")
        XCTAssertEqual(speed, 1024, accuracy: 0.001)
    }

    func testParseSpeedZero() {
        let speed = parseSpeed("0B/s")
        XCTAssertEqual(speed, 0)
    }

    func testParseSpeedInvalidReturnsZero() {
        let speed = parseSpeed("not-a-speed")
        XCTAssertEqual(speed, 0)
    }

    func testParseSpeedEmptyReturnsZero() {
        let speed = parseSpeed("")
        XCTAssertEqual(speed, 0)
    }

    // MARK: - Time Parsing

    /// Replicates RsyncExecutor.parseTime() for unit testing
    private func parseTime(_ timeString: String) -> TimeInterval {
        let components = timeString.components(separatedBy: ":")
        guard components.count >= 2 else { return 0 }

        let hours = Double(components[0]) ?? 0
        let minutes = Double(components[1]) ?? 0
        let seconds = components.count >= 3 ? (Double(components[2]) ?? 0) : 0

        return hours * 3600 + minutes * 60 + seconds
    }

    func testParseTimeHoursMinutesSeconds() {
        let time = parseTime("1:23:45")
        XCTAssertEqual(time, 1 * 3600 + 23 * 60 + 45, accuracy: 0.001)
    }

    func testParseTimeMinutesSeconds() {
        let time = parseTime("5:30")
        XCTAssertEqual(time, 5 * 3600 + 30 * 60, accuracy: 0.001)
        // Note: parseTime treats first component as hours when only 2 components
        // "5:30" = 5 hours + 30 minutes = 19800 seconds
    }

    func testParseTimeZero() {
        let time = parseTime("0:00:00")
        XCTAssertEqual(time, 0)
    }

    func testParseTimeLargeValues() {
        let time = parseTime("99:59:59")
        XCTAssertEqual(time, 99 * 3600 + 59 * 60 + 59, accuracy: 0.001)
    }

    func testParseTimeInvalidReturnsZero() {
        let time = parseTime("invalid")
        XCTAssertEqual(time, 0)
    }

    func testParseTimeEmptyReturnsZero() {
        let time = parseTime("")
        XCTAssertEqual(time, 0)
    }

    // MARK: - Bytes Parsing

    /// Replicates RsyncExecutor.parseBytes() for unit testing
    private func parseBytes(_ bytesString: String) -> Int64 {
        let cleaned = bytesString.trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: ",", with: "")

        if cleaned.contains("bytes") {
            let numberString = cleaned.components(separatedBy: .whitespaces).first ?? "0"
            return Int64(numberString) ?? 0
        }

        if cleaned.hasSuffix("GB") || cleaned.hasSuffix("G") {
            let stripped = cleaned.hasSuffix("GB") ? String(cleaned.dropLast(2)) : String(cleaned.dropLast())
            if let value = Double(stripped) { return Int64(value * 1_073_741_824) }
        } else if cleaned.hasSuffix("MB") || cleaned.hasSuffix("M") {
            let stripped = cleaned.hasSuffix("MB") ? String(cleaned.dropLast(2)) : String(cleaned.dropLast())
            if let value = Double(stripped) { return Int64(value * 1_048_576) }
        } else if cleaned.hasSuffix("KB") || cleaned.hasSuffix("K") {
            let stripped = cleaned.hasSuffix("KB") ? String(cleaned.dropLast(2)) : String(cleaned.dropLast())
            if let value = Double(stripped) { return Int64(value * 1024) }
        }

        return Int64(cleaned) ?? 0
    }

    func testParseBytesRawFormat() {
        let bytes = parseBytes("1,234,567 bytes")
        XCTAssertEqual(bytes, 1234567)
    }

    func testParseBytesNoCommas() {
        let bytes = parseBytes("12345 bytes")
        XCTAssertEqual(bytes, 12345)
    }

    func testParseBytesMBFormat() {
        let bytes = parseBytes("1.18MB")
        XCTAssertEqual(bytes, Int64(1.18 * 1_048_576))
    }

    func testParseBytesMBShortFormat() {
        let bytes = parseBytes("2.5M")
        XCTAssertEqual(bytes, Int64(2.5 * 1_048_576))
    }

    func testParseBytesGBFormat() {
        let bytes = parseBytes("1.5GB")
        XCTAssertEqual(bytes, Int64(1.5 * 1_073_741_824))
    }

    func testParseBytesGBShortFormat() {
        let bytes = parseBytes("3G")
        XCTAssertEqual(bytes, Int64(3.0 * 1_073_741_824))
    }

    func testParseBytesKBFormat() {
        let bytes = parseBytes("512KB")
        XCTAssertEqual(bytes, Int64(512 * 1024))
    }

    func testParseBytesKBShortFormat() {
        let bytes = parseBytes("100K")
        XCTAssertEqual(bytes, Int64(100 * 1024))
    }

    func testParseBytesPlainNumber() {
        let bytes = parseBytes("999")
        XCTAssertEqual(bytes, 999)
    }

    func testParseBytesWithLeadingWhitespace() {
        let bytes = parseBytes("  1,024 bytes  ")
        XCTAssertEqual(bytes, 1024)
    }

    func testParseBytesZero() {
        let bytes = parseBytes("0 bytes")
        XCTAssertEqual(bytes, 0)
    }

    func testParseBytesInvalidReturnsZero() {
        let bytes = parseBytes("not-a-number")
        XCTAssertEqual(bytes, 0)
    }

    // MARK: - Final Stats Parsing

    /// Replicates RsyncExecutor.parseFinalStats() for unit testing
    private func parseFinalStats(from output: String) -> (filesTransferred: Int, bytesTransferred: Int64) {
        var filesTransferred = 0
        var bytesTransferred: Int64 = 0

        let lines = output.components(separatedBy: .newlines)

        for line in lines {
            if line.contains("Number of files transferred:") {
                let components = line.components(separatedBy: ":")
                if components.count >= 2 {
                    let valueString = components[1].trimmingCharacters(in: .whitespaces)
                    let numberPart = valueString.components(separatedBy: .whitespaces).first ?? "0"
                    filesTransferred = Int(numberPart) ?? 0
                }
            }

            if line.contains("Total transferred file size:") {
                let components = line.components(separatedBy: ":")
                if components.count >= 2 {
                    let sizeString = components[1].trimmingCharacters(in: .whitespaces)
                    bytesTransferred = parseBytes(sizeString)
                }
            }
        }

        return (filesTransferred, bytesTransferred)
    }

    func testParseFinalStatsTypicalOutput() {
        let output = """
        Number of files: 1,234
        Number of files transferred: 42
        Total file size: 5,678,901 bytes
        Total transferred file size: 1,234,567 bytes
        Literal data: 1,234,567 bytes
        Matched data: 0 bytes
        File list size: 1,234
        File list generation time: 0.001 seconds
        File list transfer time: 0.000 seconds
        Total bytes sent: 1,234,890
        Total bytes received: 456
        """

        let stats = parseFinalStats(from: output)

        XCTAssertEqual(stats.filesTransferred, 42)
        XCTAssertEqual(stats.bytesTransferred, 1234567)
    }

    func testParseFinalStatsHumanReadableOutput() {
        let output = """
        Number of files: 1.23K
        Number of files transferred: 100
        Total file size: 5.67GB
        Total transferred file size: 1.18MB
        """

        let stats = parseFinalStats(from: output)

        XCTAssertEqual(stats.filesTransferred, 100)
        XCTAssertEqual(stats.bytesTransferred, Int64(1.18 * 1_048_576))
    }

    func testParseFinalStatsNoTransfers() {
        let output = """
        Number of files: 100
        Number of files transferred: 0
        Total file size: 1,000 bytes
        Total transferred file size: 0 bytes
        """

        let stats = parseFinalStats(from: output)

        XCTAssertEqual(stats.filesTransferred, 0)
        XCTAssertEqual(stats.bytesTransferred, 0)
    }

    func testParseFinalStatsEmptyOutput() {
        let stats = parseFinalStats(from: "")

        XCTAssertEqual(stats.filesTransferred, 0)
        XCTAssertEqual(stats.bytesTransferred, 0)
    }

    func testParseFinalStatsGarbageOutput() {
        let stats = parseFinalStats(from: "random garbage that rsync would never output")

        XCTAssertEqual(stats.filesTransferred, 0)
        XCTAssertEqual(stats.bytesTransferred, 0)
    }

    // MARK: - Progress Line Parsing (to-check extraction)

    func testToCheckExtractionFromProgressLine() {
        // Typical rsync progress line:
        // "  648 100%  2.55MB/s  00:00:00 (xfer#323, to-check=6988/42255)"
        let line = "  648 100%  2.55MB/s  00:00:00 (xfer#323, to-check=6988/42255)"

        var overallPercentage: Double = 0
        var filesCompleted = 0
        var totalFiles = 0

        if let toCheckPart = line.range(of: "to-check=") {
            let toCheckString = String(line[toCheckPart.upperBound...])
            let toCheckComponents = toCheckString.components(separatedBy: "/")
            if toCheckComponents.count >= 2 {
                let remaining = Int(toCheckComponents[0]) ?? 0
                totalFiles = Int(toCheckComponents[1].components(separatedBy: ")").first ?? "0") ?? 0
                filesCompleted = totalFiles - remaining
                if totalFiles > 0 {
                    overallPercentage = Double(filesCompleted) / Double(totalFiles) * 100.0
                }
            }
        }

        XCTAssertEqual(totalFiles, 42255)
        XCTAssertEqual(filesCompleted, 42255 - 6988)
        XCTAssertEqual(overallPercentage, Double(42255 - 6988) / 42255.0 * 100.0, accuracy: 0.01)
    }

    func testToCheckExtractionCompletedSync() {
        // When sync is complete: to-check=0/N
        let line = "  4096 100%  10.00MB/s  00:00:00 (xfer#100, to-check=0/100)"

        var totalFiles = 0
        var filesCompleted = 0

        if let toCheckPart = line.range(of: "to-check=") {
            let toCheckString = String(line[toCheckPart.upperBound...])
            let toCheckComponents = toCheckString.components(separatedBy: "/")
            if toCheckComponents.count >= 2 {
                let remaining = Int(toCheckComponents[0]) ?? 0
                totalFiles = Int(toCheckComponents[1].components(separatedBy: ")").first ?? "0") ?? 0
                filesCompleted = totalFiles - remaining
            }
        }

        XCTAssertEqual(filesCompleted, 100)
        XCTAssertEqual(totalFiles, 100)
    }

    func testProgressLineWithoutToCheck() {
        // Some progress lines don't have to-check info
        let line = "  648 100%  2.55MB/s  00:00:00"

        let hasToCheck = line.range(of: "to-check=") != nil
        XCTAssertFalse(hasToCheck)
    }

    // MARK: - RsyncProgress Model Formatting

    func testProgressSpeedFormattedVariousRanges() {
        var progress = RsyncProgress(
            currentFile: "", filesTransferred: 0, totalFiles: 0,
            bytesTransferred: 0, totalBytes: 0,
            percentage: 0, overallPercentage: 0,
            speed: 0, timeRemaining: 0
        )

        // Zero speed
        progress.speed = 0
        XCTAssertTrue(progress.speedFormatted.hasSuffix("/s"))

        // KB range
        progress.speed = 512 * 1024
        XCTAssertTrue(progress.speedFormatted.hasSuffix("/s"))

        // MB range
        progress.speed = 50 * 1_048_576
        XCTAssertTrue(progress.speedFormatted.hasSuffix("/s"))

        // GB range
        progress.speed = 2 * 1_073_741_824
        XCTAssertTrue(progress.speedFormatted.hasSuffix("/s"))
    }

    func testProgressTimeRemainingFormattedEdgeCases() {
        var progress = RsyncProgress(
            currentFile: "", filesTransferred: 0, totalFiles: 0,
            bytesTransferred: 0, totalBytes: 0,
            percentage: 0, overallPercentage: 0,
            speed: 0, timeRemaining: 0
        )

        // Exactly one hour
        progress.timeRemaining = 3600
        XCTAssertEqual(progress.timeRemainingFormatted, "1:00:00")

        // 59 seconds (no hours)
        progress.timeRemaining = 59
        XCTAssertEqual(progress.timeRemainingFormatted, "0:59")

        // Very large time
        progress.timeRemaining = 86400 // 24 hours
        XCTAssertEqual(progress.timeRemainingFormatted, "24:00:00")
    }
}
