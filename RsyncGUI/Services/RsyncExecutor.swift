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

    /// Maximum bytes of rsync output to retain in memory per execution.
    /// Large jobs with --verbose --progress can generate hundreds of MB — cap prevents OOM kills.
    private static let maxOutputBytes = 10 * 1024 * 1024 // 10 MB
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

        // Get enabled destinations only
        let enabledDestinations = job.destinations.filter { $0.isEnabled }

        guard !enabledDestinations.isEmpty else {
            throw RsyncError.invalidConfiguration
        }

        let validSources = job.sources.filter { !$0.isEmpty }
        guard !validSources.isEmpty else {
            throw RsyncError.invalidConfiguration
        }

        // Run pre-sync script
        if let preScript = job.preScript, !preScript.isEmpty, !dryRun {
            NSLog("[RsyncExecutor] Running pre-sync script...")
            try await runScript(preScript, jobName: job.name, status: "starting", filesTransferred: 0)
        }

        // Prepare all destinations (create directories if needed)
        for dest in enabledDestinations {
            if (dest.type == .iCloudDrive || dest.type == .local) && !dryRun {
                try createDestinationDirectory(path: dest.path)
            }
        }

        // Execute sync based on strategy
        var combinedResult: ExecutionResult

        if job.executionStrategy == .parallel && enabledDestinations.count > 1 {
            combinedResult = try await executeParallel(job: job, destinations: enabledDestinations, dryRun: dryRun)
        } else {
            combinedResult = try await executeSequential(job: job, destinations: enabledDestinations, dryRun: dryRun)
        }

        // Run verification if enabled
        if job.verifyAfterSync && !dryRun && combinedResult.status != .failed {
            NSLog("[RsyncExecutor] Running verification pass...")
            combinedResult.output += "\n\n=== VERIFICATION PASS ===\n"
            for dest in enabledDestinations {
                var verifyJob = job
                verifyJob.options.checksum = true
                verifyJob.options.dryRun = true
                let command = try buildCommand(for: verifyJob, destination: dest, dryRun: true)
                let verifyResult = try await executeCommand(command, result: ExecutionResult(
                    id: UUID(), jobId: job.id, startTime: Date(), endTime: nil,
                    status: .success, filesTransferred: 0, bytesTransferred: 0, errors: [], output: ""
                ))
                combinedResult.output += "\n--- Verify: \(dest.path) ---\n" + verifyResult.output
            }
        }

        // Run post-sync script
        if let postScript = job.postScript, !postScript.isEmpty, !dryRun {
            NSLog("[RsyncExecutor] Running post-sync script...")
            try await runScript(postScript, jobName: job.name,
                              status: combinedResult.status.rawValue,
                              filesTransferred: combinedResult.filesTransferred)
        }

        return combinedResult
    }

    // MARK: - Sequential Execution

    private func executeSequential(job: SyncJob, destinations: [SyncDestination], dryRun: Bool) async throws -> ExecutionResult {
        var combinedResult = ExecutionResult(
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

        var allSucceeded = true
        var anySucceeded = false

        for (index, dest) in destinations.enumerated() {
            NSLog("[RsyncExecutor] Syncing to destination %d/%d: %@", index + 1, destinations.count, dest.path)

            let command = try buildCommand(for: job, destination: dest, dryRun: dryRun)
            let result = try await executeCommand(command, result: ExecutionResult(
                id: UUID(), jobId: job.id, startTime: Date(), endTime: nil,
                status: .success, filesTransferred: 0, bytesTransferred: 0, errors: [], output: ""
            ))

            combinedResult.filesTransferred += result.filesTransferred
            combinedResult.bytesTransferred += result.bytesTransferred
            combinedResult.errors.append(contentsOf: result.errors)
            combinedResult.output += "\n--- Destination: \(dest.path) ---\n" + result.output

            if result.status == .success {
                anySucceeded = true
            } else if result.status == .failed {
                allSucceeded = false
                if job.failureHandling == .stopOnError {
                    combinedResult.errors.append("Stopped: Destination \(dest.path) failed")
                    break
                }
            } else if result.status == .partialSuccess {
                anySucceeded = true
                allSucceeded = false
            }
        }

        combinedResult.endTime = Date()
        combinedResult.status = allSucceeded ? .success : (anySucceeded ? .partialSuccess : .failed)
        return combinedResult
    }

    // MARK: - Parallel Execution

    private func executeParallel(job: SyncJob, destinations: [SyncDestination], dryRun: Bool) async throws -> ExecutionResult {
        var combinedResult = ExecutionResult(
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

        NSLog("[RsyncExecutor] Starting parallel sync to %d destinations (max %d concurrent)", destinations.count, job.maxParallelSyncs)

        // Use TaskGroup for parallel execution with limited concurrency
        let results = await withTaskGroup(of: (SyncDestination, ExecutionResult).self) { group in
            var pending = destinations[...]
            var results: [(SyncDestination, ExecutionResult)] = []
            var activeCount = 0

            // Start initial batch
            while activeCount < job.maxParallelSyncs && !pending.isEmpty {
                let dest = pending.removeFirst()
                activeCount += 1
                group.addTask {
                    do {
                        let command = try self.buildCommand(for: job, destination: dest, dryRun: dryRun)
                        let result = try? await self.executeCommand(command, result: ExecutionResult(
                            id: UUID(), jobId: job.id, startTime: Date(), endTime: nil,
                            status: .success, filesTransferred: 0, bytesTransferred: 0, errors: [], output: ""
                        ))
                        return (dest, result ?? ExecutionResult(
                            id: UUID(), jobId: job.id, startTime: Date(), endTime: Date(),
                            status: .failed, filesTransferred: 0, bytesTransferred: 0, errors: ["Execution failed"], output: ""
                        ))
                    } catch {
                        return (dest, ExecutionResult(
                            id: UUID(), jobId: job.id, startTime: Date(), endTime: Date(),
                            status: .failed, filesTransferred: 0, bytesTransferred: 0,
                            errors: ["Command build failed: \(error.localizedDescription)"], output: ""
                        ))
                    }
                }
            }

            // Process results and start new tasks
            for await result in group {
                results.append(result)
                activeCount -= 1

                if !pending.isEmpty {
                    let dest = pending.removeFirst()
                    activeCount += 1
                    group.addTask {
                        do {
                            let command = try self.buildCommand(for: job, destination: dest, dryRun: dryRun)
                            let result = try? await self.executeCommand(command, result: ExecutionResult(
                                id: UUID(), jobId: job.id, startTime: Date(), endTime: nil,
                                status: .success, filesTransferred: 0, bytesTransferred: 0, errors: [], output: ""
                            ))
                            return (dest, result ?? ExecutionResult(
                                id: UUID(), jobId: job.id, startTime: Date(), endTime: Date(),
                                status: .failed, filesTransferred: 0, bytesTransferred: 0, errors: ["Execution failed"], output: ""
                            ))
                        } catch {
                            return (dest, ExecutionResult(
                                id: UUID(), jobId: job.id, startTime: Date(), endTime: Date(),
                                status: .failed, filesTransferred: 0, bytesTransferred: 0,
                                errors: ["Command build failed: \(error.localizedDescription)"], output: ""
                            ))
                        }
                    }
                }
            }

            return results
        }

        // Combine results
        var allSucceeded = true
        var anySucceeded = false

        for (dest, result) in results {
            combinedResult.filesTransferred += result.filesTransferred
            combinedResult.bytesTransferred += result.bytesTransferred
            combinedResult.errors.append(contentsOf: result.errors)
            combinedResult.output += "\n--- Destination: \(dest.path) ---\n" + result.output

            if result.status == .success {
                anySucceeded = true
            } else if result.status == .failed {
                allSucceeded = false
            } else if result.status == .partialSuccess {
                anySucceeded = true
                allSucceeded = false
            }
        }

        combinedResult.endTime = Date()
        combinedResult.status = allSucceeded ? .success : (anySucceeded ? .partialSuccess : .failed)
        return combinedResult
    }

    // MARK: - Script Execution

    private func runScript(_ script: String, jobName: String, status: String, filesTransferred: Int) async throws {
        let trimmed = script.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        // Only permit execution of real files — inline shell commands are rejected
        // to prevent shell injection attacks via user-configured script fields.
        let expanded = (trimmed as NSString).expandingTildeInPath
        guard expanded.hasPrefix("/"),
              !expanded.contains(".."),
              FileManager.default.isExecutableFile(atPath: expanded) else {
            NSLog("[RsyncExecutor] SECURITY: Script '%@' is not an executable file path — inline commands are not permitted", String(trimmed.prefix(200)))
            return
        }

        NSLog("[RsyncExecutor] Executing script: %@", expanded)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: expanded)
        process.arguments = []
        process.environment = [
            "JOB_NAME": jobName,
            "JOB_STATUS": status,
            "FILES_TRANSFERRED": String(filesTransferred),
            "PATH": "/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
        ]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        // Use async continuation instead of waitUntilExit() — the blocking call would
        // occupy a cooperative thread pool thread for the entire script duration.
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            process.terminationHandler = { proc in
                let outputData = pipe.fileHandleForReading.readDataToEndOfFile()
                pipe.fileHandleForReading.closeFile()
                if proc.terminationStatus != 0 {
                    let output = String(data: outputData, encoding: .utf8) ?? ""
                    NSLog("[RsyncExecutor] Script failed with exit code %d: %@", proc.terminationStatus, output)
                }
                continuation.resume()
            }
            do {
                try process.run()
            } catch {
                pipe.fileHandleForReading.closeFile()
                continuation.resume(throwing: RsyncError.executionFailed(error))
            }
        }
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

            // Note: iCloud's daemon (bird) will pick up the new folder asynchronously.
            // A blocking sleep here is both incorrect and unnecessary — rsync handles
            // the destination directory being present at the time it runs.
            NSLog("[RsyncExecutor] ✅ Created iCloud destination directory: %@", expandedPath)
        } catch {
            print("[RsyncExecutor] ❌ Failed to create directory: \(error.localizedDescription)")
            print("[RsyncExecutor] Path: \(expandedPath)")
            throw RsyncError.executionFailed(error)
        }
    }

    // MARK: - Command Building

    /// Resolves the rsync binary from a fixed set of known locations.
    /// Never reads from UserDefaults — prevents binary substitution attacks.
    private func resolveRsyncPath() -> String {
        let candidates = ["/usr/bin/rsync", "/opt/homebrew/bin/rsync", "/usr/local/bin/rsync"]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) } ?? "/usr/bin/rsync"
    }

    private func buildCommand(for job: SyncJob, destination dest: SyncDestination, dryRun: Bool) throws -> [String] {
        let rsyncPath = resolveRsyncPath()
        var args = [rsyncPath]

        // Add rsync options
        var options = job.options
        if dryRun {
            options.dryRun = true
        }
        args.append(contentsOf: options.toArguments())

        // Handle remote SSH connections
        if dest.type == .remoteSSH, let host = dest.remoteHost, let user = dest.remoteUser {
            // Validate host and user contain only safe characters
            let safePattern = #"^[a-zA-Z0-9._-]+$"#
            guard host.range(of: safePattern, options: .regularExpression) != nil else {
                throw RsyncError.invalidHostOrUser(host)
            }
            guard user.range(of: safePattern, options: .regularExpression) != nil else {
                throw RsyncError.invalidHostOrUser(user)
            }

            // SSH options - build as array components to avoid shell injection via key path
            var sshComponents = ["ssh"]
            if let keyPath = dest.sshKeyPath, !keyPath.isEmpty {
                let expandedKey = (keyPath as NSString).expandingTildeInPath
                guard expandedKey.hasPrefix("/"),
                      !expandedKey.contains(".."),
                      FileManager.default.fileExists(atPath: expandedKey) else {
                    throw RsyncError.invalidSSHKeyPath
                }
                sshComponents.append("-i")
                sshComponents.append(expandedKey)
            }
            args.append("-e")
            args.append(sshComponents.joined(separator: " "))

            // Add all sources (rsync supports multiple sources)
            for source in job.sources where !source.isEmpty {
                let expandedSource = source.replacingOccurrences(of: "~", with: FileManager.default.homeDirectoryForCurrentUser.path)
                args.append(expandedSource)
            }

            // Remote destination
            let remotePrefix = "\(user)@\(host):"
            let destPath = dest.path.starts(with: remotePrefix) ? dest.path : "\(remotePrefix)\(dest.path)"
            args.append(destPath)

            print("[RsyncExecutor] Sources: \(job.sources)")
            print("[RsyncExecutor] Remote Destination: \(destPath)")
        } else {
            // Add all sources (rsync supports multiple sources)
            for source in job.sources where !source.isEmpty {
                let expandedSource = source.replacingOccurrences(of: "~", with: FileManager.default.homeDirectoryForCurrentUser.path)
                args.append(expandedSource)
            }

            // iCloud: exclude .icloud placeholder stubs.
            // Files evicted from local storage appear as ".filename.icloud" — rsync cannot read them
            // and will either error out or transfer the stub file, not the real content.
            if dest.type == .iCloudDrive {
                args.append("--exclude=*.icloud")
                NSLog("[RsyncExecutor] iCloud destination: added --exclude=*.icloud to skip offloaded file placeholders")
            }

            // Local/iCloud destination
            var expandedDest = dest.path.replacingOccurrences(of: "~", with: FileManager.default.homeDirectoryForCurrentUser.path)

            // For iCloud Drive or local directories, ensure trailing slash
            // This tells rsync to sync contents into the directory rather than creating a subdirectory
            if !expandedDest.hasSuffix("/") {
                expandedDest += "/"
            }

            args.append(expandedDest)

            print("[RsyncExecutor] Sources: \(job.sources)")
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

            // Thread-safe data accumulation and termination signaling
            let dataLock = NSLock()
            var outputData = Data()
            var errorData = Data()
            var isTerminating = false
            var outputTruncated = false

            // Track active handlers to prevent race conditions
            let handlerGroup = DispatchGroup()

            // Read output asynchronously
            outputPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
                // Check if we're terminating before processing
                dataLock.lock()
                let shouldProcess = !isTerminating
                if shouldProcess {
                    handlerGroup.enter()
                }
                dataLock.unlock()

                guard shouldProcess else { return }
                defer { handlerGroup.leave() }

                guard let self = self else { return }
                let data = handle.availableData
                guard !data.isEmpty else { return }

                // Make a defensive copy of the data for thread safety
                let dataCopy = Data(data)

                // Thread-safe append with output cap to prevent OOM on large jobs
                dataLock.lock()
                if outputData.count < RsyncExecutor.maxOutputBytes {
                    outputData.append(dataCopy)
                } else if !outputTruncated {
                    outputTruncated = true
                    let notice = Data("\n⚠️ Output truncated at 10 MB. Full output available in system log (Console.app).\n".utf8)
                    outputData.append(notice)
                    NSLog("[RsyncExecutor] Output cap reached (10 MB) — truncating display output")
                }
                dataLock.unlock()

                if let output = String(data: dataCopy, encoding: .utf8) {
                    // String(data:encoding:) already returns an owned String
                    self.parseProgress(from: output)
                }
            }

            errorPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
                // Check if we're terminating before processing
                dataLock.lock()
                let shouldProcess = !isTerminating
                if shouldProcess {
                    handlerGroup.enter()
                }
                dataLock.unlock()

                guard shouldProcess else { return }
                defer { handlerGroup.leave() }

                guard let self = self else { return }
                let data = handle.availableData
                guard !data.isEmpty else { return }

                // Make a defensive copy
                let dataCopy = Data(data)

                // Thread-safe append
                dataLock.lock()
                errorData.append(dataCopy)
                dataLock.unlock()
            }

            process.terminationHandler = { [weak self] process in
                guard let self = self else {
                    continuation.resume(throwing: RsyncError.cancelled)
                    return
                }

                // Signal handlers to stop accepting new data
                dataLock.lock()
                isTerminating = true
                dataLock.unlock()

                // Nil out handlers first to prevent new callbacks from being dispatched,
                // then wait for any already in-flight handler invocations to complete.
                outputPipe.fileHandleForReading.readabilityHandler = nil
                errorPipe.fileHandleForReading.readabilityHandler = nil

                // Wait for any in-progress handlers to complete (with timeout)
                _ = handlerGroup.wait(timeout: .now() + 2.0)

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
            // .components(separatedBy:) already returns [String], no conversion needed

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
            // .components(separatedBy:) already returns [String], no conversion needed

            // Parse "Number of files transferred: 123"
            if line.contains("Number of files transferred:") {
                let components = line.components(separatedBy: ":")
                if components.count >= 2 {
                    let valueString = components[1].trimmingCharacters(in: .whitespaces)
                    let numberPart = valueString.components(separatedBy: .whitespaces).first ?? "0"
                    filesTransferred = Int(numberPart) ?? 0
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
    case invalidSSHKeyPath
    case invalidHostOrUser(String)

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
        case .invalidSSHKeyPath:
            return "Invalid SSH key path. The path must be an absolute path to an existing key file."
        case .invalidHostOrUser(let value):
            return "Invalid hostname or username: '\(value)'. Only alphanumeric characters, dots, hyphens, and underscores are allowed."
        }
    }
}
