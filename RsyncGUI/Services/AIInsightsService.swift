//
//  AIInsightsService.swift
//  RsyncGUI
//
//  AI-powered insights for backup and sync operations
//  Created by Jordan Koch on 2026-02-02.
//

import Foundation
import Combine
import NaturalLanguage

/// Main AI service for all intelligent features
@MainActor
class AIInsightsService: ObservableObject {
    static let shared = AIInsightsService()

    @Published var healthScore: BackupHealthScore?
    @Published var anomalies: [AnomalyAlert] = []
    @Published var suggestions: [AISuggestion] = []
    @Published var isAnalyzing = false

    private var changeHistory: [ChangeRecord] = []
    private var storageHistory: [StorageSnapshot] = []

    private init() {}

    // MARK: - 1. Smart Error Diagnosis

    func diagnoseError(_ error: String, output: String) -> ErrorDiagnosis {
        var diagnosis = ErrorDiagnosis(originalError: error)

        // Permission denied
        if error.contains("Permission denied") || output.contains("permission denied") {
            let pathMatch = output.range(of: #"(?:Permission denied|permission denied)[:\s]+([^\n]+)"#, options: .regularExpression)
            let path = pathMatch.map { String(output[$0]).components(separatedBy: ":").last?.trimmingCharacters(in: .whitespaces) } ?? nil

            diagnosis.explanation = "The sync cannot access one or more files due to permission restrictions."
            diagnosis.suggestions = [
                "Check file ownership: ls -la \(path ?? "<path>")",
                "Grant read permission: chmod +r \(path ?? "<path>")",
                "For directories, use: chmod +rx \(path ?? "<path>")",
                "If system files, try running with sudo (not recommended for regular backups)"
            ]
            diagnosis.severity = .medium
            diagnosis.category = .permission
        }
        // Disk full
        else if error.contains("No space left") || output.contains("No space left on device") {
            diagnosis.explanation = "The destination drive has run out of storage space."
            diagnosis.suggestions = [
                "Check available space: df -h",
                "Delete old backups or unused files from destination",
                "Use --delete flag to remove extraneous files",
                "Consider excluding large unnecessary files"
            ]
            diagnosis.severity = .high
            diagnosis.category = .storage
        }
        // Connection refused/timeout
        else if error.contains("Connection refused") || error.contains("Connection timed out") || output.contains("ssh: connect") {
            diagnosis.explanation = "Cannot connect to the remote server. The server may be offline or blocking connections."
            diagnosis.suggestions = [
                "Verify server is online: ping <hostname>",
                "Check SSH service is running on remote host",
                "Verify firewall allows SSH (port 22)",
                "Test SSH manually: ssh user@host",
                "Check VPN connection if required"
            ]
            diagnosis.severity = .high
            diagnosis.category = .connection
        }
        // Host key verification
        else if output.contains("Host key verification failed") {
            diagnosis.explanation = "The remote server's identity has changed since last connection. This could indicate a security issue or server reinstallation."
            diagnosis.suggestions = [
                "If server was reinstalled, remove old key: ssh-keygen -R <hostname>",
                "Verify you're connecting to the correct server",
                "Check for man-in-the-middle attacks if unexpected"
            ]
            diagnosis.severity = .high
            diagnosis.category = .security
        }
        // File vanished
        else if output.contains("file has vanished") {
            diagnosis.explanation = "Some files were deleted or moved during the sync operation. This is usually harmless."
            diagnosis.suggestions = [
                "This is normal for active directories",
                "Use --ignore-missing-args to suppress warnings",
                "Consider syncing during low-activity periods"
            ]
            diagnosis.severity = .low
            diagnosis.category = .transient
        }
        // Invalid argument
        else if error.contains("Invalid argument") || output.contains("invalid argument") {
            diagnosis.explanation = "One of the rsync options or paths is incorrect."
            diagnosis.suggestions = [
                "Check source and destination paths exist",
                "Verify no special characters in paths",
                "Review rsync options for typos",
                "Try running with -v for more details"
            ]
            diagnosis.severity = .medium
            diagnosis.category = .configuration
        }
        // Partial transfer
        else if output.contains("rsync error: some files") || error.contains("partial transfer") {
            diagnosis.explanation = "Some files could not be transferred. The sync partially completed."
            diagnosis.suggestions = [
                "Check the output for specific failed files",
                "Verify source files are not locked by other applications",
                "Try running sync again for remaining files",
                "Use --partial to resume interrupted transfers"
            ]
            diagnosis.severity = .medium
            diagnosis.category = .partial
        }
        // Generic/unknown
        else {
            diagnosis.explanation = "An error occurred during synchronization."
            diagnosis.suggestions = [
                "Run with -v or -vv for more detailed output",
                "Check source and destination are accessible",
                "Verify network connectivity",
                "Review rsync man page for error codes"
            ]
            diagnosis.severity = .medium
            diagnosis.category = .unknown
        }

        return diagnosis
    }

    // MARK: - 2. Change Summary

    func generateChangeSummary(from output: String, job: SyncJob) -> ChangeSummary {
        var summary = ChangeSummary(jobName: job.name)

        // Parse itemized changes
        let lines = output.components(separatedBy: .newlines)

        var addedFiles: [FileChange] = []
        var modifiedFiles: [FileChange] = []
        var deletedFiles: [FileChange] = []

        for line in lines {
            // Itemize format: >f+++++++++ filename (new file)
            // >f.st...... filename (modified)
            // *deleting filename (deleted)

            if line.hasPrefix(">f+++") || line.hasPrefix(">d+++") {
                let filename = extractFilename(from: line)
                addedFiles.append(FileChange(path: filename, type: classifyFile(filename)))
            } else if line.hasPrefix(">f") && line.contains(".") {
                let filename = extractFilename(from: line)
                modifiedFiles.append(FileChange(path: filename, type: classifyFile(filename)))
            } else if line.hasPrefix("*deleting") {
                let filename = line.replacingOccurrences(of: "*deleting ", with: "").trimmingCharacters(in: .whitespaces)
                deletedFiles.append(FileChange(path: filename, type: classifyFile(filename)))
            }
        }

        summary.addedFiles = addedFiles
        summary.modifiedFiles = modifiedFiles
        summary.deletedFiles = deletedFiles

        // Generate human-readable summary
        summary.humanSummary = generateHumanReadableSummary(added: addedFiles, modified: modifiedFiles, deleted: deletedFiles)

        // Highlight important changes
        summary.highlights = identifyHighlights(added: addedFiles, modified: modifiedFiles, deleted: deletedFiles)

        return summary
    }

    private func extractFilename(from line: String) -> String {
        // Remove rsync itemize prefix (first 12 characters typically)
        let components = line.components(separatedBy: " ")
        return components.dropFirst().joined(separator: " ").trimmingCharacters(in: .whitespaces)
    }

    private func classifyFile(_ path: String) -> FileType {
        let ext = (path as NSString).pathExtension.lowercased()

        switch ext {
        case "jpg", "jpeg", "png", "gif", "heic", "raw", "tiff":
            return .photo
        case "mp4", "mov", "avi", "mkv", "m4v":
            return .video
        case "mp3", "wav", "aac", "flac", "m4a":
            return .audio
        case "doc", "docx", "pdf", "txt", "rtf", "md":
            return .document
        case "xls", "xlsx", "csv", "numbers":
            return .spreadsheet
        case "ppt", "pptx", "key":
            return .presentation
        case "zip", "tar", "gz", "rar", "7z":
            return .archive
        case "swift", "py", "js", "ts", "java", "cpp", "h", "m":
            return .code
        case "dmg", "pkg", "app":
            return .application
        default:
            if path.hasSuffix("/") {
                return .folder
            }
            return .other
        }
    }

    private func generateHumanReadableSummary(added: [FileChange], modified: [FileChange], deleted: [FileChange]) -> String {
        var parts: [String] = []

        // Group by type
        let addedByType = Dictionary(grouping: added, by: { $0.type })
        let modifiedByType = Dictionary(grouping: modified, by: { $0.type })
        let deletedByType = Dictionary(grouping: deleted, by: { $0.type })

        // Added files summary
        for (type, files) in addedByType.sorted(by: { $0.value.count > $1.value.count }) {
            if files.count > 0 {
                parts.append("Added \(files.count) \(type.pluralName(files.count))")
            }
        }

        // Modified files summary
        for (type, files) in modifiedByType.sorted(by: { $0.value.count > $1.value.count }) {
            if files.count > 0 {
                parts.append("Updated \(files.count) \(type.pluralName(files.count))")
            }
        }

        // Deleted files summary
        let totalDeleted = deleted.count
        if totalDeleted > 0 {
            parts.append("Removed \(totalDeleted) file\(totalDeleted == 1 ? "" : "s")")
        }

        if parts.isEmpty {
            return "No changes detected"
        }

        return parts.joined(separator: ", ")
    }

    private func identifyHighlights(added: [FileChange], modified: [FileChange], deleted: [FileChange]) -> [String] {
        var highlights: [String] = []

        // Large number of photos (vacation?)
        let photoCount = added.filter { $0.type == .photo }.count
        if photoCount > 20 {
            highlights.append("📸 \(photoCount) new photos added - looks like a photo session!")
        }

        // Important document types
        let docCount = added.filter { $0.type == .document || $0.type == .spreadsheet }.count
        if docCount > 5 {
            highlights.append("📄 \(docCount) new documents backed up")
        }

        // Large deletions (potential concern)
        if deleted.count > 50 {
            highlights.append("⚠️ \(deleted.count) files removed - verify this was intentional")
        }

        // Code changes
        let codeCount = modified.filter { $0.type == .code }.count + added.filter { $0.type == .code }.count
        if codeCount > 10 {
            highlights.append("💻 \(codeCount) code files changed")
        }

        return highlights
    }

    // MARK: - 3. Anomaly Detection

    func detectAnomalies(in output: String, job: SyncJob, previousRuns: [ExecutionResult]) -> [AnomalyAlert] {
        var alerts: [AnomalyAlert] = []

        let lines = output.components(separatedBy: .newlines)
        var deletedCount = 0
        var addedCount = 0
        var encryptedExtensions = 0
        var renamedCount = 0

        // Suspicious extensions often used by ransomware
        let ransomwareExtensions = ["encrypted", "locked", "crypto", "crypt", "enc", "pay", "ransom", "wcry", "wncry", "locky", "cerber"]

        for line in lines {
            if line.hasPrefix("*deleting") {
                deletedCount += 1
            } else if line.hasPrefix(">f+++") || line.hasPrefix(">d+++") {
                addedCount += 1

                // Check for ransomware-like extensions
                for ext in ransomwareExtensions {
                    if line.lowercased().contains(".\(ext)") {
                        encryptedExtensions += 1
                    }
                }
            }
        }

        // Calculate averages from history
        let avgDeleted = previousRuns.isEmpty ? 10 : previousRuns.map { $0.filesTransferred }.reduce(0, +) / max(previousRuns.count, 1)

        // Mass deletion alert
        if deletedCount > 100 && deletedCount > avgDeleted * 5 {
            alerts.append(AnomalyAlert(
                type: .massDeletion,
                severity: .critical,
                title: "Unusual Mass Deletion Detected",
                message: "\(deletedCount) files are being deleted, which is \(deletedCount / max(avgDeleted, 1))x more than average.",
                recommendation: "Verify this is intentional before proceeding. This could indicate accidental deletion or malware.",
                filesAffected: deletedCount
            ))
        }

        // Ransomware detection
        if encryptedExtensions > 10 {
            alerts.append(AnomalyAlert(
                type: .ransomware,
                severity: .critical,
                title: "⚠️ Potential Ransomware Activity",
                message: "Detected \(encryptedExtensions) files with suspicious encrypted extensions.",
                recommendation: "STOP THE SYNC IMMEDIATELY. Do not sync these files to your backup. Investigate the source for malware.",
                filesAffected: encryptedExtensions
            ))
        }

        // Unusual file growth
        if addedCount > 10000 {
            alerts.append(AnomalyAlert(
                type: .unusualGrowth,
                severity: .warning,
                title: "Large Number of New Files",
                message: "\(addedCount) new files detected. This is unusually high.",
                recommendation: "Verify the source hasn't been compromised or contains unwanted files.",
                filesAffected: addedCount
            ))
        }

        return alerts
    }

    // MARK: - 4. Smart Scheduling

    func analyzeOptimalSchedule(for job: SyncJob, history: [ExecutionResult]) -> ScheduleRecommendation {
        // Analyze when files typically change
        var hourlyChanges: [Int: Int] = [:]
        var dailyChanges: [Int: Int] = [:] // 0 = Sunday

        for result in history {
            let hour = Calendar.current.component(.hour, from: result.startTime)
            let day = Calendar.current.component(.weekday, from: result.startTime) - 1

            hourlyChanges[hour, default: 0] += result.filesTransferred
            dailyChanges[day, default: 0] += result.filesTransferred
        }

        // Find peak activity hours
        let peakHour = hourlyChanges.max(by: { $0.value < $1.value })?.key ?? 12
        let peakDay = dailyChanges.max(by: { $0.value < $1.value })?.key ?? 1

        // Recommend backing up after peak activity
        let recommendedHour = (peakHour + 2) % 24 // 2 hours after peak
        let recommendedMinute = 0

        let dayNames = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]
        let peakDayName = dayNames[peakDay]

        var recommendation = ScheduleRecommendation(
            frequency: .daily,
            recommendedHour: recommendedHour,
            recommendedMinute: recommendedMinute,
            confidence: 0.0,
            explanation: ""
        )

        // Determine confidence based on data
        if history.count >= 14 {
            recommendation.confidence = 0.85
            recommendation.explanation = "Based on \(history.count) sync runs, your files change most during \(peakDayName)s around \(peakHour):00. Recommended: Daily backup at \(recommendedHour):00 to capture all changes."
        } else if history.count >= 7 {
            recommendation.confidence = 0.65
            recommendation.explanation = "Based on limited history, suggest daily backup at \(recommendedHour):00. Run more syncs for better recommendations."
        } else {
            recommendation.confidence = 0.4
            recommendation.explanation = "Not enough sync history for accurate analysis. Default recommendation: Daily backup at 18:00 (after typical work hours)."
            recommendation.recommendedHour = 18
        }

        return recommendation
    }

