//
//  JobEditorView.swift
//  RsyncGUI
//
//  Created by Jordan Koch on 1/14/26.
//

import SwiftUI

struct JobEditorView: View {
    @EnvironmentObject var jobManager: JobManager
    @State var job: SyncJob
    @Binding var isPresented: Bool

    @State private var selectedTab: EditorTab = .basic

    enum EditorTab: String, CaseIterable {
        case basic = "Basic"
        case transfer = "Transfer"
        case preserve = "Preserve"
        case filters = "Filters"
        case advanced = "Advanced"
        case schedule = "Schedule"
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

            Divider()

            // Footer actions
            footer
        }
        .frame(width: 900, height: 700)
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Image(systemName: "pencil.circle.fill")
                .font(.title)
                .foregroundStyle(.blue.gradient)

            VStack(alignment: .leading, spacing: 4) {
                Text("Edit Sync Job")
                    .font(.title2)
                    .fontWeight(.bold)

                Text(job.name)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            Spacer()

            Button("Cancel") {
                isPresented = false
            }
        }
        .padding()
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // MARK: - Tab Bar

    private var tabBar: some View {
        HStack(spacing: 0) {
            ForEach(EditorTab.allCases, id: \.self) { tab in
                Button(action: { selectedTab = tab }) {
                    Text(tab.rawValue)
                        .font(.headline)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
                        .frame(maxWidth: .infinity)
                        .background(selectedTab == tab ? Color.blue.opacity(0.1) : Color.clear)
                        .foregroundColor(selectedTab == tab ? .blue : .secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .background(Color(nsColor: .controlBackgroundColor))
    }

    // MARK: - Tab Content

    @ViewBuilder
    private var tabContent: some View {
        switch selectedTab {
        case .basic:
            basicTab
        case .transfer:
            transferTab
        case .preserve:
            preserveTab
        case .filters:
            filtersTab
        case .advanced:
            advancedTab
        case .schedule:
            scheduleTab
        }
    }

    // MARK: - Basic Tab

    private var basicTab: some View {
        VStack(spacing: 24) {
            FormSection(title: "Job Information") {
                TextField("Job Name", text: $job.name)
                    .textFieldStyle(.roundedBorder)

                Toggle("Enabled", isOn: $job.isEnabled)
            }

            FormSection(title: "Source") {
                HStack {
                    TextField("Source path", text: $job.source)
                        .textFieldStyle(.roundedBorder)

                    Button("Browse") {
                        selectFolder(for: \.source)
                    }
                }

                Text("Tip: Use ~ for home directory (e.g., ~/Documents)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            FormSection(title: "Destination") {
                HStack {
                    TextField("Destination path", text: $job.destination)
                        .textFieldStyle(.roundedBorder)

                    Button("Browse") {
                        selectFolder(for: \.destination)
                    }
                }
            }

            FormSection(title: "Remote Connection") {
                Toggle("Use remote server (SSH)", isOn: $job.isRemote)

                if job.isRemote {
                    HStack {
                        TextField("Username", text: Binding(
                            get: { job.remoteUser ?? "" },
                            set: { job.remoteUser = $0.isEmpty ? nil : $0 }
                        ))
                        .textFieldStyle(.roundedBorder)

                        Text("@")

                        TextField("Host", text: Binding(
                            get: { job.remoteHost ?? "" },
                            set: { job.remoteHost = $0.isEmpty ? nil : $0 }
                        ))
                        .textFieldStyle(.roundedBorder)
                    }

                    HStack {
                        TextField("SSH Key Path (optional)", text: Binding(
                            get: { job.sshKeyPath ?? "" },
                            set: { job.sshKeyPath = $0.isEmpty ? nil : $0 }
                        ))
                        .textFieldStyle(.roundedBorder)

                        Button("Browse") {
                            selectSSHKey()
                        }
                    }

                    Text("Leave empty to use default SSH key (~/.ssh/id_rsa)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            FormSection(title: "Common Options") {
                Toggle("Archive mode (-a): preserve permissions, times, recursive", isOn: $job.options.archive)
                Toggle("Verbose output (-v)", isOn: $job.options.verbose)
                Toggle("Compress during transfer (-z)", isOn: $job.options.compress)
                Toggle("Delete extraneous files from destination (--delete)", isOn: $job.options.delete)
                    .foregroundColor(job.options.delete ? .red : .primary)
                Toggle("Show progress during transfer (--progress)", isOn: $job.options.progress)
                Toggle("Show statistics (--stats)", isOn: $job.options.stats)
            }
        }
    }

    // MARK: - Transfer Tab

    private var transferTab: some View {
        VStack(spacing: 24) {
            FormSection(title: "Transfer Behavior") {
                Toggle("Recursive (-r)", isOn: $job.options.recursive)
                Toggle("Update only (skip newer files) (-u)", isOn: $job.options.update)
                Toggle("Skip creating new files (--existing)", isOn: $job.options.existing)
                Toggle("Skip updating existing files (--ignore-existing)", isOn: $job.options.ignoreExisting)
                Toggle("Keep partially transferred files (--partial)", isOn: $job.options.partial)
                Toggle("Update files in-place (--inplace)", isOn: $job.options.inplace)
            }

            FormSection(title: "Delete Options") {
                Toggle("Delete extraneous files (--delete)", isOn: $job.options.delete)
                    .foregroundColor(job.options.delete ? .red : .primary)

                if job.options.delete {
                    VStack(spacing: 8) {
                        Toggle("Delete excluded files too (--delete-excluded)", isOn: $job.options.deleteExcluded)
                        Toggle("Delete before transfer (--delete-before)", isOn: $job.options.deleteBefore)
                        Toggle("Delete during transfer (--delete-during)", isOn: $job.options.deleteDuring)
                        Toggle("Delete after transfer (--delete-after)", isOn: $job.options.deleteAfter)
                        Toggle("Force delete non-empty dirs (--force)", isOn: $job.options.forceDelete)

                        HStack {
                            Text("Max files to delete:")
                            TextField("Unlimited", value: $job.options.maxDelete, format: .number)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 100)
                        }
                    }
                    .padding(.leading, 20)
                }
            }

            FormSection(title: "Source File Handling") {
                Toggle("Remove source files after transfer (--remove-source-files)", isOn: $job.options.removeSourceFiles)
                    .foregroundColor(job.options.removeSourceFiles ? .red : .primary)

                Text("⚠️ Warning: This DELETES source files after successful transfer!")
                    .font(.caption)
                    .foregroundColor(.red)
                    .opacity(job.options.removeSourceFiles ? 1 : 0)
            }

            FormSection(title: "Partial Transfer") {
                HStack {
                    Text("Partial files directory:")
                    TextField("Default", text: Binding(
                        get: { job.options.partialDir ?? "" },
                        set: { job.options.partialDir = $0.isEmpty ? nil : $0 }
                    ))
                    .textFieldStyle(.roundedBorder)
                }
            }
        }
    }

    // MARK: - Preserve Tab

    private var preserveTab: some View {
        VStack(spacing: 24) {
            FormSection(title: "Preserve Attributes") {
                Toggle("Permissions (-p)", isOn: $job.options.preservePermissions)
                Toggle("Owner (-o) - requires root", isOn: $job.options.preserveOwner)
                Toggle("Group (-g)", isOn: $job.options.preserveGroup)
                Toggle("Modification times (-t)", isOn: $job.options.preserveTimes)
                Toggle("Devices (-D) - requires root", isOn: $job.options.preserveDevices)
                Toggle("Special files (--specials)", isOn: $job.options.preserveSpecials)
                Toggle("ACLs (-A)", isOn: $job.options.preserveAcls)
                Toggle("Extended attributes (-X)", isOn: $job.options.preserveXattrs)
                Toggle("Executability (-E)", isOn: $job.options.preserveExecutability)
            }

            FormSection(title: "Links") {
                Toggle("Copy symlinks as symlinks (-l)", isOn: $job.options.preserveLinks)
                Toggle("Transform symlinks to files (-L)", isOn: $job.options.copyLinks)
                Toggle("Copy unsafe symlinks (--copy-unsafe-links)", isOn: $job.options.copyUnsafeLinks)
                Toggle("Ignore symlinks outside tree (--safe-links)", isOn: $job.options.safeLinks)
                Toggle("Preserve hard links (-H)", isOn: $job.options.hardLinks)
                Toggle("Transform symlink to dir (-k)", isOn: $job.options.copyDirlinks)
                Toggle("Treat symlinked dir as dir (-K)", isOn: $job.options.keepDirlinks)
            }

            FormSection(title: "Time Options") {
                Toggle("Omit directory times (-O)", isOn: $job.options.omitDirTimes)
                Toggle("Omit symlink times (-J)", isOn: $job.options.omitLinkTimes)

                HStack {
                    Text("Modify window (seconds):")
                    TextField("Auto", value: $job.options.modifyWindow, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 100)
                }
            }
        }
    }

    // MARK: - Filters Tab

    private var filtersTab: some View {
        VStack(spacing: 24) {
            FormSection(title: "Exclude Patterns") {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Exclude patterns (one per line):")
                            .font(.headline)
                        Spacer()
                        Button("Add Pattern") {
                            job.options.exclude.append("*.tmp")
                        }
                        .buttonStyle(.bordered)
                    }

                    TextEditor(text: Binding(
                        get: { job.options.exclude.joined(separator: "\n") },
                        set: { job.options.exclude = $0.split(separator: "\n").map(String.init) }
                    ))
                    .font(.system(.body, design: .monospaced))
                    .frame(height: 120)
                    .border(Color.secondary.opacity(0.3))

                    Text("Examples: *.log, .DS_Store, node_modules/, .git/")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                HStack {
                    Text("Exclude from file:")
                    TextField("Path to exclude file", text: Binding(
                        get: { job.options.excludeFrom ?? "" },
                        set: { job.options.excludeFrom = $0.isEmpty ? nil : $0 }
                    ))
                    .textFieldStyle(.roundedBorder)
                }

                Toggle("Auto-ignore CVS files (-C)", isOn: $job.options.cvsExclude)
            }

            FormSection(title: "Include Patterns") {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Include patterns (one per line):")
                            .font(.headline)
                        Spacer()
                        Button("Add Pattern") {
                            job.options.include.append("*.txt")
                        }
                        .buttonStyle(.bordered)
                    }

                    TextEditor(text: Binding(
                        get: { job.options.include.joined(separator: "\n") },
                        set: { job.options.include = $0.split(separator: "\n").map(String.init) }
                    ))
                    .font(.system(.body, design: .monospaced))
                    .frame(height: 100)
                    .border(Color.secondary.opacity(0.3))
                }

                HStack {
                    Text("Include from file:")
                    TextField("Path to include file", text: Binding(
                        get: { job.options.includeFrom ?? "" },
                        set: { job.options.includeFrom = $0.isEmpty ? nil : $0 }
                    ))
                    .textFieldStyle(.roundedBorder)
                }
            }

            FormSection(title: "Size Filters") {
                HStack {
                    Text("Min file size:")
                    TextField("e.g., 10K, 1M", text: Binding(
                        get: { job.options.minSize ?? "" },
                        set: { job.options.minSize = $0.isEmpty ? nil : $0 }
                    ))
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 150)

                    Spacer()

                    Text("Max file size:")
                    TextField("e.g., 100M, 1G", text: Binding(
                        get: { job.options.maxSize ?? "" },
                        set: { job.options.maxSize = $0.isEmpty ? nil : $0 }
                    ))
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 150)
                }
            }
        }
    }

    // MARK: - Advanced Tab

    private var advancedTab: some View {
        VStack(spacing: 24) {
            FormSection(title: "Comparison") {
                Toggle("Ignore times, always checksum (-I)", isOn: $job.options.ignoreTime)
                Toggle("Skip based on size only (--size-only)", isOn: $job.options.sizeOnly)
                Toggle("Skip based on checksum (-c)", isOn: $job.options.checksum)
                Toggle("Find similar file for basis (--fuzzy)", isOn: $job.options.fuzzy)
            }

            FormSection(title: "Performance") {
                HStack {
                    Text("Bandwidth limit (KB/s):")
                    TextField("Unlimited", value: $job.options.bandwidth, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 150)
                }

                HStack {
                    Text("I/O timeout (seconds):")
                    TextField("Default", value: $job.options.timeout, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 150)
                }

                HStack {
                    Text("Block size:")
                    TextField("Auto", value: $job.options.blockSize, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 150)
                }

                Toggle("Copy files whole, no delta (-W)", isOn: $job.options.wholeFile)
                Toggle("Always use incremental rsync (--no-whole-file)", isOn: $job.options.noWholeFile)
            }

            FormSection(title: "Backup") {
                Toggle("Make backups (-b)", isOn: $job.options.backup)

                if job.options.backup {
                    VStack(spacing: 8) {
                        HStack {
                            Text("Backup directory:")
                            TextField("Same location", text: Binding(
                                get: { job.options.backupDir ?? "" },
                                set: { job.options.backupDir = $0.isEmpty ? nil : $0 }
                            ))
                            .textFieldStyle(.roundedBorder)
                        }

                        HStack {
                            Text("Backup suffix:")
                            TextField("~", text: Binding(
                                get: { job.options.suffix ?? "" },
                                set: { job.options.suffix = $0.isEmpty ? nil : $0 }
                            ))
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 100)
                        }
                    }
                    .padding(.leading, 20)
                }
            }

            FormSection(title: "Advanced Options") {
                Toggle("Delay updates until end (--delay-updates)", isOn: $job.options.delayUpdates)
                Toggle("Prune empty directory chains (-m)", isOn: $job.options.pruneEmptyDirs)
                Toggle("Don't map uid/gid by name (--numeric-ids)", isOn: $job.options.numericIds)
                Toggle("Ignore I/O errors (--ignore-errors)", isOn: $job.options.ignoreErrors)
                Toggle("Use fake super-user (--fake-super)", isOn: $job.options.fakeSuper)
                Toggle("Protect args from shell (--protect-args)", isOn: $job.options.protectArgs)
                Toggle("Open files without updating atime (--open-noatime)", isOn: $job.options.openNoatime)
            }

            FormSection(title: "Directory Handling") {
                HStack {
                    Text("Link destination:")
                    TextField("--link-dest=DIR", text: Binding(
                        get: { job.options.linkDest ?? "" },
                        set: { job.options.linkDest = $0.isEmpty ? nil : $0 }
                    ))
                    .textFieldStyle(.roundedBorder)
                }

                HStack {
                    Text("Compare destination:")
                    TextField("--compare-dest=DIR", text: Binding(
                        get: { job.options.compareDest ?? "" },
                        set: { job.options.compareDest = $0.isEmpty ? nil : $0 }
                    ))
                    .textFieldStyle(.roundedBorder)
                }

                HStack {
                    Text("Copy destination:")
                    TextField("--copy-dest=DIR", text: Binding(
                        get: { job.options.copyDest ?? "" },
                        set: { job.options.copyDest = $0.isEmpty ? nil : $0 }
                    ))
                    .textFieldStyle(.roundedBorder)
                }
            }

            FormSection(title: "Output Options") {
                Toggle("Quiet mode (-q)", isOn: $job.options.quiet)
                Toggle("Itemize changes (-i)", isOn: $job.options.itemize)
                Toggle("Human-readable numbers (-h)", isOn: $job.options.humanReadable)

                HStack {
                    Text("Output format:")
                    TextField("--out-format=FORMAT", text: Binding(
                        get: { job.options.outFormat ?? "" },
                        set: { job.options.outFormat = $0.isEmpty ? nil : $0 }
                    ))
                    .textFieldStyle(.roundedBorder)
                }
            }
        }
    }

