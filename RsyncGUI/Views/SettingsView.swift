//
//  SettingsView.swift
//  RsyncGUI
//
//  Created by Jordan Koch on 1/14/26.
//

import SwiftUI

struct SettingsView: View {
    @AppStorage("defaultRsyncPath") private var defaultRsyncPath = "/usr/bin/rsync"
    @AppStorage("notificationsEnabled") private var notificationsEnabled = true
    @AppStorage("autoSaveJobs") private var autoSaveJobs = true
    @AppStorage("confirmDeletions") private var confirmDeletions = true

    var body: some View {
        TabView {
            GeneralSettings()
                .tabItem {
                    Label("General", systemImage: "gear")
                }

            NotificationSettings()
                .tabItem {
                    Label("Notifications", systemImage: "bell")
                }

            AdvancedSettings()
                .tabItem {
                    Label("Advanced", systemImage: "slider.horizontal.3")
                }
        }
        .frame(width: 600, height: 400)
    }
}

// MARK: - General Settings

struct GeneralSettings: View {
    @AppStorage("defaultRsyncPath") private var defaultRsyncPath = "/usr/bin/rsync"
    @AppStorage("autoSaveJobs") private var autoSaveJobs = true
    @AppStorage("confirmDeletions") private var confirmDeletions = true
    @State private var rsyncVersionString: String = "Loading..."

    var body: some View {
        Form {
            Section("Application") {
                Toggle("Auto-save jobs after changes", isOn: $autoSaveJobs)
                Toggle("Confirm before deleting jobs", isOn: $confirmDeletions)
            }

            Section("Rsync Binary") {
                HStack {
                    TextField("Path to rsync", text: $defaultRsyncPath)
                        .textFieldStyle(.roundedBorder)

                    Button("Browse") {
                        selectRsyncBinary()
                    }
                }

                Text("Current version: \(rsyncVersionString)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
        .task(id: defaultRsyncPath) {
            rsyncVersionString = await fetchRsyncVersion(path: defaultRsyncPath)
        }
    }

    private func fetchRsyncVersion(path: String) async -> String {
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let task = Process()
                task.executableURL = URL(fileURLWithPath: path)
                task.arguments = ["--version"]

                let pipe = Pipe()
                task.standardOutput = pipe
                task.standardError = Pipe() // Prevent stderr from leaking

                do {
                    try task.run()
                    task.waitUntilExit()

                    let data = pipe.fileHandleForReading.readDataToEndOfFile()
                    if let output = String(data: data, encoding: .utf8) {
                        let lines = output.components(separatedBy: .newlines)
                        continuation.resume(returning: lines.first ?? "Unknown")
                        return
                    }
                } catch {
                    NSLog("[RsyncGUI] Failed to get rsync version at path %@: %@", path, error.localizedDescription)
                    continuation.resume(returning: "Not found")
                    return
                }

                continuation.resume(returning: "Unknown")
            }
        }
    }

    private func selectRsyncBinary() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false

        if panel.runModal() == .OK, let url = panel.url {
            defaultRsyncPath = url.path
        }
    }
}

// MARK: - Notification Settings

struct NotificationSettings: View {
    @AppStorage("notificationsEnabled") private var notificationsEnabled = true
    @AppStorage("notifyOnSuccess") private var notifyOnSuccess = true
    @AppStorage("notifyOnFailure") private var notifyOnFailure = true
    @AppStorage("playSoundOnCompletion") private var playSoundOnCompletion = false