    // MARK: - 5. Storage Prediction

    func predictStorageNeeds(for destinations: [SyncDestination], history: [StorageSnapshot]) -> StoragePrediction {
        guard let latestSnapshot = history.last else {
            return StoragePrediction(
                daysUntilFull: nil,
                growthRatePerDay: 0,
                recommendation: "No storage history available. Run a few syncs to enable predictions.",
                projectedFullDate: nil
            )
        }

        // Calculate growth rate
        var totalGrowthBytes: Int64 = 0
        var daysCovered = 0

        if history.count >= 2 {
            let oldestSnapshot = history.first!
            totalGrowthBytes = latestSnapshot.usedBytes - oldestSnapshot.usedBytes
            daysCovered = Calendar.current.dateComponents([.day], from: oldestSnapshot.date, to: latestSnapshot.date).day ?? 1
        }

        let growthPerDay = daysCovered > 0 ? totalGrowthBytes / Int64(daysCovered) : 0
        let availableBytes = latestSnapshot.totalBytes - latestSnapshot.usedBytes
        let daysUntilFull = growthPerDay > 0 ? Int(availableBytes / growthPerDay) : nil

        var recommendation = ""
        var projectedDate: Date? = nil

        if let days = daysUntilFull {
            projectedDate = Calendar.current.date(byAdding: .day, value: days, to: Date())

            if days < 7 {
                recommendation = "⚠️ CRITICAL: Storage will be full in \(days) days! Free up space immediately or add more storage."
            } else if days < 30 {
                recommendation = "Storage running low. Consider cleaning up old files or expanding storage within the next month."
            } else if days < 90 {
                recommendation = "Storage is adequate for the next \(days) days at current growth rate."
            } else {
                recommendation = "Storage is healthy. No action needed."
            }
        } else {
            recommendation = "Unable to calculate - storage may not be growing or data is insufficient."
        }

        return StoragePrediction(
            daysUntilFull: daysUntilFull,
            growthRatePerDay: growthPerDay,
            recommendation: recommendation,
            projectedFullDate: projectedDate
        )
    }