    // MARK: - Schedule Tab

    private var scheduleTab: some View {
        VStack(spacing: 24) {
            FormSection(title: "Schedule Configuration") {
                Toggle("Enable scheduling", isOn: Binding(
                    get: { job.schedule?.isEnabled ?? false },
                    set: { enabled in
                        if job.schedule == nil {
                            job.schedule = ScheduleConfig()
                        }
                        job.schedule?.isEnabled = enabled
                    }
                ))

                if let schedule = job.schedule, schedule.isEnabled {
                    VStack(spacing: 16) {
                        Picker("Frequency", selection: Binding(
                            get: { job.schedule?.frequency ?? .manual },
                            set: { job.schedule?.frequency = $0 }
                        )) {
                            ForEach(ScheduleFrequency.allCases, id: \.self) { freq in
                                Text(freq.description).tag(freq)
                            }
                        }
                        .pickerStyle(.segmented)

                        if schedule.frequency != .manual && schedule.frequency != .hourly {
                            DatePicker("Time", selection: Binding(
                                get: { job.schedule?.time ?? Date() },
                                set: { job.schedule?.time = $0 }
                            ), displayedComponents: .hourAndMinute)
                        }

                        if schedule.frequency == .weekly {
                            Picker("Day of Week", selection: Binding(
                                get: { job.schedule?.dayOfWeek ?? 0 },
                                set: { job.schedule?.dayOfWeek = $0 }
                            )) {
                                Text("Sunday").tag(0)
                                Text("Monday").tag(1)
                                Text("Tuesday").tag(2)
                                Text("Wednesday").tag(3)
                                Text("Thursday").tag(4)
                                Text("Friday").tag(5)
                                Text("Saturday").tag(6)
                            }
                        }

                        if schedule.frequency == .monthly {
                            Picker("Day of Month", selection: Binding(
                                get: { job.schedule?.dayOfMonth ?? 1 },
                                set: { job.schedule?.dayOfMonth = $0 }
                            )) {
                                ForEach(1...31, id: \.self) { day in
                                    Text("\(day)").tag(day)
                                }
                            }
                        }

                        Toggle("Run at system startup", isOn: Binding(
                            get: { job.schedule?.runAtStartup ?? false },
                            set: { job.schedule?.runAtStartup = $0 }
                        ))
                    }
                    .padding(.leading, 20)
                }
            }

            FormSection(title: "Schedule Preview") {
                if let schedule = job.schedule, schedule.isEnabled {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(scheduleDescription(schedule))
                            .font(.body)

                        Text("Uses macOS launchd - runs even when app is closed")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.blue.opacity(0.1))
                    .cornerRadius(8)
                } else {
                    Text("No schedule configured")
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding()
                }
            }
        }
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            Button("Test Connection") {
                testConnection()
            }
            .buttonStyle(.bordered)

