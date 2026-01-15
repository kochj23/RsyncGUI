//
//  RsyncExecutor.swift
//  RsyncGUI
//
//  Created by Jordan Koch on 1/14/26.
//

import Foundation
import Combine

/// Executes rsync commands and provides real-time progress updates
class RsyncExecutor: ObservableObject {
    @Published var progress: RsyncProgress?
    @Published var isRunning = false

    private var process: Process?
    private var progressUpdateSubject = PassthroughSubject<RsyncProgress, Never>()

    var progressPublisher: AnyPublisher<RsyncProgress, Never> {
        progressUpdateSubject.eraseToAnyPublisher()
    }

    // MARK: - Execution

    func execute(job: SyncJob, dryRun: Bool = false) async throws -> ExecutionResult {
        guard !isRunning else {
            throw RsyncError.alreadyRunning
        }

        await MainActor.run {
            isRunning = true
        }

        defer {
            Task { @MainActor in
                isRunning = false
            }
        }

        let result = ExecutionResult(
            id: UUID(),
            jobId: job.id,
            startTime: Date(),
            endTime: nil,
            status: .success,
            filesTransferred: 0,
            bytesTransferred: 0,
            errors: [],
            output: ""
        )

        // Build rsync command
        let command = buildCommand(for: job, dryRun: dryRun)

        // Execute
        return try await executeCommand(command, result: result)
    }

    func cancel() {
        process?.terminate()
        Task { @MainActor [weak self] in
            guard let self = self else { return }
            self.isRunning = false
        }
    }

    // MARK: - Command Building

    private func buildCommand(for job: SyncJob, dryRun: Bool) -> [String] {
        var args = ["/usr/bin/rsync"]

        // Add rsync options
        var options = job.options
        if dryRun {
            options.dryRun = true
        }
        args.append(contentsOf: options.toArguments())

        // Handle remote connections
        if job.isRemote, let host = job.remoteHost, let user = job.remoteUser {
            // SSH options
            var sshCommand = "ssh"
            if let keyPath = job.sshKeyPath {
                sshCommand += " -i \(keyPath)"
            }
            args.append("-e")
            args.append(sshCommand)

            // Source or destination is remote
            // Detect if source or dest has host prefix
            let remotePrefix = "\(user)@\(host):"

            let source = job.source.starts(with: remotePrefix) ? job.source : job.source
            let destination = job.destination.starts(with: remotePrefix) ? job.destination : job.destination

            args.append(source)
            args.append(destination)
        } else {
            // Expand ~ to home directory
            let expandedSource = job.source.replacingOccurrences(of: "~", with: FileManager.default.homeDirectoryForCurrentUser.path)
            let expandedDest = job.destination.replacingOccurrences(of: "~", with: FileManager.default.homeDirectoryForCurrentUser.path)

            args.append(expandedSource)
            args.append(expandedDest)
        }

        return args
    }

    // MARK: - Command Execution

    private func executeCommand(_ command: [String], result: ExecutionResult) async throws -> ExecutionResult {
        var mutableResult = result

        return try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            self.process = process

            process.executableURL = URL(fileURLWithPath: command[0])
            process.arguments = Array(command.dropFirst())

            let outputPipe = Pipe()
            let errorPipe = Pipe()

            process.standardOutput = outputPipe
            process.standardError = errorPipe

            var outputData = Data()
            var errorData = Data()

            // Read output asynchronously
            outputPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
                guard let self = self else { return }
                let data = handle.availableData
                guard !data.isEmpty else { return }

                outputData.append(data)

                if let output = String(data: data, encoding: .utf8) {
                    // Parse progress from output
                    self.parseProgress(from: output)
                }
            }

            errorPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
                guard let self = self else { return }
                let data = handle.availableData
                guard !data.isEmpty else { return }
                errorData.append(data)
            }

            process.terminationHandler = { [weak self] process in
                guard let self = self else {
                    continuation.resume(throwing: RsyncError.cancelled)
                    return
                }

                outputPipe.fileHandleForReading.readabilityHandler = nil
                errorPipe.fileHandleForReading.readabilityHandler = nil

                mutableResult.endTime = Date()

                if let output = String(data: outputData, encoding: .utf8) {
                    mutableResult.output = output

                    // Parse final statistics
                    let stats = self.parseFinalStats(from: output)
                    mutableResult.filesTransferred = stats.filesTransferred
                    mutableResult.bytesTransferred = stats.bytesTransferred
                }

                if let errorOutput = String(data: errorData, encoding: .utf8), !errorOutput.isEmpty {
                    mutableResult.errors.append(errorOutput)
                }

                // Determine status
                if process.terminationStatus == 0 {
                    mutableResult.status = .success
                } else if process.terminationStatus == 23 {
                    // rsync exit code 23 = partial transfer (some files/attrs not transferred)
                    mutableResult.status = .partialSuccess
                } else if process.terminationReason == .exit {
                    mutableResult.status = .failed
                } else {
                    mutableResult.status = .cancelled
                }

                continuation.resume(returning: mutableResult)
            }

            do {
                try process.run()
            } catch {
                continuation.resume(throwing: RsyncError.executionFailed(error))
            }
        }
    }

    // MARK: - Progress Parsing

    private func parseProgress(from output: String) {
        // Parse rsync progress output
        // Format: "  1,234,567  56%  123.45MB/s    0:01:23"
        // Or: "sent 123 bytes  received 456 bytes  789.00 bytes/sec"

        let lines = output.components(separatedBy: .newlines)

        for line in lines {
            // Parse progress line (with --progress flag)
            if line.contains("%") {
                parseProgressLine(line)
            }

            // Parse file transfer line (with -v flag)
            if line.hasPrefix("sending incremental file list") || line.contains("/") {
                parseFileTransferLine(line)
            }
        }
    }

    private func parseProgressLine(_ line: String) {
        // Example: "  648 100%  2.55MB/s  00:00:00 (xfer#323, to-check=6988/42255)"
        let components = line.components(separatedBy: .whitespaces).filter { !$0.isEmpty }

        guard components.count >= 4 else { return }

        // Extract current file percentage
        var currentFilePercentage: Double = 0
        if let percentString = components.first(where: { $0.hasSuffix("%") }),
           let percentValue = Double(percentString.replacingOccurrences(of: "%", with: "")) {
            currentFilePercentage = percentValue
        }

        // Extract overall progress from "to-check=X/Y"
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

        // Extract speed
        let speedString = components.first { $0.contains("B/s") } ?? "0B/s"
        let speed = parseSpeed(speedString)

        // Extract time remaining
        let timeString = components.first { $0.contains(":") && $0.count <= 8 } ?? "0:00:00"
        let timeRemaining = parseTime(timeString)

        let progress = RsyncProgress(
            currentFile: self.progress?.currentFile ?? "",
            filesTransferred: filesCompleted,
            totalFiles: totalFiles,
            bytesTransferred: self.progress?.bytesTransferred ?? 0,
            totalBytes: self.progress?.totalBytes ?? 0,
            percentage: currentFilePercentage,
            overallPercentage: overallPercentage,
            speed: speed,
            timeRemaining: timeRemaining
        )

        Task { @MainActor [weak self] in
            guard let self = self else { return }
            self.progress = progress
        }

        progressUpdateSubject.send(progress)
    }

    private func parseFileTransferLine(_ line: String) {
        // Extract current file being transferred
        let trimmed = line.trimmingCharacters(in: .whitespaces)

        if !trimmed.isEmpty && !trimmed.hasPrefix("sending") {
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                if var currentProgress = self.progress {
                    currentProgress.currentFile = trimmed
                    self.progress = currentProgress
                }
            }
        }
    }

    private func parseFinalStats(from output: String) -> (filesTransferred: Int, bytesTransferred: Int64) {
        var filesTransferred = 0
        var bytesTransferred: Int64 = 0

        let lines = output.components(separatedBy: .newlines)

        for line in lines {
            // Parse "Number of files transferred: 123"
            if line.contains("Number of files transferred:") {
                let components = line.components(separatedBy: ":")
                if components.count >= 2,
                   let count = Int(components[1].trimmingCharacters(in: .whitespaces).components(separatedBy: .whitespaces).first ?? "0") {
                    filesTransferred = count
                }
            }

            // Parse "Total transferred file size: 123,456 bytes"
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

    // MARK: - Parsing Helpers

    private func parseSpeed(_ speedString: String) -> Double {
        // Parse "123.45MB/s" -> bytes per second
        let cleaned = speedString.replacingOccurrences(of: "/s", with: "")

        if cleaned.hasSuffix("GB") {
            if let value = Double(cleaned.replacingOccurrences(of: "GB", with: "")) {
                return value * 1_073_741_824 // 1024^3
            }
        } else if cleaned.hasSuffix("MB") {
            if let value = Double(cleaned.replacingOccurrences(of: "MB", with: "")) {
                return value * 1_048_576 // 1024^2
            }
        } else if cleaned.hasSuffix("KB") {
            if let value = Double(cleaned.replacingOccurrences(of: "KB", with: "")) {
                return value * 1024
            }
        } else if cleaned.hasSuffix("B") {
            return Double(cleaned.replacingOccurrences(of: "B", with: "")) ?? 0
        }

        return 0
    }

    private func parseTime(_ timeString: String) -> TimeInterval {
        // Parse "1:23:45" -> seconds
        let components = timeString.components(separatedBy: ":")
        guard components.count >= 2 else { return 0 }

        let hours = Double(components[0]) ?? 0
        let minutes = Double(components[1]) ?? 0
        let seconds = components.count >= 3 ? (Double(components[2]) ?? 0) : 0

        return hours * 3600 + minutes * 60 + seconds
    }

    private func parseBytes(_ bytesString: String) -> Int64 {
        // Parse "123,456 bytes" or "123.45MB"
        let cleaned = bytesString.replacingOccurrences(of: ",", with: "")

        if cleaned.contains("bytes") {
            let numberString = cleaned.components(separatedBy: .whitespaces).first ?? "0"
            return Int64(numberString) ?? 0
        }

        // Handle unit suffixes
        if cleaned.hasSuffix("GB") {
            if let value = Double(cleaned.replacingOccurrences(of: "GB", with: "")) {
                return Int64(value * 1_073_741_824)
            }
        } else if cleaned.hasSuffix("MB") {
            if let value = Double(cleaned.replacingOccurrences(of: "MB", with: "")) {
                return Int64(value * 1_048_576)
            }
        } else if cleaned.hasSuffix("KB") {
            if let value = Double(cleaned.replacingOccurrences(of: "KB", with: "")) {
                return Int64(value * 1024)
            }
        }

        return Int64(cleaned) ?? 0
    }
}

// MARK: - Progress Model

struct RsyncProgress {
    var currentFile: String
    var filesTransferred: Int
    var totalFiles: Int
    var bytesTransferred: Int64
    var totalBytes: Int64
    var percentage: Double // Current file percentage (from rsync per-file output)
    var overallPercentage: Double // Overall sync percentage (calculated from files done/total)
    var speed: Double // bytes per second
    var timeRemaining: TimeInterval

    var speedFormatted: String {
        ByteCountFormatter.string(fromByteCount: Int64(speed), countStyle: .binary) + "/s"
    }

    var bytesTransferredFormatted: String {
        ByteCountFormatter.string(fromByteCount: bytesTransferred, countStyle: .binary)
    }

    var totalBytesFormatted: String {
        ByteCountFormatter.string(fromByteCount: totalBytes, countStyle: .binary)
    }

    var timeRemainingFormatted: String {
        let hours = Int(timeRemaining) / 3600
        let minutes = (Int(timeRemaining) % 3600) / 60
        let seconds = Int(timeRemaining) % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%d:%02d", minutes, seconds)
        }
    }
}

// MARK: - Errors

enum RsyncError: LocalizedError {
    case alreadyRunning
    case executionFailed(Error)
    case invalidConfiguration
    case cancelled

    var errorDescription: String? {
        switch self {
        case .alreadyRunning:
            return "Rsync is already running"
        case .executionFailed(let error):
            return "Rsync execution failed: \(error.localizedDescription)"
        case .invalidConfiguration:
            return "Invalid rsync configuration"
        case .cancelled:
            return "Rsync was cancelled"
        }
    }
}