    // MARK: - 6. Intelligent Exclusions

    func suggestExclusions(for sourcePath: String) async -> [ExclusionSuggestion] {
        var suggestions: [ExclusionSuggestion] = []

        let excludePatterns: [(pattern: String, description: String, reason: String, typicalSize: String)] = [
            ("node_modules/", "Node.js dependencies", "Easily regenerated with npm install", "100MB - 2GB"),
            (".git/", "Git repository data", "Only needed for version control, not backups", "10MB - 1GB"),
            ("DerivedData/", "Xcode build cache", "Regenerated on build", "1GB - 50GB"),
            (".build/", "Swift build folder", "Regenerated on build", "100MB - 5GB"),
            ("Pods/", "CocoaPods dependencies", "Regenerated with pod install", "100MB - 1GB"),
            ("*.xcarchive", "Xcode archives", "Can be very large, keep only if needed", "100MB - 2GB each"),
            ("__pycache__/", "Python bytecode cache", "Regenerated automatically", "1MB - 100MB"),
            (".venv/", "Python virtual environment", "Recreate with pip install", "100MB - 1GB"),
            ("target/", "Rust/Java build output", "Regenerated on build", "100MB - 5GB"),
            ("*.log", "Log files", "Usually not needed for backup", "1MB - 1GB"),
            (".DS_Store", "macOS folder metadata", "System generated, not needed", "< 1MB"),
            ("*.tmp", "Temporary files", "Not needed for backup", "varies"),
            ("Caches/", "Application caches", "Regenerated by applications", "1GB - 20GB"),
            ("*.dSYM", "Debug symbols", "Only needed for crash analysis", "10MB - 500MB each"),
        ]

        // Check which patterns exist in source
        let fileManager = FileManager.default
        let expandedPath = sourcePath.replacingOccurrences(of: "~", with: fileManager.homeDirectoryForCurrentUser.path)

        for (pattern, description, reason, size) in excludePatterns {
            // Simple check - see if pattern might exist
            let checkPath = pattern.replacingOccurrences(of: "*", with: "").replacingOccurrences(of: "/", with: "")

            if let enumerator = fileManager.enumerator(atPath: expandedPath) {
                var found = false
                var foundPath = ""
                var estimatedSize: Int64 = 0

                while let file = enumerator.nextObject() as? String {
                    if file.contains(checkPath) {
                        found = true
                        foundPath = file
                        // Get size estimate
                        let fullPath = (expandedPath as NSString).appendingPathComponent(file)
                        if let attrs = try? fileManager.attributesOfItem(atPath: fullPath) {
                            estimatedSize += (attrs[.size] as? Int64) ?? 0
                        }
                        break // Found at least one match
                    }
                }

                if found {
                    suggestions.append(ExclusionSuggestion(
                        pattern: pattern,
                        description: description,
                        reason: reason,
                        estimatedSize: estimatedSize > 0 ? ByteCountFormatter.string(fromByteCount: estimatedSize, countStyle: .file) : size,
                        foundAt: foundPath,
                        priority: estimatedSize > 100_000_000 ? .high : .medium // High priority if > 100MB
                    ))
                }
            }
        }

        return suggestions.sorted { $0.priority.rawValue > $1.priority.rawValue }
    }