            Spacer()

            Button("Dry Run") {
                saveAndDryRun()
            }
            .buttonStyle(.bordered)

            Button("Save") {
                saveJob()
                isPresented = false
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)
        }
        .padding()
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // MARK: - Actions

    private func saveJob() {
        jobManager.updateJob(job)
        if let schedule = job.schedule, schedule.isEnabled {
            jobManager.updateSchedule(for: job)
        }
    }

    private func saveAndDryRun() {
        saveJob()
        // Trigger dry run execution
        Task {
            do {
                _ = try await jobManager.executeJob(job, dryRun: true)
            } catch {
                print("Dry run failed: \(error)")
            }
        }
    }

    private func testConnection() {
        // Test rsync connection
        print("Testing connection...")
    }

    private func selectFolder(for keyPath: WritableKeyPath<SyncJob, String>) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false

        if panel.runModal() == .OK, let url = panel.url {
            job[keyPath: keyPath] = url.path
        }
    }

    private func selectSSHKey() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.data]

        if panel.runModal() == .OK, let url = panel.url {
            job.sshKeyPath = url.path
        }
    }

    private func scheduleDescription(_ schedule: ScheduleConfig) -> String {
        switch schedule.frequency {
        case .manual:
            return "Manual execution only"
        case .hourly:
            return "Runs every hour at the top of the hour"
        case .daily:
            if let time = schedule.time {
                return "Runs daily at \(time.formatted(date: .omitted, time: .shortened))"
            }
            return "Runs daily"
        case .weekly:
            if let time = schedule.time, let day = schedule.dayOfWeek {
                let dayName = Calendar.current.weekdaySymbols[day]
                return "Runs every \(dayName) at \(time.formatted(date: .omitted, time: .shortened))"
            }
            return "Runs weekly"
        case .monthly:
            if let time = schedule.time, let day = schedule.dayOfMonth {
                return "Runs on day \(day) of each month at \(time.formatted(date: .omitted, time: .shortened))"
            }
            return "Runs monthly"
        case .custom:
            if let cron = schedule.customCron {
                return "Custom schedule: \(cron)"
            }
            return "Custom schedule"
        }
    }
}

// MARK: - Form Section

struct FormSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title)
                .font(.title3)
                .fontWeight(.semibold)

            VStack(alignment: .leading, spacing: 12) {
                content
            }
            .padding()
            .background(Color.secondary.opacity(0.05))
            .cornerRadius(12)
        }
    }
}
