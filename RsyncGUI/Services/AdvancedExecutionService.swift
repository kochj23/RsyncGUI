//
//  AdvancedExecutionService.swift
//  RsyncGUI
//
//  Created by Jordan Koch on 1/14/26.
//

import Foundation
import CryptoKit

/// Advanced execution features: parallelism, dependencies, conditional execution, delta reporting
class AdvancedExecutionService {
    static let shared = AdvancedExecutionService()

    private init() {}

    // MARK: - Parallel Execution

    /// Execute rsync with parallelism for tons of tiny files
    func executeParallel(job: SyncJob, dryRun: Bool = false) async throws -> ExecutionResult {
        guard let parallelConfig = job.parallelism, parallelConfig.isEnabled else {
            // No parallelism, use standard execution
            return try await RsyncExecutor().execute(job: job, dryRun: dryRun)
        }

        let startTime = Date()
        print("[Parallel] Starting parallel rsync with \(parallelConfig.numberOfThreads) threads")

        // Analyze source directory to split work
        let fileList = try await analyzeSourceDirectory(path: job.source)
        print("[Parallel] Found \(fileList.count) files to sync")

        // Split files across threads based on strategy
        let fileBatches = splitFilesForParallel(
            files: fileList,
            threadCount: parallelConfig.numberOfThreads,
            strategy: parallelConfig.strategy
        )

        // Create temp directory for file lists
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("rsyncgui-parallel-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        // Execute rsync in parallel for each batch
        return try await withThrowingTaskGroup(of: ExecutionResult.self) { group in
            for (index, batch) in fileBatches.enumerated() {
                // Write file list to temp file
                let fileListPath = tempDir.appendingPathComponent("files-\(index).txt")
                let fileListContent = batch.joined(separator: "\n")
                try fileListContent.write(to: fileListPath, atomically: true, encoding: .utf8)

                // Create job variant with --files-from
                var threadJob = job
                threadJob.options.filesFrom = fileListPath.path
                threadJob.options.from0 = false

                // Add to task group
                group.addTask {
                    print("[Parallel] Thread \(index + 1): Processing \(batch.count) files")
                    let executor = RsyncExecutor()
                    return try await executor.execute(job: threadJob, dryRun: dryRun)
                }
            }

            // Collect results from all threads
            var combinedResult = ExecutionResult(
                id: UUID(),
                jobId: job.id,
                startTime: startTime,
                endTime: nil,
                status: .success,
                filesTransferred: 0,
                bytesTransferred: 0,
                errors: [],
                output: ""
            )

            for try await result in group {
                combinedResult.filesTransferred += result.filesTransferred
                combinedResult.bytesTransferred += result.bytesTransferred
                combinedResult.errors.append(contentsOf: result.errors)
                combinedResult.output += "\n--- Thread Output ---\n" + result.output

                if result.status != .success {
                    combinedResult.status = .partialSuccess
                }
            }

            combinedResult.endTime = Date()
            print("[Parallel] Complete: \(combinedResult.filesTransferred) files, \(ByteCountFormatter.string(fromByteCount: combinedResult.bytesTransferred, countStyle: .binary))")

            return combinedResult
        }
    }

    // MARK: - Job Dependencies

    /// Check if all dependencies are satisfied before running job
    func checkDependencies(for job: SyncJob, allJobs: [SyncJob]) -> DependencyCheckResult {
        guard !job.dependencies.isEmpty else {
            return .satisfied
        }

        var unsatisfiedDependencies: [String] = []

        for depId in job.dependencies {
            guard let depJob = allJobs.first(where: { $0.id == depId }) else {
                unsatisfiedDependencies.append("Missing job: \(depId)")
                continue
            }

            // Check if dependency has run successfully
            if depJob.lastStatus != .success {
                unsatisfiedDependencies.append("\(depJob.name): Not run successfully (status: \(depJob.lastStatus?.rawValue ?? "never run"))")
            }
        }

        if unsatisfiedDependencies.isEmpty {
            return .satisfied
        } else {
            return .unsatisfied(reasons: unsatisfiedDependencies)
        }
    }

    /// Execute job with dependency checking
    func executeWithDependencies(job: SyncJob, allJobs: [SyncJob], dryRun: Bool = false) async throws -> ExecutionResult {
        // Check dependencies first
        let depCheck = checkDependencies(for: job, allJobs: allJobs)

        switch depCheck {
        case .satisfied:
            print("[Dependencies] All dependencies satisfied for '\(job.name)'")
        case .unsatisfied(let reasons):
            print("[Dependencies] Unsatisfied dependencies for '\(job.name)':")
            for reason in reasons {
                print("  - \(reason)")
            }
            throw DependencyError.unsatisfiedDependencies(reasons)
        }

        // Execute the job
        return try await executeWithAllFeatures(job: job, allJobs: allJobs, dryRun: dryRun)
    }

    // MARK: - Conditional Execution

    /// Check if source has changed since last run
    func hasSourceChanged(for job: SyncJob) async -> Bool {
        guard job.runOnlyIfChanged else {
            return true // Always run if conditional execution is disabled
        }

        print("[Conditional] Checking if source has changed: \(job.source)")

        do {
            let currentChecksum = try await calculateDirectoryChecksum(path: job.source)

            if let lastChecksum = job.lastSourceChecksum {
                let hasChanged = currentChecksum != lastChecksum
                print("[Conditional] Source \(hasChanged ? "HAS CHANGED" : "unchanged")")
                return hasChanged
            } else {
                print("[Conditional] No previous checksum, will run")
                return true // First run, always execute
            }
        } catch {
            print("[Conditional] Error calculating checksum: \(error), will run anyway")
            return true // On error, run anyway
        }
    }

    /// Update source checksum after successful run
    func updateSourceChecksum(for job: inout SyncJob) async {
        do {
            let checksum = try await calculateDirectoryChecksum(path: job.source)
            job.lastSourceChecksum = checksum
            print("[Conditional] Updated source checksum for '\(job.name)'")
        } catch {
            print("[Conditional] Failed to update checksum: \(error)")
        }
    }

    // MARK: - Delta Reporting

    /// Generate delta report from rsync output
    func generateDeltaReport(from output: String, jobId: UUID) -> DeltaReport {
        var report = DeltaReport(jobId: jobId)

        let lines = output.components(separatedBy: .newlines)

        for line in lines {
            // Parse rsync itemize output (-i flag)
            // Format: >f+++++++++ path/to/file
            // >f = sending file, + = new file, c = changed, * = deleted

            if line.hasPrefix(">f+++") {
                // New file
                let filename = String(line.dropFirst(11).trimmingCharacters(in: .whitespaces))
                report.filesAdded.append(filename)
            } else if line.hasPrefix(">f.st") || line.hasPrefix(">f..t") {
                // Modified file (size or time changed)
                let filename = String(line.dropFirst(11).trimmingCharacters(in: .whitespaces))
                report.filesModified.append(filename)
            } else if line.hasPrefix("*deleting") {
                // Deleted file
                let filename = String(line.dropFirst(9).trimmingCharacters(in: .whitespaces))
                report.filesDeleted.append(filename)
            }

            // Parse file sizes from verbose output
            if line.contains("bytes") && line.contains("sent") {
                // Example: "sent 123,456 bytes  received 789 bytes  234.56 bytes/sec"
                if let sentRange = line.range(of: "sent "),
                   let bytesRange = line.range(of: " bytes", range: sentRange.upperBound..<line.endIndex) {
                    let bytesString = String(line[sentRange.upperBound..<bytesRange.lowerBound])
                    if let bytes = Int64(bytesString.replacingOccurrences(of: ",", with: "")) {
                        report.bytesAdded += bytes
                    }
                }
            }
        }

        print("[Delta] Report: \(report.summary)")
        return report
    }

    // MARK: - Combined Execution

    /// Execute job with all advanced features
    func executeWithAllFeatures(job: SyncJob, allJobs: [SyncJob], dryRun: Bool = false) async throws -> ExecutionResult {
        // 1. Check if source changed (conditional execution)
        if job.runOnlyIfChanged {
            let hasChanged = await hasSourceChanged(for: job)
            if !hasChanged {
                print("[Conditional] Source unchanged, skipping sync for '\(job.name)'")
                return ExecutionResult(
                    id: UUID(),
                    jobId: job.id,
                    startTime: Date(),
                    endTime: Date(),
                    status: .success,
                    filesTransferred: 0,
                    bytesTransferred: 0,
                    errors: [],
                    output: "Skipped: Source unchanged"
                )
            }
        }

        // 2. Execute with parallelism if enabled
        var result: ExecutionResult
        if job.parallelism?.isEnabled == true {
            result = try await executeParallel(job: job, dryRun: dryRun)
        } else {
            result = try await RsyncExecutor().execute(job: job, dryRun: dryRun)
        }

        // 3. Generate delta report if itemize is enabled
        if job.options.itemize {
            let deltaReport = generateDeltaReport(from: result.output, jobId: job.id)
            var mutableJob = job
            mutableJob.lastDeltaReport = deltaReport
            // Update job in JobManager would happen in caller
        }

        // 4. Update source checksum if conditional execution is enabled
        if job.runOnlyIfChanged && result.status == .success {
            var mutableJob = job
            await updateSourceChecksum(for: &mutableJob)
            // Update job in JobManager would happen in caller
        }

        return result
    }

    // MARK: - Helper Methods

    /// Analyze source directory and list all files
    private func analyzeSourceDirectory(path: String) async throws -> [String] {
        let expandedPath = path.replacingOccurrences(of: "~", with: FileManager.default.homeDirectoryForCurrentUser.path)
        let url = URL(fileURLWithPath: expandedPath)

        var files: [String] = []

        if let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.isRegularFileKey]) {
            for case let fileURL as URL in enumerator {
                if let isRegularFile = try? fileURL.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile,
                   isRegularFile {
                    let relativePath = fileURL.path.replacingOccurrences(of: url.path + "/", with: "")
                    files.append(relativePath)
                }
            }
        }