    // MARK: - 7. Natural Language Job Creation

    func parseNaturalLanguageJob(_ input: String) -> ParsedJobIntent? {
        let lowercased = input.lowercased()

        var intent = ParsedJobIntent()

        // Detect action (backup, sync, copy)
        if lowercased.contains("backup") {
            intent.action = .backup
        } else if lowercased.contains("sync") {
            intent.action = .sync
        } else if lowercased.contains("copy") || lowercased.contains("mirror") {
            intent.action = .copy
        } else {
            intent.action = .backup // Default
        }

        // Detect source folders
        let sourcePatterns = [
            ("documents", "~/Documents"),
            ("photos", "~/Pictures"),
            ("pictures", "~/Pictures"),
            ("desktop", "~/Desktop"),
            ("downloads", "~/Downloads"),
            ("music", "~/Music"),
            ("movies", "~/Movies"),
            ("home", "~"),
            ("projects", "~/Projects"),
            ("code", "~/Code"),
        ]

        for (keyword, path) in sourcePatterns {
            if lowercased.contains(keyword) {
                intent.sourcePath = path
                break
            }
        }

        // Detect destination
        if lowercased.contains("icloud") {
            intent.destinationType = .iCloudDrive
            intent.destinationPath = SyncJob.iCloudDrivePath
        } else if lowercased.contains("nas") || lowercased.contains("network") {
            intent.destinationType = .local
            intent.destinationPath = "/Volumes/" // User will need to specify
        } else if lowercased.contains("external") || lowercased.contains("drive") {
            intent.destinationType = .local
            intent.destinationPath = "/Volumes/" // User will need to specify
        } else if lowercased.contains("server") || lowercased.contains("remote") || lowercased.contains("ssh") {
            intent.destinationType = .remoteSSH
        }

        // Detect schedule
        if lowercased.contains("every day") || lowercased.contains("daily") {
            intent.frequency = .daily
        } else if lowercased.contains("every hour") || lowercased.contains("hourly") {
            intent.frequency = .hourly
        } else if lowercased.contains("every week") || lowercased.contains("weekly") {
            intent.frequency = .weekly
        } else if lowercased.contains("every month") || lowercased.contains("monthly") {
            intent.frequency = .monthly
        } else if lowercased.contains("sunday") {
            intent.frequency = .weekly
            intent.dayOfWeek = 0
        } else if lowercased.contains("monday") {
            intent.frequency = .weekly
            intent.dayOfWeek = 1
        } else if lowercased.contains("friday") {
            intent.frequency = .weekly
            intent.dayOfWeek = 5
        }

        // Detect time
        let timePattern = #"at (\d{1,2})(?::(\d{2}))?\s*(am|pm)?"#
        if let regex = try? NSRegularExpression(pattern: timePattern, options: .caseInsensitive),
           let match = regex.firstMatch(in: input, options: [], range: NSRange(input.startIndex..., in: input)) {
            if let hourRange = Range(match.range(at: 1), in: input) {
                var hour = Int(input[hourRange]) ?? 12
                if let ampmRange = Range(match.range(at: 3), in: input) {
                    let ampm = String(input[ampmRange]).lowercased()
                    if ampm == "pm" && hour < 12 { hour += 12 }
                    if ampm == "am" && hour == 12 { hour = 0 }
                }
                intent.hour = hour
            }
        }

        // Generate suggested name
        let sourceName = intent.sourcePath?.components(separatedBy: "/").last ?? "Files"
        let destName = intent.destinationType == .iCloudDrive ? "iCloud" : "Backup"
        intent.suggestedName = "\(sourceName) to \(destName)"

        return intent
    }

