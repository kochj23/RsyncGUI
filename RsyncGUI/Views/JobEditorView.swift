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
    @State private var showingTestResult = false
    @State private var testResult: TestConnectionResult?

    enum EditorTab: String, CaseIterable {
        case basic = "Basic"
        case syncMode = "Sync Mode"
        case transfer = "Transfer"
        case preserve = "Preserve"
        case filters = "Filters"
        case advanced = "Advanced"
        case parallelism = "Parallelism"
        case dependencies = "Dependencies"
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
        .alert("Connection Test", isPresented: $showingTestResult, presenting: testResult) { result in
            Button("OK") {
                showingTestResult = false
            }
        } message: { result in
            VStack(alignment: .leading, spacing: 8) {
                Text(result.overallSuccess ? "✅ All checks passed!" : "⚠️ Some checks failed")
                    .font(.headline)

                ForEach(result.checks) { check in
                    Text(check.message)
                        .font(.caption)
                }
            }
        }
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
        case .syncMode:
            syncModeTab
        case .transfer:
            transferTab
        case .preserve:
            preserveTab
        case .filters:
            filtersTab
        case .advanced:
            advancedTab
        case .parallelism:
            parallelismTab
        case .dependencies:
            dependenciesTab
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

            FormSection(title: "Sources (\(job.sources.count))") {
                ForEach(job.sources.indices, id: \.self) { index in
                    HStack {
                        Image(systemName: "folder.fill")
                            .foregroundColor(.blue)

                        TextField("Source path", text: $job.sources[index])
                            .textFieldStyle(.roundedBorder)

                        Button(action: { browseForSource(at: index) }) {
                            Image(systemName: "folder.badge.plus")
                        }
                        .buttonStyle(.bordered)

                        if job.sources.count > 1 {
                            Button(action: { job.sources.remove(at: index) }) {
                                Image(systemName: "minus.circle.fill")
                                    .foregroundColor(.red)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                HStack {
                    Button(action: { job.sources.append("") }) {
                        Label("Add Source", systemImage: "plus.circle.fill")
                    }
                    .buttonStyle(.bordered)

                    Spacer()

                    Text("Tip: Use ~ for home directory")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            FormSection(title: "Destinations (\(job.destinations.count))") {
                ForEach($job.destinations) { $dest in
                    destinationRow(destination: $dest)
                }

                Button(action: { job.destinations.append(SyncDestination()) }) {
                    Label("Add Destination", systemImage: "plus.circle.fill")
                }
                .buttonStyle(.bordered)
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

    // MARK: - Sync Mode Tab

    private var syncModeTab: some View {
        VStack(spacing: 24) {
            FormSection(title: "Sync Mode") {
                VStack(alignment: .leading, spacing: 16) {
                    ForEach(SyncMode.allCases, id: \.self) { mode in
                        HStack(spacing: 16) {
                            Image(systemName: mode.icon)
                                .font(.title2)
                                .foregroundColor(job.syncMode == mode ? .blue : .secondary)
                                .frame(width: 30)

                            VStack(alignment: .leading, spacing: 4) {
                                Text(mode.rawValue)
                                    .font(.headline)
                                    .foregroundColor(job.syncMode == mode ? .primary : .secondary)

                                Text(mode.description)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }

                            Spacer()

                            if job.syncMode == mode {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.blue)
                            }
                        }
                        .padding()
                        .background(job.syncMode == mode ? Color.blue.opacity(0.1) : Color.secondary.opacity(0.05))
                        .cornerRadius(8)
                        .onTapGesture {
                            job.syncMode = mode
                        }
                    }
                }

                // Visual diagram of current mode
                syncModeDiagram
            }

            FormSection(title: "Execution Strategy") {
                Picker("Strategy", selection: $job.executionStrategy) {
                    ForEach(ExecutionStrategy.allCases, id: \.self) { strategy in
                        Text(strategy.rawValue).tag(strategy)
                    }
                }
                .pickerStyle(.segmented)

                Text(job.executionStrategy.description)
                    .font(.caption)
                    .foregroundColor(.secondary)

                if job.executionStrategy == .parallel {
                    Stepper("Max parallel syncs: \(job.maxParallelSyncs)", value: $job.maxParallelSyncs, in: 2...8)

                    Text("⚡ Parallel mode can significantly speed up syncs to multiple destinations")
                        .font(.caption)
                        .foregroundColor(.orange)
                }
            }

            FormSection(title: "Failure Handling") {
                Picker("On failure", selection: $job.failureHandling) {
                    ForEach(FailureHandling.allCases, id: \.self) { handling in
                        Text(handling.rawValue).tag(handling)
                    }
                }
                .pickerStyle(.segmented)

                Text(job.failureHandling.description)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            FormSection(title: "Verification") {
                Toggle("Verify after sync (checksum comparison)", isOn: $job.verifyAfterSync)

                if job.verifyAfterSync {
                    Text("After sync completes, rsync will run again with --checksum to verify all files match")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Text("⚠️ Verification doubles the sync time but ensures data integrity")
                        .font(.caption)
                        .foregroundColor(.orange)
                }
            }

            FormSection(title: "Scripts") {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Pre-sync script (runs before sync starts)")
                        .font(.subheadline)
                        .foregroundColor(.secondary)

                    TextField("e.g., /path/to/script.sh or shell command", text: Binding(
                        get: { job.preScript ?? "" },
                        set: { job.preScript = $0.isEmpty ? nil : $0 }
                    ))
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))
                }

                VStack(alignment: .leading, spacing: 12) {
                    Text("Post-sync script (runs after sync completes)")
                        .font(.subheadline)
                        .foregroundColor(.secondary)

                    TextField("e.g., /path/to/script.sh or shell command", text: Binding(
                        get: { job.postScript ?? "" },
                        set: { job.postScript = $0.isEmpty ? nil : $0 }
                    ))
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))
                }

                Text("Scripts run with your user privileges. Only use scripts you trust.")
                    .font(.caption)
                    .foregroundColor(.orange)

                Text("Scripts receive JOB_NAME, JOB_STATUS, FILES_TRANSFERRED environment variables")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }

    // MARK: - Sync Mode Diagram

    private var syncModeDiagram: some View {
        VStack(spacing: 8) {
            Text("Current Configuration")
                .font(.caption)
                .foregroundColor(.secondary)

            HStack(spacing: 20) {
                // Sources
                VStack(spacing: 4) {
                    ForEach(job.sources.indices, id: \.self) { index in
                        if !job.sources[index].isEmpty {
                            HStack {
                                Image(systemName: "folder.fill")
                                    .foregroundColor(.blue)
                                Text(URL(fileURLWithPath: job.sources[index]).lastPathComponent)
                                    .font(.caption)
                                    .lineLimit(1)
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.blue.opacity(0.1))
                            .cornerRadius(4)
                        }
                    }
                }

                // Arrows
                VStack {
                    Image(systemName: job.syncMode.icon)
                        .font(.title)
                        .foregroundColor(.orange)
                }

                // Destinations
                VStack(spacing: 4) {
                    ForEach(job.destinations.filter { $0.isEnabled }) { dest in
                        HStack {
                            Image(systemName: dest.type == .remoteSSH ? "server.rack" :
                                    dest.type == .iCloudDrive ? "icloud.fill" : "externaldrive.fill")
                                .foregroundColor(.green)
                            Text(URL(fileURLWithPath: dest.path).lastPathComponent)
                                .font(.caption)
                                .lineLimit(1)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.green.opacity(0.1))
                        .cornerRadius(4)
                    }
                }
            }
            .padding()
            .background(Color.secondary.opacity(0.05))
            .cornerRadius(8)
        }
    }

    // MARK: - Destination Row

    @ViewBuilder
    private func destinationRow(destination: Binding<SyncDestination>) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: destination.wrappedValue.type == .remoteSSH ? "server.rack" :
                        destination.wrappedValue.type == .iCloudDrive ? "icloud.fill" : "externaldrive.fill")
                    .foregroundColor(destination.wrappedValue.type == .remoteSSH ? .orange :
                        destination.wrappedValue.type == .iCloudDrive ? .blue : .green)

                Picker("", selection: destination.type) {
                    ForEach([DestinationType.local, .iCloudDrive, .remoteSSH], id: \.self) { type in
                        Text(type.rawValue).tag(type)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 350)

                Toggle("", isOn: destination.isEnabled)
                    .toggleStyle(.switch)
                    .labelsHidden()

                if job.destinations.count > 1 {
                    Button(action: {
                        job.destinations.removeAll { $0.id == destination.wrappedValue.id }
                    }) {
                        Image(systemName: "minus.circle.fill")
                            .foregroundColor(.red)
                    }
                    .buttonStyle(.plain)
                }
            }

            HStack {
                TextField("Destination path", text: destination.path)
                    .textFieldStyle(.roundedBorder)

                Button("Browse") {
                    browseForDestination(destinationId: destination.wrappedValue.id)
                }
                .buttonStyle(.bordered)

                if destination.wrappedValue.type == .iCloudDrive {
                    Button("iCloud") {
                        selectiCloudDriveFor(destinationId: destination.wrappedValue.id)
                    }
                    .buttonStyle(.bordered)
                }
            }

            if destination.wrappedValue.type == .remoteSSH {
                HStack {
                    TextField("Username", text: Binding(
                        get: { destination.wrappedValue.remoteUser ?? "" },
                        set: { destination.wrappedValue.remoteUser = $0.isEmpty ? nil : $0 }
                    ))
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 150)

                    Text("@")

                    TextField("Host", text: Binding(
                        get: { destination.wrappedValue.remoteHost ?? "" },
                        set: { destination.wrappedValue.remoteHost = $0.isEmpty ? nil : $0 }
                    ))
                    .textFieldStyle(.roundedBorder)

                    TextField("SSH Key (optional)", text: Binding(
                        get: { destination.wrappedValue.sshKeyPath ?? "" },
                        set: { destination.wrappedValue.sshKeyPath = $0.isEmpty ? nil : $0 }
                    ))
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 200)
                }
            }

            if !destination.wrappedValue.isEnabled {
                Text("This destination is disabled and will be skipped")
                    .font(.caption)
                    .foregroundColor(.orange)
            }
        }
        .padding()
        .background(destination.wrappedValue.isEnabled ? Color.secondary.opacity(0.05) : Color.orange.opacity(0.05))
        .cornerRadius(8)
    }

    // MARK: - Browse Helpers

    private func browseForSource(at index: Int) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false

        if panel.runModal() == .OK, let url = panel.url {
            job.sources[index] = url.path
        }
    }

    private func browseForDestination(destinationId: UUID) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false

        if panel.runModal() == .OK, let url = panel.url {
            if let index = job.destinations.firstIndex(where: { $0.id == destinationId }) {
                job.destinations[index].path = url.path
            }
        }
    }

    private func selectiCloudDriveFor(destinationId: UUID) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "Select iCloud Drive folder to grant RsyncGUI access permission"
        panel.prompt = "Grant Access"

        let iCloudPath = SyncJob.iCloudDrivePath
        if FileManager.default.fileExists(atPath: iCloudPath) {
            panel.directoryURL = URL(fileURLWithPath: iCloudPath)
        }

        if panel.runModal() == .OK, let url = panel.url {
            if let index = job.destinations.firstIndex(where: { $0.id == destinationId }) {
                job.destinations[index].path = url.path
                do {
                    let bookmark = try url.bookmarkData(
                        options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess],
                        includingResourceValuesForKeys: nil,
                        relativeTo: nil
                    )
                    job.destinations[index].bookmark = bookmark
                } catch {
                    NSLog("[JobEditor] Failed to create bookmark: %@", error.localizedDescription)
                }
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
                                .onChange(of: job.options.maxDelete) { newValue in
                                    if let val = newValue, val < 0 { job.options.maxDelete = nil }
                                }
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
                        .onChange(of: job.options.modifyWindow) { newValue in
                            if let val = newValue, val < 0 { job.options.modifyWindow = nil }
                        }
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
                        .onChange(of: job.options.bandwidth) { newValue in
                            if let val = newValue, val < 0 { job.options.bandwidth = nil }
                        }
                }

                HStack {
                    Text("I/O timeout (seconds):")
                    TextField("Default", value: $job.options.timeout, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 150)
                        .onChange(of: job.options.timeout) { newValue in
                            if let val = newValue, val < 0 { job.options.timeout = nil }
                        }
                }

                HStack {
                    Text("Block size:")
                    TextField("Auto", value: $job.options.blockSize, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 150)
                        .onChange(of: job.options.blockSize) { newValue in
                            if let val = newValue, val < 0 { job.options.blockSize = nil }
                        }
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

    // MARK: - Parallelism Tab

    private var parallelismTab: some View {
        VStack(spacing: 24) {
            FormSection(title: "Parallel Execution") {
                Toggle("Enable parallelism (for tons of tiny files)", isOn: Binding(
                    get: { job.parallelism?.isEnabled ?? false },
                    set: { enabled in
                        if job.parallelism == nil {
                            job.parallelism = ParallelismConfig()
                        }
                        job.parallelism?.isEnabled = enabled
                    }
                ))

                if let parallelConfig = job.parallelism, parallelConfig.isEnabled {
                    VStack(spacing: 16) {
                        Stepper("Number of parallel threads: \(job.parallelism?.numberOfThreads ?? 4)", value: Binding(
                            get: { job.parallelism?.numberOfThreads ?? 4 },
                            set: { job.parallelism?.numberOfThreads = $0 }
                        ), in: 2...16)

                        Picker("Split Strategy", selection: Binding(
                            get: { job.parallelism?.strategy ?? .automatic },
                            set: { job.parallelism?.strategy = $0 }
                        )) {
                            ForEach(ParallelStrategy.allCases, id: \.self) { strategy in
                                VStack(alignment: .leading) {
                                    Text(strategy.rawValue)
                                    Text(strategy.description)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                .tag(strategy)
                            }
                        }

                        Text("⚡ Best for: Thousands of small files (< 1MB each)")
                            .font(.caption)
                            .foregroundColor(.orange)
                            .padding()
                            .frame(maxWidth: .infinity)
                            .background(Color.orange.opacity(0.1))
                            .cornerRadius(8)
                    }
                    .padding(.leading, 20)
                }
            }

            FormSection(title: "How Parallelism Works") {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: "1.circle.fill")
                            .foregroundColor(.blue)
                        VStack(alignment: .leading) {
                            Text("Analyze Source")
                                .fontWeight(.semibold)
                            Text("Scan source directory and list all files")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }

                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: "2.circle.fill")
                            .foregroundColor(.blue)
                        VStack(alignment: .leading) {
                            Text("Split Work")
                                .fontWeight(.semibold)
                            Text("Divide files across \(job.parallelism?.numberOfThreads ?? 4) threads based on strategy")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }

                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: "3.circle.fill")
                            .foregroundColor(.blue)
                        VStack(alignment: .leading) {
                            Text("Execute in Parallel")
                                .fontWeight(.semibold)
                            Text("Run \(job.parallelism?.numberOfThreads ?? 4) rsync processes simultaneously")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }

                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: "4.circle.fill")
                            .foregroundColor(.blue)
                        VStack(alignment: .leading) {
                            Text("Combine Results")
                                .fontWeight(.semibold)
                            Text("Merge statistics from all threads")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .padding()
                .background(Color.blue.opacity(0.05))
                .cornerRadius(8)
            }
        }
    }

    // MARK: - Dependencies Tab

    private var dependenciesTab: some View {
        VStack(spacing: 24) {
            FormSection(title: "Job Dependencies") {
                VStack(alignment: .leading, spacing: 12) {
                    Text("This job will only run after these jobs complete successfully:")
                        .font(.subheadline)
                        .foregroundColor(.secondary)

                    ForEach(job.dependencies, id: \.self) { depId in
                        if let depJob = jobManager.jobs.first(where: { $0.id == depId }) {
                            HStack {
                                Image(systemName: "arrow.right.circle.fill")
                                    .foregroundColor(.blue)
                                Text(depJob.name)
                                    .font(.body)
                                Spacer()
                                Button(action: {
                                    job.dependencies.removeAll { $0 == depId }
                                }) {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundColor(.red)
                                }
                                .buttonStyle(.plain)
                            }
                            .padding()
                            .background(Color.secondary.opacity(0.1))
                            .cornerRadius(8)
                        }
                    }

                    if job.dependencies.isEmpty {
                        Text("No dependencies configured")
                            .foregroundColor(.secondary)
                            .italic()
                    }

                    Menu {
                        ForEach(jobManager.jobs.filter { $0.id != job.id }) { availableJob in
                            Button(availableJob.name) {
                                if !job.dependencies.contains(availableJob.id) {
                                    job.dependencies.append(availableJob.id)
                                }
                            }
                        }
                    } label: {
                        Label("Add Dependency", systemImage: "plus.circle.fill")
                    }
                    .buttonStyle(.bordered)
                }
            }

            FormSection(title: "Conditional Execution") {
                Toggle("Only run if source has changed", isOn: $job.runOnlyIfChanged)

                if job.runOnlyIfChanged {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                            Text("Smart execution enabled")
                                .fontWeight(.semibold)
                        }

                        Text("RsyncGUI will calculate a checksum of your source directory (file list + modification times) before each scheduled run. If nothing changed, the sync will be skipped.")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        Text("💡 Perfect for scheduled backups where source rarely changes")
                            .font(.caption)
                            .foregroundColor(.blue)
                    }
                    .padding()
                    .background(Color.green.opacity(0.1))
                    .cornerRadius(8)
                }
            }

            FormSection(title: "Delta Reporting") {
                Toggle("Enable itemized changes (--itemize-changes)", isOn: $job.options.itemize)

                if job.options.itemize {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("When enabled, RsyncGUI will generate a detailed report showing:")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        HStack(spacing: 20) {
                            VStack(alignment: .leading) {
                                HStack {
                                    Image(systemName: "plus.circle.fill")
                                        .foregroundColor(.green)
                                    Text("Files Added")
                                }
                                HStack {
                                    Image(systemName: "pencil.circle.fill")
                                        .foregroundColor(.orange)
                                    Text("Files Modified")
                                }
                                HStack {
                                    Image(systemName: "trash.circle.fill")
                                        .foregroundColor(.red)
                                    Text("Files Deleted")
                                }
                            }
                            .font(.caption)

                            Spacer()
                        }

                        Text("View delta reports in job history after each sync")
                            .font(.caption)
                            .foregroundColor(.blue)
                    }
                    .padding()
                    .background(Color.blue.opacity(0.1))
                    .cornerRadius(8)
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

            if let message = validationMessage {
                Text(message)
                    .font(.caption)
                    .foregroundColor(.red)
            }

            Spacer()

            Button("Dry Run") {
                saveAndDryRun()
            }
            .buttonStyle(.bordered)
            .disabled(!isValid)

            Button("Save") {
                saveJob()
                isPresented = false
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)
            .disabled(!isValid)
        }
        .padding()
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // MARK: - Validation

    /// Validates the job has reasonable, non-empty inputs before saving.
    private var isValid: Bool {
        // Job name must not be empty or whitespace-only
        guard !job.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }

        // At least one non-empty source path
        let validSources = job.sources.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        guard !validSources.isEmpty else { return false }

        // At least one destination with a non-empty path
        let validDestinations = job.destinations.filter { !$0.path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        guard !validDestinations.isEmpty else { return false }

        return true
    }

    /// Human-readable validation error message, or nil if valid.
    private var validationMessage: String? {
        if job.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "Job name cannot be empty"
        }
        let validSources = job.sources.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        if validSources.isEmpty {
            return "At least one source path is required"
        }
        let validDestinations = job.destinations.filter { !$0.path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        if validDestinations.isEmpty {
            return "At least one destination path is required"
        }
        return nil
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
        Task {
            showingTestResult = false
            let result = await performConnectionTest()
            await MainActor.run {
                testResult = result
                showingTestResult = true
            }
        }
    }

    private func performConnectionTest() async -> TestConnectionResult {
        var checks: [ConnectionCheck] = []

        // 1. Check source path
        let sourcePath = job.source.replacingOccurrences(of: "~", with: FileManager.default.homeDirectoryForCurrentUser.path)
        let sourceExists = FileManager.default.fileExists(atPath: sourcePath)
        checks.append(ConnectionCheck(
            name: "Source Path",
            passed: sourceExists,
            message: sourceExists ? "✅ \(sourcePath)" : "❌ Path not found: \(sourcePath)"
        ))

        // 2. Check destination path (if local)
        if !job.isRemote {
            let destPath = job.destination.replacingOccurrences(of: "~", with: FileManager.default.homeDirectoryForCurrentUser.path)
            let destExists = FileManager.default.fileExists(atPath: destPath)
            checks.append(ConnectionCheck(
                name: "Destination Path",
                passed: destExists,
                message: destExists ? "✅ \(destPath)" : "⚠️  Path not found (will be created): \(destPath)"
            ))
        }

        // 3. Test SSH connection if remote
        if job.isRemote, let host = job.remoteHost, let user = job.remoteUser {
            let sshResult = await testSSHConnection(user: user, host: host, keyPath: job.sshKeyPath)
            checks.append(sshResult)
        }

        // 4. Check rsync is installed (use user-configured path)
        let rsyncPath = UserDefaults.standard.string(forKey: "defaultRsyncPath") ?? "/usr/bin/rsync"
        let rsyncExists = FileManager.default.fileExists(atPath: rsyncPath)
        checks.append(ConnectionCheck(
            name: "rsync Binary",
            passed: rsyncExists,
            message: rsyncExists ? "rsync found at \(rsyncPath)" : "rsync not found at \(rsyncPath)"
        ))

        let allPassed = checks.allSatisfy { $0.passed }
        return TestConnectionResult(checks: checks, overallSuccess: allPassed)
    }

    private func testSSHConnection(user: String, host: String, keyPath: String?) async -> ConnectionCheck {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ssh")

        var args = ["-o", "BatchMode=yes", "-o", "ConnectTimeout=5"]
        if let key = keyPath {
            args.append(contentsOf: ["-i", key])
        }
        args.append("\(user)@\(host)")
        args.append("echo 'Connection successful'")

        process.arguments = args

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        do {
            try process.run()
            process.waitUntilExit()

            if process.terminationStatus == 0 {
                return ConnectionCheck(
                    name: "SSH Connection",
                    passed: true,
                    message: "✅ Connected to \(user)@\(host)"
                )
            } else {
                return ConnectionCheck(
                    name: "SSH Connection",
                    passed: false,
                    message: "❌ Failed to connect to \(user)@\(host)"
                )
            }
        } catch {
            return ConnectionCheck(
                name: "SSH Connection",
                passed: false,
                message: "❌ SSH error: \(error.localizedDescription)"
            )
        }
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

    private func selectiCloudDrive() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "Select iCloud Drive folder to grant RsyncGUI access permission"
        panel.prompt = "Grant Access"

        // Try to navigate to iCloud Drive automatically
        let iCloudPath = SyncJob.iCloudDrivePath
        if FileManager.default.fileExists(atPath: iCloudPath) {
            panel.directoryURL = URL(fileURLWithPath: iCloudPath)
        }

        if panel.runModal() == .OK, let url = panel.url {
            // User selected folder - app now has permission to access it
            job.destination = url.path

            // Create and save security-scoped bookmark to persist permission
            do {
                let bookmark = try url.bookmarkData(
                    options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess],
                    includingResourceValuesForKeys: nil,
                    relativeTo: nil
                )
                job.destinationBookmark = bookmark
                NSLog("[JobEditor] ✅ iCloud Drive folder selected: %@", url.path)
                NSLog("[JobEditor] ✅ Security-scoped bookmark created - permission will persist")
            } catch {
                NSLog("[JobEditor] ⚠️ Failed to create bookmark: %@", error.localizedDescription)
                NSLog("[JobEditor] Permission granted for this session only")
            }
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