        return files
    }

    /// Split files across threads based on strategy
    private func splitFilesForParallel(files: [String], threadCount: Int, strategy: ParallelStrategy) -> [[String]] {
        guard !files.isEmpty && threadCount > 1 else {
            return [files]
        }

        switch strategy {
        case .automatic, .byCount:
            // Split by file count (round-robin or chunks)
            let chunkSize = max(1, files.count / threadCount)
            var batches: [[String]] = []

            for i in 0..<threadCount {
                let start = i * chunkSize
                let end = (i == threadCount - 1) ? files.count : min(start + chunkSize, files.count)
                if start < files.count {
                    batches.append(Array(files[start..<end]))
                }
            }

            return batches

        case .byDirectory:
            // Group files by top-level directory
            var dirGroups: [String: [String]] = [:]

            for file in files {
                let components = file.components(separatedBy: "/")
                let topDir = components.first ?? "root"
                dirGroups[topDir, default: []].append(file)
            }

            // Distribute directories across threads
            var batches: [[String]] = Array(repeating: [], count: threadCount)
            var currentThread = 0

            for (_, dirFiles) in dirGroups.sorted(by: { $0.value.count > $1.value.count }) {
                batches[currentThread].append(contentsOf: dirFiles)
                currentThread = (currentThread + 1) % threadCount
            }

            return batches.filter { !$0.isEmpty }

        case .bySize:
            // Would need file sizes - for now, fall back to byCount
            return splitFilesForParallel(files: files, threadCount: threadCount, strategy: .byCount)
        }
    }

    /// Calculate directory checksum (fast hash of file list + mtimes)
    private func calculateDirectoryChecksum(path: String) async throws -> String {
        let expandedPath = path.replacingOccurrences(of: "~", with: FileManager.default.homeDirectoryForCurrentUser.path)
        let url = URL(fileURLWithPath: expandedPath)

        var checksumData = Data()

        if let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey]) {
            var fileInfos: [(path: String, mtime: Date, size: Int64)] = []

            for case let fileURL as URL in enumerator {
                if let resourceValues = try? fileURL.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey]),
                   let mtime = resourceValues.contentModificationDate,
                   let size = resourceValues.fileSize {

                    let relativePath = fileURL.path.replacingOccurrences(of: url.path + "/", with: "")
                    fileInfos.append((relativePath, mtime, Int64(size)))
                }
            }

            // Sort for consistency
            fileInfos.sort { $0.path < $1.path }

            // Hash the file list
            for info in fileInfos {
                checksumData.append(info.path.data(using: .utf8)!)
                checksumData.append(String(info.mtime.timeIntervalSince1970).data(using: .utf8)!)
                checksumData.append(String(info.size).data(using: .utf8)!)
            }
        }

        let hash = SHA256.hash(data: checksumData)
        return hash.compactMap { String(format: "%02x", $0) }.joined()
    }
}

// MARK: - Supporting Types

enum DependencyCheckResult {
    case satisfied
    case unsatisfied(reasons: [String])
}

enum DependencyError: LocalizedError {
    case unsatisfiedDependencies([String])

    var errorDescription: String? {
        switch self {
        case .unsatisfiedDependencies(let reasons):
            return "Cannot run job - dependencies not satisfied:\n" + reasons.joined(separator: "\n")
        }
    }
}