    var body: some View {
        Form {
            Section("Notifications") {
                Toggle("Enable notifications", isOn: $notificationsEnabled)

                if notificationsEnabled {
                    Toggle("Notify on successful completion", isOn: $notifyOnSuccess)
                    Toggle("Notify on failure", isOn: $notifyOnFailure)
                    Toggle("Play sound on completion", isOn: $playSoundOnCompletion)
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

// MARK: - Advanced Settings

struct AdvancedSettings: View {
    @AppStorage("maxConcurrentJobs") private var maxConcurrentJobs = 1
    @AppStorage("keepLogDays") private var keepLogDays = 30
    @AppStorage("enableDebugLogging") private var enableDebugLogging = false

    var body: some View {
        Form {
            Section("Performance") {
                Stepper("Max concurrent jobs: \(maxConcurrentJobs)", value: $maxConcurrentJobs, in: 1...10)
            }

            Section("Logs") {
                Stepper("Keep logs for \(keepLogDays) days", value: $keepLogDays, in: 1...365)
                Toggle("Enable debug logging", isOn: $enableDebugLogging)

                Button("View Logs Folder") {
                    openLogsFolder()
                }
            }

            Section("Data") {
                Button("Export All Jobs") {
                    exportJobs()
                }

                Button("Import Jobs") {
                    importJobs()
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    private func openLogsFolder() {
        let logsURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("RsyncGUI/Logs")

        NSWorkspace.shared.open(logsURL)
    }

    private func exportJobs() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "rsyncgui-jobs-\(Date().formatted(date: .numeric, time: .omitted)).json"

        if panel.runModal() == .OK, let url = panel.url {
            let jobs = JobManager.shared.jobs
            if let data = try? JSONEncoder().encode(jobs) {
                do {
                    try data.write(to: url, options: .atomic)
                    showAlert(title: "Export Successful", message: "Exported \(jobs.count) job(s) to \(url.lastPathComponent)")
                } catch {
                    showAlert(title: "Export Failed", message: "Error: \(error.localizedDescription)")
                }
            }
        }
    }

    /// Validate an imported job for dangerous or malformed data.
    /// Returns an error message if validation fails, or nil if the job is acceptable.
    private func validateImportedJob(_ job: SyncJob) -> String? {
        // Validate job name length
        if job.name.count > 256 {
            return "Job name exceeds 256 characters: \(job.name.prefix(50))..."
        }

        // Validate sources are not empty and don't contain path traversal
        for source in job.sources {
            let trimmed = source.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                return "Job '\(job.name)' has an empty source path"
            }
            if trimmed.contains("..") {
                return "Job '\(job.name)' has a source path containing path traversal (..): \(trimmed)"
            }
        }

        // Validate destinations
        for dest in job.destinations {
            let trimmedPath = dest.path.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmedPath.isEmpty {
                return "Job '\(job.name)' has an empty destination path"
            }
            if trimmedPath.contains("..") {
                return "Job '\(job.name)' has a destination path containing path traversal (..): \(trimmedPath)"
            }
        }

        // Dangerous patterns for pre/post scripts
        let dangerousPatterns = ["rm -rf /", "rm -rf /*", "sudo ", "mkfs", "dd if=", "> /dev/sd", ":(){ :|:& };:"]

        if let preScript = job.preScript, !preScript.isEmpty {
            for pattern in dangerousPatterns {
                if preScript.contains(pattern) {
                    return "Job '\(job.name)' preScript contains dangerous pattern: \(pattern)"
                }
            }
        }

        if let postScript = job.postScript, !postScript.isEmpty {
            for pattern in dangerousPatterns {
                if postScript.contains(pattern) {
                    return "Job '\(job.name)' postScript contains dangerous pattern: \(pattern)"
                }
            }
        }

        return nil
    }

    private func importJobs() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.json]

        if panel.runModal() == .OK, let url = panel.url {
            do {
                let data = try Data(contentsOf: url)
                let jobs = try JSONDecoder().decode([SyncJob].self, from: data)

                // Validate jobs
                guard !jobs.isEmpty else {
                    showAlert(title: "Import Failed", message: "No jobs found in file")
                    return
                }

                NSLog("[RsyncGUI] Import: Attempting to import %d job(s) from %@", jobs.count, url.lastPathComponent)

                // Check for duplicate job IDs
                let existingIds = Set(JobManager.shared.jobs.map { $0.id })
                var imported = 0
                var skipped = 0
                var validationErrors: [String] = []

                for var job in jobs {
                    // Validate each imported job
                    if let error = validateImportedJob(job) {
                        NSLog("[RsyncGUI] Import: REJECTED job '%@' (id: %@): %@", job.name, job.id.uuidString, error)
                        validationErrors.append(error)
                        skipped += 1
                        continue
                    }

                    if existingIds.contains(job.id) {
                        // Generate new ID for duplicates
                        job.id = UUID()
                        job.name = job.name + " (Imported)"
                    }
                    NSLog("[RsyncGUI] Import: Accepted job '%@' (id: %@), sources: %d, destinations: %d", job.name, job.id.uuidString, job.sources.count, job.destinations.count)
                    JobManager.shared.jobs.append(job)
                    imported += 1
                }

                JobManager.shared.saveJobs()

                var message = "Imported \(imported) job(s)"
                if skipped > 0 {
                    message += ", skipped \(skipped) due to validation errors"
                    if let firstError = validationErrors.first {
                        message += ".\nFirst error: \(firstError)"
                    }
                }
                NSLog("[RsyncGUI] Import: Complete. Imported: %d, Skipped: %d", imported, skipped)
                showAlert(title: skipped > 0 ? "Import Partially Successful" : "Import Successful", message: message)
            } catch {
                NSLog("[RsyncGUI] Import: Failed to decode jobs from %@: %@", url.lastPathComponent, error.localizedDescription)
                showAlert(title: "Import Failed", message: "Error: \(error.localizedDescription)")
            }
        }
    }

    private func showAlert(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = title.contains("Failed") ? .warning : .informational
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}
