//
//  JobDetailView.swift
//  RsyncGUI
//
//  Created by Jordan Koch on 1/14/26.
//

import SwiftUI

struct JobDetailView: View {
    let job: SyncJob
    let onRun: (Bool) -> Void
    let onEdit: () -> Void

    @State private var showingDeltaReport = false
    @State private var showingHistory = false

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Header card
                headerCard

                // Source and Destination
                pathsCard

                // Quick actions
                actionsCard

                // Statistics
                if job.totalRuns > 0 {
                    statisticsCard
                }

                // Options summary
                optionsSummaryCard

                // Schedule info
                if let schedule = job.schedule, schedule.isEnabled {
                    scheduleCard(schedule: schedule)
                }
            }
            .padding()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .textBackgroundColor))
    }

    // MARK: - Header Card

    private var headerCard: some View {
        VStack(spacing: 16) {
            HStack {
                Image(systemName: "arrow.triangle.2.circlepath.circle.fill")
                    .font(.system(size: 60))
                    .foregroundStyle(.blue.gradient)

                VStack(alignment: .leading, spacing: 8) {
                    Text(job.name)
                        .font(.title)
                        .fontWeight(.bold)

                    HStack(spacing: 16) {
                        Label(job.isEnabled ? "Enabled" : "Disabled", systemImage: job.isEnabled ? "checkmark.circle.fill" : "circle")
                            .foregroundColor(job.isEnabled ? .green : .gray)

                        if job.isRemote {
                            Label("Remote", systemImage: "network")
                                .foregroundColor(.blue)
                        } else {
                            Label("Local", systemImage: "internaldrive")
                                .foregroundColor(.purple)
                        }
                    }
                    .font(.caption)
                }

                Spacer()

                Button(action: onEdit) {
                    Label("Edit", systemImage: "pencil.circle.fill")
                        .font(.title3)
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(24)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.secondary.opacity(0.1))
        )
    }

    // MARK: - Paths Card

    private var pathsCard: some View {
        VStack(spacing: 20) {
            PathRow(
                title: "Source",
                path: job.source,
                icon: "folder.fill",
                color: .blue
            )

            Divider()

            PathRow(
                title: "Destination",
                path: job.destination,
                icon: "folder.badge.plus",
                color: .green
            )

            if job.isRemote, let host = job.remoteHost {
                Divider()

                HStack {
                    Image(systemName: "server.rack")
                        .foregroundColor(.orange)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Remote Host")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        Text("\(job.remoteUser ?? "user")@\(host)")
                            .font(.body)
                            .fontWeight(.medium)
                    }

                    Spacer()

                    if let keyPath = job.sshKeyPath {
                        HStack(spacing: 4) {
                            Image(systemName: "key.fill")
                            Text("SSH Key")
                        }
                        .font(.caption)
                        .foregroundColor(.purple)
                    }
                }
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.secondary.opacity(0.05))
        )
    }

    // MARK: - Actions Card

    private var actionsCard: some View {
        VStack(spacing: 12) {
            HStack(spacing: 16) {
                Button(action: { onRun(true) }) {
                    Label("Dry Run", systemImage: "eye.fill")
                        .frame(maxWidth: .infinity)
                        .padding()
                }
                .buttonStyle(.bordered)
                .controlSize(.large)

                Button(action: { onRun(false) }) {
                    Label("Run Now", systemImage: "play.circle.fill")
                        .frame(maxWidth: .infinity)
                        .padding()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .tint(.blue)
            }

            HStack(spacing: 16) {
                if job.lastDeltaReport != nil {
                    Button(action: { showingDeltaReport = true }) {
                        Label("View Delta Report", systemImage: "chart.bar.doc.horizontal")
                            .frame(maxWidth: .infinity)
                            .padding()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .tint(.green)
                }

                if job.totalRuns > 0 {
                    Button(action: { showingHistory = true }) {
                        Label("Execution History", systemImage: "clock.arrow.circlepath")
                            .frame(maxWidth: .infinity)
                            .padding()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .tint(.purple)
                }
            }
        }
        .sheet(isPresented: $showingDeltaReport) {
            if let report = job.lastDeltaReport {
                DeltaReportView(report: report)
            }
        }
        .sheet(isPresented: $showingHistory) {
            ExecutionHistoryView(jobId: job.id)
        }
    }

    // MARK: - Statistics Card

    private var statisticsCard: some View {
        VStack(spacing: 16) {
            HStack {
                Text("Statistics")
                    .font(.headline)
                Spacer()
            }

            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 16) {
                MiniStatCard(
                    icon: "play.circle.fill",
                    title: "Total Runs",
                    value: "\(job.totalRuns)",
                    color: .blue
                )

                MiniStatCard(
                    icon: "checkmark.circle.fill",
                    title: "Successful",
                    value: "\(job.successfulRuns)",
                    color: .green
                )

                MiniStatCard(
                    icon: "xmark.circle.fill",
                    title: "Failed",
                    value: "\(job.failedRuns)",
                    color: .red
                )
            }

            if let lastRun = job.lastRun {
                HStack {
                    Image(systemName: "clock.fill")
                        .foregroundColor(.secondary)
                    Text("Last run: \(lastRun.formatted(date: .abbreviated, time: .shortened))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                }
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.secondary.opacity(0.05))
        )
    }

    // MARK: - Options Summary

    private var optionsSummaryCard: some View {
        VStack(spacing: 16) {
            HStack {
                Text("Rsync Options")
                    .font(.headline)
                Spacer()
                Text("\(enabledOptionsCount) enabled")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            FlowLayout(spacing: 8) {
                ForEach(enabledOptions, id: \.self) { option in
                    OptionBadge(option: option)
                }
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.secondary.opacity(0.05))
        )
    }

    private var enabledOptions: [String] {
        var options: [String] = []

        if job.options.archive { options.append("Archive") }
        if job.options.verbose { options.append("Verbose") }
        if job.options.compress { options.append("Compress") }
        if job.options.delete { options.append("Delete") }
        if job.options.checksum { options.append("Checksum") }
        if job.options.partial { options.append("Partial") }
        if job.options.progress { options.append("Progress") }
        if job.options.stats { options.append("Stats") }

        return options
    }

    private var enabledOptionsCount: Int {
        var count = 0
        let opts = job.options

        if opts.archive { count += 1 }
        if opts.verbose { count += 1 }
        if opts.compress { count += 1 }
        if opts.delete { count += 1 }
        if opts.recursive { count += 1 }
        if opts.update { count += 1 }
        if opts.checksum { count += 1 }
        if opts.partial { count += 1 }
        // Add more as needed...

        return count
    }

    // MARK: - Schedule Card

    private func scheduleCard(schedule: ScheduleConfig) -> some View {
        VStack(spacing: 16) {
            HStack {
                Image(systemName: "calendar.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.purple.gradient)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Scheduled")
                        .font(.headline)

                    Text(schedule.frequency.description)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }

                Spacer()

                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
            }

            if schedule.runAtStartup {
                HStack {
                    Image(systemName: "power.circle")
                        .foregroundColor(.orange)
                    Text("Runs at system startup")
                        .font(.caption)
                    Spacer()
                }
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.purple.opacity(0.1))
        )
    }
}

// MARK: - Supporting Views

struct PathRow: View {
    let title: String
    let path: String
    let icon: String
    let color: Color

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundColor(color)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.caption)
                    .foregroundColor(.secondary)

                Text(path)
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
            }

            Spacer()
        }
    }
}

