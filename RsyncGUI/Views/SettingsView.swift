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

                Text("Current version: \(rsyncVersion)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    private var rsyncVersion: String {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: defaultRsyncPath)
        task.arguments = ["--version"]

        let pipe = Pipe()
        task.standardOutput = pipe

        do {
            try task.run()
            task.waitUntilExit()

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if let output = String(data: data, encoding: .utf8) {
                let lines = output.components(separatedBy: .newlines)
                return lines.first ?? "Unknown"
            }
        } catch {
            return "Not found"
        }

        return "Unknown"
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

                // Check for duplicate job IDs
                let existingIds = Set(JobManager.shared.jobs.map { $0.id })
                var imported = 0
                var skipped = 0

                for var job in jobs {
                    if existingIds.contains(job.id) {
                        // Generate new ID for duplicates
                        job.id = UUID()
                        job.name = job.name + " (Imported)"
                    }
                    JobManager.shared.jobs.append(job)
                    imported += 1
                }

                JobManager.shared.saveJobs()
                showAlert(title: "Import Successful", message: "Imported \(imported) job(s)")
            } catch {
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