    // MARK: - 8. Backup Health Score

    func calculateHealthScore(jobs: [SyncJob], history: [ExecutionResult]) -> BackupHealthScore {
        var score = BackupHealthScore()

        // Factor 1: Coverage (are important folders backed up?)
        let importantFolders = ["Documents", "Desktop", "Pictures", "Projects"]
        var coveredFolders = 0
        for folder in importantFolders {
            if jobs.contains(where: { $0.sources.contains(where: { $0.contains(folder) }) }) {
                coveredFolders += 1
            }
        }
        score.coverageScore = Double(coveredFolders) / Double(importantFolders.count) * 100

        // Factor 2: Frequency (when was last backup?)
        let recentRuns = history.filter { $0.status == .success }
        if let lastRun = recentRuns.max(by: { $0.startTime < $1.startTime }) {
            let daysSinceLastBackup = Calendar.current.dateComponents([.day], from: lastRun.startTime, to: Date()).day ?? 0
            if daysSinceLastBackup <= 1 {
                score.frequencyScore = 100
            } else if daysSinceLastBackup <= 7 {
                score.frequencyScore = 80
            } else if daysSinceLastBackup <= 14 {
                score.frequencyScore = 50
            } else {
                score.frequencyScore = 20
            }
            score.daysSinceLastBackup = daysSinceLastBackup
        } else {
            score.frequencyScore = 0
            score.daysSinceLastBackup = nil
        }

        // Factor 3: Redundancy (multiple destinations?)
        let totalDestinations = jobs.flatMap { $0.destinations }.filter { $0.isEnabled }.count
        let uniqueTypes = Set(jobs.flatMap { $0.destinations }.map { $0.type }).count
        if totalDestinations >= 3 && uniqueTypes >= 2 {
            score.redundancyScore = 100
        } else if totalDestinations >= 2 {
            score.redundancyScore = 70
        } else if totalDestinations >= 1 {
            score.redundancyScore = 40
        } else {
            score.redundancyScore = 0
        }

        // Factor 4: Success rate
        let recentHistory = history.suffix(20)
        let successCount = recentHistory.filter { $0.status == .success }.count
        score.successRate = recentHistory.isEmpty ? 100 : Double(successCount) / Double(recentHistory.count) * 100

        // Factor 5: Verification enabled?
        score.verificationEnabled = jobs.contains { $0.verifyAfterSync }

        // Calculate overall score (weighted average)
        let weights = [0.25, 0.30, 0.20, 0.20, 0.05] // Coverage, Frequency, Redundancy, Success, Verification
        let scores = [score.coverageScore, score.frequencyScore, score.redundancyScore, score.successRate, score.verificationEnabled ? 100.0 : 0.0]
        score.overallScore = zip(weights, scores).map { $0 * $1 }.reduce(0, +)

        // Assign grade
        switch score.overallScore {
        case 90...100: score.grade = "A"
        case 80..<90: score.grade = "B"
        case 70..<80: score.grade = "C"
        case 60..<70: score.grade = "D"
        default: score.grade = "F"
        }

        // Generate recommendations
        score.recommendations = generateHealthRecommendations(score: score, jobs: jobs)

        return score
    }