struct MiniStatCard: View {
    let icon: String
    let title: String
    let value: String
    let color: Color

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .foregroundColor(color)

            Text(value)
                .font(.title3)
                .fontWeight(.bold)

            Text(title)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(Color.secondary.opacity(0.05))
        .cornerRadius(8)
    }
}

struct OptionBadge: View {
    let option: String

    var body: some View {
        Text(option)
            .font(.caption)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(Color.blue.opacity(0.1))
            .foregroundColor(.blue)
            .cornerRadius(6)
    }
}

// Simple FlowLayout for wrapping badges
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = FlowResult(
            in: proposal.replacingUnspecifiedDimensions().width,
            subviews: subviews,
            spacing: spacing
        )
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = FlowResult(
            in: bounds.width,
            subviews: subviews,
            spacing: spacing
        )
        for (index, subview) in subviews.enumerated() {
            subview.place(at: CGPoint(x: bounds.minX + result.positions[index].x, y: bounds.minY + result.positions[index].y), proposal: .unspecified)
        }
    }

    struct FlowResult {
        var size: CGSize
        var positions: [CGPoint]

        init(in maxWidth: CGFloat, subviews: Subviews, spacing: CGFloat) {
            var positions: [CGPoint] = []
            var currentX: CGFloat = 0
            var currentY: CGFloat = 0
            var lineHeight: CGFloat = 0

            for subview in subviews {
                let size = subview.sizeThatFits(.unspecified)

                if currentX + size.width > maxWidth && currentX > 0 {
                    currentX = 0
                    currentY += lineHeight + spacing
                    lineHeight = 0
                }

                positions.append(CGPoint(x: currentX, y: currentY))
                currentX += size.width + spacing
                lineHeight = max(lineHeight, size.height)
            }

            self.positions = positions
            self.size = CGSize(width: maxWidth, height: currentY + lineHeight)
        }
    }
}
