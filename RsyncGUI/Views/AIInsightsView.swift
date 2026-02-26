//
//  AIInsightsView.swift
//  RsyncGUI
//
//  AI-powered insights dashboard
//  Created by Jordan Koch on 2026-02-02.
//

import SwiftUI

struct AIInsightsView: View {
    @EnvironmentObject var jobManager: JobManager
    @StateObject private var aiService = AIInsightsService.shared

    @State private var selectedTab: InsightTab = .health
    @State private var naturalLanguageInput = ""
    @State private var parsedIntent: ParsedJobIntent?
    @State private var searchQuery = ""
    @State private var searchResults: [RecoverySearchResult] = []
    @State private var exclusionSuggestions: [ExclusionSuggestion] = []
    @State private var sensitiveFiles: [SensitiveFileAlert] = []
    @State private var isScanning = false

    enum InsightTab: String, CaseIterable {
        case health = "Health Score"
        case create = "Create Job"
        case recovery = "Recovery"
        case security = "Security"
        case exclusions = "Exclusions"
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            header

            Divider()

            // Tab bar
            tabBar

            Divider()

            // Content
            ScrollView {
                tabContent
                    .padding(24)
            }
        }
        .frame(minWidth: 800, minHeight: 600)
        .onAppear {
            refreshHealthScore()
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Image(systemName: "brain.head.profile")
                .font(.title)
                .foregroundStyle(.purple.gradient)

            VStack(alignment: .leading, spacing: 4) {
                Text("AI Insights")
                    .font(.title2)
                    .fontWeight(.bold)

                Text("Intelligent backup analysis and recommendations")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            Spacer()
        }
        .padding()
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // MARK: - Tab Bar

    private var tabBar: some View {
        HStack(spacing: 0) {
            ForEach(InsightTab.allCases, id: \.self) { tab in
                Button(action: { selectedTab = tab }) {
                    HStack {
                        Image(systemName: tabIcon(for: tab))
                        Text(tab.rawValue)
                    }
                    .font(.headline)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .frame(maxWidth: .infinity)
                    .background(selectedTab == tab ? Color.purple.opacity(0.1) : Color.clear)
                    .foregroundColor(selectedTab == tab ? .purple : .secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private func tabIcon(for tab: InsightTab) -> String {
        switch tab {
        case .health: return "heart.text.square"
        case .create: return "text.bubble"
        case .recovery: return "magnifyingglass"
        case .security: return "lock.shield"
        case .exclusions: return "minus.circle"
        }
    }

    // MARK: - Tab Content

    @ViewBuilder
    private var tabContent: some View {
        switch selectedTab {
        case .health:
            healthScoreTab
        case .create:
            naturalLanguageTab
        case .recovery:
            recoveryTab
        case .security:
            securityTab
        case .exclusions:
            exclusionsTab
        }
    }

    // MARK: - Health Score Tab

    private var healthScoreTab: some View {
        VStack(spacing: 24) {
            if let health = aiService.healthScore {
                // Overall Grade
                HStack(spacing: 40) {
                    VStack {
                        Text(health.grade)
                            .font(.system(size: 80, weight: .bold, design: .rounded))
                            .foregroundColor(gradeColor(health.grade))

                        Text("Overall Grade")
                            .font(.headline)
                            .foregroundColor(.secondary)
                    }
                    .frame(width: 150)

                    VStack(alignment: .leading, spacing: 16) {
                        healthMetric(title: "Coverage", value: health.coverageScore, icon: "folder.fill")
                        healthMetric(title: "Frequency", value: health.frequencyScore, icon: "clock.fill")
                        healthMetric(title: "Redundancy", value: health.redundancyScore, icon: "square.stack.3d.up.fill")
                        healthMetric(title: "Success Rate", value: health.successRate, icon: "checkmark.circle.fill")
                    }
                }
                .padding()
                .background(Color.secondary.opacity(0.05))
                .cornerRadius(12)

                // Last Backup Info
                if let days = health.daysSinceLastBackup {
                    HStack {
                        Image(systemName: days <= 1 ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                            .foregroundColor(days <= 1 ? .green : (days <= 7 ? .orange : .red))

                        Text(days == 0 ? "Last backup was today" : "Last backup was \(days) day\(days == 1 ? "" : "s") ago")
                            .font(.headline)
                    }
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(days <= 1 ? Color.green.opacity(0.1) : Color.orange.opacity(0.1))
                    .cornerRadius(8)
                }

                // Recommendations
                VStack(alignment: .leading, spacing: 12) {
                    Text("Recommendations")
                        .font(.title3)
                        .fontWeight(.semibold)

                    ForEach(health.recommendations, id: \.self) { rec in
                        HStack(alignment: .top) {
                            Image(systemName: "lightbulb.fill")
                                .foregroundColor(.yellow)
                            Text(rec)
                                .font(.body)
                        }
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.yellow.opacity(0.1))
                        .cornerRadius(8)
                    }
                }

                Button("Refresh Analysis") {
                    refreshHealthScore()
                }
                .buttonStyle(.bordered)
            } else {
                ProgressView("Analyzing backup health...")
            }
        }
    }

    private func healthMetric(title: String, value: Double, icon: String) -> some View {
        HStack {
            Image(systemName: icon)
                .foregroundColor(scoreColor(value))
                .frame(width: 24)

            Text(title)
                .frame(width: 100, alignment: .leading)

            ProgressView(value: value, total: 100)
                .progressViewStyle(.linear)
                .tint(scoreColor(value))
                .frame(width: 150)

            Text("\(Int(value))%")
                .font(.system(.body, design: .monospaced))
                .foregroundColor(scoreColor(value))
                .frame(width: 50, alignment: .trailing)
        }
    }

    private func gradeColor(_ grade: String) -> Color {
        switch grade {
        case "A": return .green
        case "B": return .blue
        case "C": return .yellow
        case "D": return .orange
        default: return .red
        }
    }

    private func scoreColor(_ score: Double) -> Color {
        switch score {
        case 80...100: return .green
        case 60..<80: return .blue
        case 40..<60: return .yellow
        case 20..<40: return .orange
        default: return .red
        }
    }

    // MARK: - Natural Language Tab

    private var naturalLanguageTab: some View {
        VStack(spacing: 24) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Create Job with Natural Language")
                    .font(.title3)
                    .fontWeight(.semibold)

                Text("Describe what you want to backup in plain English")
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                HStack {
                    TextField("e.g., Backup my documents to iCloud every night at 10pm", text: $naturalLanguageInput)
                        .textFieldStyle(.roundedBorder)
                        .font(.body)

                    Button("Parse") {
                        parsedIntent = aiService.parseNaturalLanguageJob(naturalLanguageInput)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(naturalLanguageInput.isEmpty)
                }
            }
            .padding()
            .background(Color.secondary.opacity(0.05))
            .cornerRadius(12)

            // Parsed Intent Preview
            if let intent = parsedIntent {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Parsed Job Configuration")
                        .font(.title3)
                        .fontWeight(.semibold)

                    Group {
                        configRow(label: "Name", value: intent.suggestedName)
                        configRow(label: "Action", value: intent.action.rawValue.capitalized)
                        configRow(label: "Source", value: intent.sourcePath ?? "Not specified")
                        configRow(label: "Destination Type", value: intent.destinationType.rawValue)
                        configRow(label: "Schedule", value: "\(intent.frequency.description) at \(intent.hour):00")
                    }

                    HStack {
                        Button("Create Job") {
                            createJobFromIntent(intent)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(intent.sourcePath == nil)

                        Button("Clear") {
                            parsedIntent = nil
                            naturalLanguageInput = ""
                        }
                        .buttonStyle(.bordered)
                    }
                }
                .padding()
                .background(Color.purple.opacity(0.05))
                .cornerRadius(12)
            }

            // Example phrases
            VStack(alignment: .leading, spacing: 8) {
                Text("Example phrases:")
                    .font(.headline)

                ForEach([
                    "Backup my documents to iCloud every Sunday",
                    "Sync photos to my NAS daily at 6pm",
                    "Copy my projects folder to external drive weekly"
                ], id: \.self) { example in
                    Button(example) {
                        naturalLanguageInput = example
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(.blue)
                }
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.secondary.opacity(0.05))
            .cornerRadius(12)
        }
    }

    private func configRow(label: String, value: String) -> some View {
        HStack {
            Text(label + ":")
                .foregroundColor(.secondary)
                .frame(width: 120, alignment: .trailing)
            Text(value)
                .fontWeight(.medium)
            Spacer()
        }
    }

    // MARK: - Recovery Tab

    private var recoveryTab: some View {
        VStack(spacing: 24) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Recovery Assistant")
                    .font(.title3)
                    .fontWeight(.semibold)

                Text("Search your backup history to find and recover files")
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)

                    TextField("Search for files (e.g., tax return, vacation photos)", text: $searchQuery)
                        .textFieldStyle(.roundedBorder)

                    Button("Search") {
                        performRecoverySearch()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(searchQuery.isEmpty)
                }
            }
            .padding()
            .background(Color.secondary.opacity(0.05))
            .cornerRadius(12)

            // Search Results
            if !searchResults.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Found \(searchResults.count) results")
                        .font(.headline)

                    ForEach(searchResults) { result in
                        HStack {
                            Image(systemName: "doc.fill")
                                .foregroundColor(.blue)

                            VStack(alignment: .leading) {
                                Text(result.filename)
                                    .font(.body)
                                    .lineLimit(1)

                                Text("Backed up: \(result.syncDate.formatted())")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }

                            Spacer()

                            Button("Locate") {
                                locateFile(result.filename)
                            }
                            .buttonStyle(.bordered)
                        }
                        .padding()
                        .background(Color.secondary.opacity(0.05))
                        .cornerRadius(8)
                    }
                }
            } else if !searchQuery.isEmpty && searchResults.isEmpty {
                Text("No files found matching '\(searchQuery)'")
                    .foregroundColor(.secondary)
                    .padding()
            }
        }
    }

    // MARK: - Security Tab

    private var securityTab: some View {
        VStack(spacing: 24) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Sensitive File Detection")
                    .font(.title3)
                    .fontWeight(.semibold)

                Text("Scan your backup sources for potentially sensitive files")
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                Button(isScanning ? "Scanning..." : "Scan All Sources") {
                    Task {
                        await scanForSensitiveFiles()
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isScanning)
            }
            .padding()
            .background(Color.secondary.opacity(0.05))
            .cornerRadius(12)

            // Results
            if !sensitiveFiles.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Image(systemName: "exclamationmark.shield.fill")
                            .foregroundColor(.red)
                        Text("Found \(sensitiveFiles.count) potentially sensitive files")
                            .font(.headline)
                    }

                    ForEach(sensitiveFiles) { alert in
                        HStack(alignment: .top) {
                            Image(systemName: riskIcon(alert.risk))
                                .foregroundColor(riskColor(alert.risk))
                                .frame(width: 24)

                            VStack(alignment: .leading, spacing: 4) {
                                Text(alert.path)
                                    .font(.system(.body, design: .monospaced))
                                    .lineLimit(1)

                                Text(alert.recommendation)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }

                            Spacer()

                            Text(alert.risk.description)
                                .font(.caption)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(riskColor(alert.risk).opacity(0.2))
                                .cornerRadius(4)
                        }
                        .padding()
                        .background(Color.secondary.opacity(0.05))
                        .cornerRadius(8)
                    }
                }
            } else if !isScanning && sensitiveFiles.isEmpty {
                HStack {
                    Image(systemName: "checkmark.shield.fill")
                        .foregroundColor(.green)
                    Text("No sensitive files detected")
                }
                .padding()
                .frame(maxWidth: .infinity)
                .background(Color.green.opacity(0.1))
                .cornerRadius(8)
            }
        }
    }

    private func riskIcon(_ risk: RiskLevel) -> String {
        switch risk {
        case .critical: return "exclamationmark.triangle.fill"
        case .high: return "exclamationmark.circle.fill"
        case .medium: return "info.circle.fill"
        case .low: return "checkmark.circle.fill"
        }
    }

    private func riskColor(_ risk: RiskLevel) -> Color {
        switch risk {
        case .critical: return .red
        case .high: return .orange
        case .medium: return .yellow
        case .low: return .green
        }
    }

    // MARK: - Exclusions Tab

    private var exclusionsTab: some View {
        VStack(spacing: 24) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Intelligent Exclusion Suggestions")
                    .font(.title3)
                    .fontWeight(.semibold)

                Text("AI analyzes your sources and suggests files/folders to exclude")
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                Button(isScanning ? "Scanning..." : "Analyze Sources") {
                    Task {
                        await analyzeSources()
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isScanning)
            }
            .padding()
            .background(Color.secondary.opacity(0.05))
            .cornerRadius(12)

            // Suggestions
            if !exclusionSuggestions.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Suggested Exclusions")
                        .font(.headline)

                    ForEach(exclusionSuggestions) { suggestion in
                        HStack(alignment: .top) {
                            Image(systemName: suggestion.priority == .high ? "exclamationmark.circle.fill" : "minus.circle.fill")
                                .foregroundColor(suggestion.priority == .high ? .orange : .blue)
                                .frame(width: 24)

                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text(suggestion.pattern)
                                        .font(.system(.body, design: .monospaced))
                                        .fontWeight(.semibold)

                                    Text("~\(suggestion.estimatedSize)")
                                        .font(.caption)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Color.orange.opacity(0.2))
                                        .cornerRadius(4)
                                }

                                Text(suggestion.description)
                                    .font(.subheadline)

                                Text(suggestion.reason)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }

                            Spacer()

                            Button("Add") {
                                addExclusion(suggestion.pattern)
                            }
                            .buttonStyle(.bordered)
                        }
                        .padding()
                        .background(Color.secondary.opacity(0.05))
                        .cornerRadius(8)
                    }
                }
            }
        }
    }

    // MARK: - File Location

    /// Attempt to reveal a file in Finder. If the path is absolute and exists, select it directly.
    /// Otherwise, open the parent directory or fall back to the user's home folder.
    private func locateFile(_ filename: String) {
        let fileURL = URL(fileURLWithPath: filename)

        if filename.hasPrefix("/"), FileManager.default.fileExists(atPath: filename) {
            // Absolute path that exists -- reveal it selected in Finder
            NSWorkspace.shared.selectFile(filename, inFileViewerRootedAtPath: fileURL.deletingLastPathComponent().path)
        } else if filename.hasPrefix("/") {
            // Absolute path that doesn't exist -- open its parent directory if possible
            let parentPath = fileURL.deletingLastPathComponent().path
            if FileManager.default.fileExists(atPath: parentPath) {
                NSWorkspace.shared.open(URL(fileURLWithPath: parentPath))
            } else {
                NSWorkspace.shared.open(URL(fileURLWithPath: NSHomeDirectory()))
            }
        } else {
            // Relative filename -- open a Finder search for it
            let searchURL = URL(fileURLWithPath: NSHomeDirectory())
            NSWorkspace.shared.open(searchURL)
        }
    }

    // MARK: - Actions

    private func refreshHealthScore() {
        let historyEntries = ExecutionHistoryManager.shared.getAllHistory(limit: 100)
        let history = historyEntries.map { entry in
            ExecutionResult(
                id: entry.id,
                jobId: entry.jobId,
                startTime: entry.timestamp,
                endTime: entry.timestamp.addingTimeInterval(entry.duration),
                status: entry.status,
                filesTransferred: entry.filesTransferred,
                bytesTransferred: entry.bytesTransferred,
                errors: entry.errors,
                output: ""
            )
        }
        aiService.healthScore = aiService.calculateHealthScore(jobs: jobManager.jobs, history: history)
    }

    private func createJobFromIntent(_ intent: ParsedJobIntent) {
        guard let source = intent.sourcePath else { return }

        var newJob = SyncJob(
            name: intent.suggestedName,
            source: source,
            destination: intent.destinationPath ?? "",
            destinationType: intent.destinationType
        )

        // Configure schedule
        if intent.frequency != .manual {
            newJob.schedule = ScheduleConfig()
            newJob.schedule?.isEnabled = true
            newJob.schedule?.frequency = intent.frequency
            newJob.schedule?.time = Calendar.current.date(bySettingHour: intent.hour, minute: 0, second: 0, of: Date())
            if let day = intent.dayOfWeek {
                newJob.schedule?.dayOfWeek = day
            }
        }

        jobManager.addJob(newJob)
        parsedIntent = nil
        naturalLanguageInput = ""
    }

    private func performRecoverySearch() {
        let historyEntries = ExecutionHistoryManager.shared.getAllHistory(limit: 500)
        let history = historyEntries.map { entry in
            ExecutionResult(
                id: entry.id,
                jobId: entry.jobId,
                startTime: entry.timestamp,
                endTime: entry.timestamp.addingTimeInterval(entry.duration),
                status: entry.status,
                filesTransferred: entry.filesTransferred,
                bytesTransferred: entry.bytesTransferred,
                errors: entry.errors,
                output: ""  // Note: output not stored in history entry
            )
        }
        searchResults = aiService.searchBackups(query: searchQuery, in: history)
    }

    private func scanForSensitiveFiles() async {
        isScanning = true
        sensitiveFiles = []

        for job in jobManager.jobs {
            for source in job.sources where !source.isEmpty {
                let alerts = await aiService.scanForSensitiveFiles(in: source)
                sensitiveFiles.append(contentsOf: alerts)
            }
        }

        isScanning = false
    }

    private func analyzeSources() async {
        isScanning = true
        exclusionSuggestions = []

        for job in jobManager.jobs {
            for source in job.sources where !source.isEmpty {
                let suggestions = await aiService.suggestExclusions(for: source)
                exclusionSuggestions.append(contentsOf: suggestions)
            }
        }

        // Remove duplicates
        var seen = Set<String>()
        exclusionSuggestions = exclusionSuggestions.filter { seen.insert($0.pattern).inserted }

        isScanning = false
    }

    private func addExclusion(_ pattern: String) {
        // Add to first job or show picker
        if var job = jobManager.jobs.first {
            if !job.options.exclude.contains(pattern) {
                job.options.exclude.append(pattern)
                jobManager.updateJob(job)
            }
        }
    }
}

extension RiskLevel {
    var description: String {
        switch self {
        case .critical: return "Critical"
        case .high: return "High"
        case .medium: return "Medium"
        case .low: return "Low"
        }
    }
}