    private func generateHealthRecommendations(score: BackupHealthScore, jobs: [SyncJob]) -> [String] {
        var recommendations: [String] = []

        if score.coverageScore < 75 {
            recommendations.append("Consider backing up more important folders (Documents, Desktop, Pictures)")
        }

        if let days = score.daysSinceLastBackup, days > 7 {
            recommendations.append("Your last backup was \(days) days ago - consider running a backup soon")
        }

        if score.redundancyScore < 70 {
            recommendations.append("Add more backup destinations for better redundancy (3-2-1 rule: 3 copies, 2 media types, 1 offsite)")
        }

        if score.successRate < 90 {
            recommendations.append("Some recent backups failed - check error logs and fix issues")
        }

        if !score.verificationEnabled {
            recommendations.append("Enable verification on at least one job to ensure backup integrity")
        }

        if recommendations.isEmpty {
            recommendations.append("Your backup strategy looks great! Keep it up.")
        }

        return recommendations
    }

    // MARK: - 9. Recovery Assistant

    func searchBackups(query: String, in history: [ExecutionResult]) -> [RecoverySearchResult] {
        var results: [RecoverySearchResult] = []

        let queryLower = query.lowercased()

        for result in history {
            let lines = result.output.components(separatedBy: .newlines)
            for line in lines {
                if line.lowercased().contains(queryLower) {
                    // Extract filename from rsync output
                    let filename = extractFilename(from: line)
                    if !filename.isEmpty {
                        results.append(RecoverySearchResult(
                            filename: filename,
                            syncDate: result.startTime,
                            jobId: result.jobId,
                            relevanceScore: calculateRelevance(query: queryLower, filename: filename)
                        ))
                    }
                }
            }
        }

        // Sort by relevance and date
        return results.sorted { $0.relevanceScore > $1.relevanceScore }.prefix(50).map { $0 }
    }

