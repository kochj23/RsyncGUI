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

        // Restore security-scoped resource access for iCloud Drive
        var destinationURL: URL?
        var accessGranted = false

        if job.effectiveDestinationType == .iCloudDrive {
            NSLog("[RsyncExecutor] iCloud Drive destination detected")

            // Restore bookmark to regain permission
            if let bookmarkData = job.destinationBookmark {
                do {
                    var isStale = false
                    destinationURL = try URL(
                        resolvingBookmarkData: bookmarkData,
                        options: [.withSecurityScope, .withoutUI],
                        relativeTo: nil,
                        bookmarkDataIsStale: &isStale
                    )

                    if let url = destinationURL {
                        accessGranted = url.startAccessingSecurityScopedResource()
                        NSLog("[RsyncExecutor] ✅ Security-scoped access granted to: %@", url.path)
                        NSLog("[RsyncExecutor] Bookmark stale: %@", isStale ? "YES" : "NO")
                    }
                } catch {
                    NSLog("[RsyncExecutor] ⚠️ Failed to restore bookmark: %@", error.localizedDescription)
                    throw RsyncError.iCloudDriveNotAvailable
                }
            } else {
                NSLog("[RsyncExecutor] ⚠️ No security bookmark found - user must click 'iCloud Drive' button to grant permission")
                throw RsyncError.iCloudDriveNotEnabled
            }

            // Create destination directory if it doesn't exist
            if !dryRun {
                try createDestinationDirectory(path: job.destination)
            }
        }

        await MainActor.run {
            isRunning = true
        }

        defer {
            // Release security-scoped resource
            if accessGranted, let url = destinationURL {
                url.stopAccessingSecurityScopedResource()
                NSLog("[RsyncExecutor] ✅ Released security-scoped access")
            }

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

    // MARK: - iCloud Drive Validation

    private func validateiCloudDrive(path: String) throws {
        let iCloudPath = SyncJob.iCloudDrivePath
        let expandedPath = path.replacingOccurrences(of: "~", with: FileManager.default.homeDirectoryForCurrentUser.path)

        NSLog("[RsyncExecutor] 🔍 Validating iCloud Drive path")
        NSLog("[RsyncExecutor] iCloud Drive root: %@", iCloudPath)
        NSLog("[RsyncExecutor] Destination path: %@", expandedPath)
        NSLog("[RsyncExecutor] Path characters: %@", expandedPath.data(using: .utf8)?.base64EncodedString() ?? "unknown")

        // Check if iCloud Drive directory exists
        guard FileManager.default.fileExists(atPath: iCloudPath) else {
            NSLog("[RsyncExecutor] ❌ iCloud Drive directory not found at: %@", iCloudPath)
            throw RsyncError.iCloudDriveNotAvailable
        }

        // Check if path is within iCloud Drive or is iCloud Drive itself
        // Handle trailing slashes by comparing normalized paths
        let normalizedExpanded = expandedPath.hasSuffix("/") ? String(expandedPath.dropLast()) : expandedPath
        let normalizedICloud = iCloudPath.hasSuffix("/") ? String(iCloudPath.dropLast()) : iCloudPath

        NSLog("[RsyncExecutor] Normalized iCloud: %@", normalizedICloud)
        NSLog("[RsyncExecutor] Normalized expanded: %@", normalizedExpanded)
        NSLog("[RsyncExecutor] hasPrefix test: %@", normalizedExpanded.hasPrefix(normalizedICloud) ? "TRUE" : "FALSE")

        if !normalizedExpanded.hasPrefix(normalizedICloud) && normalizedExpanded != normalizedICloud {
            NSLog("[RsyncExecutor] ❌ Path validation failed - neither hasPrefix nor equals")
            NSLog("[RsyncExecutor] Expected prefix: %@", normalizedICloud)
            NSLog("[RsyncExecutor] Got: %@", normalizedExpanded)
            throw RsyncError.iCloudDrivePathInvalid
        }

        // Check if iCloud Drive is accessible (not just folder existing but actually mounted)
        guard FileManager.default.isReadableFile(atPath: iCloudPath) else {
            NSLog("[RsyncExecutor] ❌ iCloud Drive not readable at: %@", iCloudPath)
            throw RsyncError.iCloudDriveNotEnabled
        }

        NSLog("[RsyncExecutor] ✅ iCloud Drive validation passed: %@", expandedPath)
    }

    private func createDestinationDirectory(path: String) throws {
        var expandedPath = path.replacingOccurrences(of: "~", with: FileManager.default.homeDirectoryForCurrentUser.path)

        // Remove trailing slash for directory operations
        if expandedPath.hasSuffix("/") {
            expandedPath = String(expandedPath.dropLast())
        }

        // Check if directory already exists
        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: expandedPath, isDirectory: &isDirectory) {
            if isDirectory.boolValue {
                print("[RsyncExecutor] ✅ Destination directory exists: \(expandedPath)")
                return
            } else {
                print("[RsyncExecutor] ⚠️ Path exists but is a file, not directory: \(expandedPath)")
                throw RsyncError.invalidConfiguration // Path exists but is a file, not directory
            }
        }

        // For iCloud Drive, verify parent (iCloud Drive root) exists first
        let iCloudRoot = SyncJob.iCloudDrivePath
        if expandedPath.hasPrefix(iCloudRoot) && expandedPath != iCloudRoot {
            var isDir: ObjCBool = false
            if !FileManager.default.fileExists(atPath: iCloudRoot, isDirectory: &isDir) || !isDir.boolValue {
                print("[RsyncExecutor] ❌ iCloud Drive root not accessible: \(iCloudRoot)")
                throw RsyncError.iCloudDriveNotAvailable
            }
        }

        // Create directory with intermediate directories
        do {
            try FileManager.default.createDirectory(atPath: expandedPath, withIntermediateDirectories: true, attributes: nil)
            print("[RsyncExecutor] ✅ Created destination directory: \(expandedPath)")

            // For iCloud Drive, wait a moment for iCloud to recognize the new folder
            if expandedPath.contains("com~apple~CloudDocs") {
                Thread.sleep(forTimeInterval: 0.5)
            }
        } catch {
            print("[RsyncExecutor] ❌ Failed to create directory: \(error.localizedDescription)")
            print("[RsyncExecutor] Path: \(expandedPath)")
            throw RsyncError.executionFailed(error)
        }
    }

    // MARK: - Command Building

    private func buildCommand(for job: SyncJob, dryRun: Bool) -> [String] {
        // Get rsync path from settings
        let rsyncPath = UserDefaults.standard.string(forKey: "defaultRsyncPath") ?? "/usr/bin/rsync"
        var args = [rsyncPath]

        // Add rsync options
        var options = job.options
        if dryRun {
            options.dryRun = true
        }
        args.append(contentsOf: options.toArguments())

        // Handle destination type
        let destType = job.effectiveDestinationType

        // Handle remote SSH connections
        if destType == .remoteSSH, let host = job.remoteHost, let user = job.remoteUser {
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
            var expandedDest = job.destination.replacingOccurrences(of: "~", with: FileManager.default.homeDirectoryForCurrentUser.path)

            // For iCloud Drive or local directories, ensure trailing slash if source ends with slash
            // This tells rsync to sync contents into the directory rather than creating a subdirectory
            if (destType == .iCloudDrive || destType == .local) && job.source.hasSuffix("/") && !expandedDest.hasSuffix("/") {
                expandedDest += "/"
            }

            args.append(expandedSource)
            args.append(expandedDest)

            print("[RsyncExecutor] Source: \(expandedSource)")
            print("[RsyncExecutor] Destination: \(expandedDest)")
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

            // Thread-safe data accumulation using NSLock
            let dataLock = NSLock()
            var outputData = Data()
            var errorData = Data()

            // Read output asynchronously
            outputPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
                guard let self = self else { return }
                let data = handle.availableData
                guard !data.isEmpty else { return }

                // Thread-safe append
                dataLock.lock()
                outputData.append(data)
                dataLock.unlock()

                if let output = String(data: data, encoding: .utf8) {
                    // Parse progress from output
                    self.parseProgress(from: output)
                }
            }

            errorPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
                guard let self = self else { return }
                let data = handle.availableData
                guard !data.isEmpty else { return }

                // Thread-safe append
                dataLock.lock()
                errorData.append(data)
                dataLock.unlock()
            }

            process.terminationHandler = { [weak self] process in
                guard let self = self else {
                    continuation.resume(throwing: RsyncError.cancelled)
                    return
                }

                outputPipe.fileHandleForReading.readabilityHandler = nil
                errorPipe.fileHandleForReading.readabilityHandler = nil

                mutableResult.endTime = Date()

                // Thread-safe read of accumulated data
                dataLock.lock()
                let finalOutputData = outputData
                let finalErrorData = errorData
                dataLock.unlock()

                if let output = String(data: finalOutputData, encoding: .utf8) {
                    mutableResult.output = output

                    // Parse final statistics
                    let stats = self.parseFinalStats(from: output)
                    mutableResult.filesTransferred = stats.filesTransferred
                    mutableResult.bytesTransferred = stats.bytesTransferred
                }

                if let errorOutput = String(data: finalErrorData, encoding: .utf8), !errorOutput.isEmpty {
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
        // Safety: Limit line length to prevent memory issues
        guard line.count < 10000 else { return }

        // Extract current file being transferred
        let trimmed = line.trimmingCharacters(in: .whitespaces)

        // Safety: Validate trimmed string is reasonable
        guard !trimmed.isEmpty && trimmed.count < 5000 && !trimmed.hasPrefix("sending") else {
            return
        }

        Task { @MainActor [weak self] in
            guard let self = self else { return }
            if var currentProgress = self.progress {
                currentProgress.currentFile = trimmed
                self.progress = currentProgress
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
    case iCloudDriveNotAvailable
    case iCloudDriveNotEnabled
    case iCloudDrivePathInvalid

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
        case .iCloudDriveNotAvailable:
            return "iCloud Drive is not available. Check that iCloud Drive is enabled in System Settings → Apple ID → iCloud."
        case .iCloudDriveNotEnabled:
            return "Permission not granted. Click the 'iCloud Drive' button in job editor and select the folder to grant RsyncGUI access permission."
        case .iCloudDrivePathInvalid:
            return "Invalid iCloud Drive path. The path must be within iCloud Drive folder."
        }
    }
}