    private func calculateRelevance(query: String, filename: String) -> Double {
        let filenameLower = filename.lowercased()

        // Exact match
        if filenameLower == query { return 1.0 }

        // Filename contains query
        if filenameLower.contains(query) { return 0.8 }

        // Query words in filename
        let queryWords = query.components(separatedBy: .whitespaces)
        let matchedWords = queryWords.filter { filenameLower.contains($0) }
        return Double(matchedWords.count) / Double(queryWords.count) * 0.6
    }

    // MARK: - 10. Sensitive File Detection

    func scanForSensitiveFiles(in sourcePath: String) async -> [SensitiveFileAlert] {
        var alerts: [SensitiveFileAlert] = []

        let sensitivePatterns: [(pattern: String, type: SensitiveFileType, risk: RiskLevel)] = [
            (".env", .environmentFile, .high),
            ("credentials", .credentials, .critical),
            ("password", .password, .critical),
            ("secret", .secret, .high),
            (".pem", .privateKey, .critical),
            ("id_rsa", .sshKey, .critical),
            ("id_ed25519", .sshKey, .critical),
            (".p12", .certificate, .high),
            (".pfx", .certificate, .high),
            ("api_key", .apiKey, .high),
            ("apikey", .apiKey, .high),
            ("aws_access", .awsCredentials, .critical),
            ("token", .token, .medium),
            (".keychain", .keychain, .critical),
            ("wallet.dat", .cryptoWallet, .critical),
        ]

        let fileManager = FileManager.default
        let expandedPath = sourcePath.replacingOccurrences(of: "~", with: fileManager.homeDirectoryForCurrentUser.path)

        guard let enumerator = fileManager.enumerator(atPath: expandedPath) else { return alerts }

        while let file = enumerator.nextObject() as? String {
            let fileLower = file.lowercased()

            for (pattern, type, risk) in sensitivePatterns {
                if fileLower.contains(pattern.lowercased()) {
                    alerts.append(SensitiveFileAlert(
                        path: file,
                        type: type,
                        risk: risk,
                        recommendation: generateSensitiveFileRecommendation(type: type)
                    ))
                    break // Only one alert per file
                }
            }
        }

        return alerts.sorted { $0.risk.rawValue > $1.risk.rawValue }
    }

    private func generateSensitiveFileRecommendation(type: SensitiveFileType) -> String {
        switch type {
        case .environmentFile:
            return "Exclude .env files or ensure they don't contain production secrets"
        case .credentials, .password:
            return "Never backup plaintext credentials. Use a password manager instead."
        case .privateKey, .sshKey:
            return "SSH keys should be excluded from backups. Regenerate if compromised."
        case .certificate:
            return "Certificates with private keys should be securely stored, not in regular backups."
        case .apiKey:
            return "API keys should be excluded. Rotate keys if exposed."
        case .awsCredentials:
            return "AWS credentials are highly sensitive. Exclude and use IAM roles instead."
        case .token:
            return "Tokens may be sensitive. Review if this file contains auth tokens."
        case .keychain:
            return "Keychain files contain all your passwords. Handle with extreme care."
        case .cryptoWallet:
            return "Cryptocurrency wallets should be backed up separately with encryption."
        case .secret:
            return "Review this file for sensitive content before backing up."
        }
    }
}

// MARK: - Data Models

struct ErrorDiagnosis {
    var originalError: String
    var explanation: String = ""
    var suggestions: [String] = []
    var severity: DiagnosisSeverity = .medium
    var category: ErrorCategory = .unknown

    enum DiagnosisSeverity { case low, medium, high, critical }
    enum ErrorCategory { case permission, storage, connection, security, transient, configuration, partial, unknown }
}

struct ChangeSummary {
    var jobName: String
    var addedFiles: [FileChange] = []
    var modifiedFiles: [FileChange] = []
    var deletedFiles: [FileChange] = []
    var humanSummary: String = ""
    var highlights: [String] = []
}

struct FileChange {
    var path: String
    var type: FileType
}

enum FileType: String {
    case photo, video, audio, document, spreadsheet, presentation, archive, code, application, folder, other

    func pluralName(_ count: Int) -> String {
        let base = self.rawValue
        if count == 1 { return base }
        switch self {
        case .photo: return "photos"
        case .video: return "videos"
        case .audio: return "audio files"
        case .document: return "documents"
        case .spreadsheet: return "spreadsheets"
        case .presentation: return "presentations"
        case .archive: return "archives"
        case .code: return "code files"
        case .application: return "applications"
        case .folder: return "folders"
        case .other: return "files"
        }
    }
}

struct AnomalyAlert: Identifiable {
    var id = UUID()
    var type: AnomalyType
    var severity: AnomalySeverity
    var title: String
    var message: String
    var recommendation: String
    var filesAffected: Int

    enum AnomalyType { case massDeletion, ransomware, unusualGrowth, connectionIssue }
    enum AnomalySeverity: Int { case info = 0, warning = 1, critical = 2 }
}

struct ScheduleRecommendation {
    var frequency: ScheduleFrequency
    var recommendedHour: Int
    var recommendedMinute: Int
    var confidence: Double
    var explanation: String
}

struct StorageSnapshot {
    var date: Date
    var totalBytes: Int64
    var usedBytes: Int64
    var destination: String
}

struct StoragePrediction {
    var daysUntilFull: Int?
    var growthRatePerDay: Int64
    var recommendation: String
    var projectedFullDate: Date?
}

struct ExclusionSuggestion: Identifiable {
    var id = UUID()
    var pattern: String
    var description: String
    var reason: String
    var estimatedSize: String
    var foundAt: String
    var priority: Priority

    enum Priority: Int { case low = 0, medium = 1, high = 2 }
}

struct ParsedJobIntent {
    var action: JobAction = .backup
    var sourcePath: String?
    var destinationPath: String?
    var destinationType: DestinationType = .local
    var frequency: ScheduleFrequency = .manual
    var dayOfWeek: Int?
    var hour: Int = 18
    var suggestedName: String = "New Backup Job"

    enum JobAction: String { case backup, sync, copy }
}

struct BackupHealthScore {
    var overallScore: Double = 0
    var grade: String = "F"
    var coverageScore: Double = 0
    var frequencyScore: Double = 0
    var redundancyScore: Double = 0
    var successRate: Double = 0
    var verificationEnabled: Bool = false
    var daysSinceLastBackup: Int?
    var recommendations: [String] = []
}

struct RecoverySearchResult: Identifiable {
    var id = UUID()
    var filename: String
    var syncDate: Date
    var jobId: UUID
    var relevanceScore: Double
}

struct SensitiveFileAlert: Identifiable {
    var id = UUID()
    var path: String
    var type: SensitiveFileType
    var risk: RiskLevel
    var recommendation: String
}

enum SensitiveFileType {
    case environmentFile, credentials, password, secret, privateKey, sshKey
    case certificate, apiKey, awsCredentials, token, keychain, cryptoWallet
}

enum RiskLevel: Int {
    case low = 0, medium = 1, high = 2, critical = 3
}

struct ChangeRecord {
    var date: Date
    var filesChanged: Int
    var bytesChanged: Int64
}

struct AISuggestion: Identifiable {
    var id = UUID()
    var type: SuggestionType
    var title: String
    var description: String
    var action: String?

    enum SuggestionType { case exclusion, schedule, storage, security, performance }
}
