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
        ZStack {
            GlassmorphicBackground()

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
        }
    }

    // MARK: - Header Card

    private var headerCard: some View {
        VStack(spacing: 16) {
            HStack {
                Image(systemName: "arrow.triangle.2.circlepath.circle.fill")
                    .font(.system(size: 60))
                    .foregroundColor(ModernColors.cyan)
                    .shadow(color: ModernColors.cyan.opacity(0.5), radius: 15)

                VStack(alignment: .leading, spacing: 8) {
                    Text(job.name)
                        .modernHeader(size: .medium)

                    HStack(spacing: 16) {
                        Label(job.isEnabled ? "Enabled" : "Disabled", systemImage: job.isEnabled ? "checkmark.circle.fill" : "circle")
                            .foregroundColor(job.isEnabled ? ModernColors.accentGreen : ModernColors.textTertiary)

                        if job.isRemote {
                            Label("Remote", systemImage: "network")
                                .foregroundColor(ModernColors.cyan)
                        } else {
                            Label("Local", systemImage: "internaldrive")
                                .foregroundColor(ModernColors.purple)
                        }
                    }
                    .font(.caption)
                }

                Spacer()

                Button(action: onEdit) {
                    Label("Edit", systemImage: "pencil.circle.fill")
                        .font(.title3)
                }
                .buttonStyle(ModernButtonStyle(color: ModernColors.cyan, style: .filled))
            }
        }
        .padding(24)
        .glassCard(prominent: true)
    }

    // MARK: - Paths Card

    private var pathsCard: some View {
        VStack(spacing: 20) {
            PathRow(
                title: "Source",
                path: job.source,
                icon: "folder.fill",
                color: ModernColors.cyan
            )

            Divider()

            PathRow(
                title: "Destination",
                path: job.destination,
                icon: "folder.badge.plus",
                color: ModernColors.accentGreen
            )

            if job.isRemote, let host = job.remoteHost {
                Divider()

                HStack {
                    Image(systemName: "server.rack")
                        .foregroundColor(ModernColors.orange)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Remote Host")
                            .font(.caption)
                            .foregroundColor(ModernColors.textSecondary)

                        Text("\(job.remoteUser ?? "user")@\(host)")
                            .font(.body)
                            .fontWeight(.medium)
                            .foregroundColor(ModernColors.textPrimary)
                    }

                    Spacer()

                    if let keyPath = job.sshKeyPath {
                        HStack(spacing: 4) {
                            Image(systemName: "key.fill")
                                .foregroundColor(ModernColors.purple)
                            Text("SSH Key")
                                .foregroundColor(ModernColors.purple)
                        }
                        .font(.caption)
                    }
                }
            }
        }
        .padding(20)
        .glassCard()
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
                .buttonStyle(ModernButtonStyle(color: ModernColors.purple, style: .outlined))

                Button(action: { onRun(false) }) {
                    Label("Run Now", systemImage: "play.circle.fill")
                        .frame(maxWidth: .infinity)
                        .padding()
                }
                .buttonStyle(ModernButtonStyle(color: ModernColors.cyan, style: .filled))
            }

            HStack(spacing: 16) {
                if job.lastDeltaReport != nil {
                    Button(action: { showingDeltaReport = true }) {
                        Label("View Delta Report", systemImage: "chart.bar.doc.horizontal")
                            .frame(maxWidth: .infinity)
                            .padding()
                    }
                    .buttonStyle(ModernButtonStyle(color: ModernColors.accentGreen, style: .outlined))
                }

                if job.totalRuns > 0 {
                    Button(action: { showingHistory = true }) {
                        Label("Execution History", systemImage: "clock.arrow.circlepath")
                            .frame(maxWidth: .infinity)
                            .padding()
                    }
                    .buttonStyle(ModernButtonStyle(color: ModernColors.purple, style: .outlined))
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
                    .modernHeader(size: .small)
                Spacer()
            }

            HStack(spacing: 30) {
                VStack(spacing: 8) {
                    CircularGauge(
                        value: Double(job.successfulRuns) / max(Double(job.totalRuns), 1.0) * 100,
                        color: ModernColors.accentGreen,
                        size: 80,
                        lineWidth: 8,
                        showValue: false
                    )
                    Text("\(job.successfulRuns)")
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(ModernColors.accentGreen)
                    Text("Successful")
                        .font(.caption)
                        .foregroundColor(ModernColors.textSecondary)
                }

                VStack(spacing: 8) {
                    CircularGauge(
                        value: 100,
                        color: ModernColors.cyan,
                        size: 80,
                        lineWidth: 8,
                        showValue: false
                    )
                    Text("\(job.totalRuns)")
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(ModernColors.cyan)
                    Text("Total Runs")
                        .font(.caption)
                        .foregroundColor(ModernColors.textSecondary)
                }

                VStack(spacing: 8) {
                    CircularGauge(
                        value: Double(job.failedRuns) / max(Double(job.totalRuns), 1.0) * 100,
                        color: ModernColors.statusCritical,
                        size: 80,
                        lineWidth: 8,
                        showValue: false
                    )
                    Text("\(job.failedRuns)")
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(ModernColors.statusCritical)
                    Text("Failed")
                        .font(.caption)
                        .foregroundColor(ModernColors.textSecondary)
                }
            }

            if let lastRun = job.lastRun {
                HStack {
                    Image(systemName: "clock.fill")
                        .foregroundColor(ModernColors.purple)
                    Text("Last run: \(lastRun.formatted(date: .abbreviated, time: .shortened))")
                        .font(.caption)
                        .foregroundColor(ModernColors.textSecondary)
                    Spacer()
                }
            }
        }
        .padding(20)
        .glassCard()
    }

    // MARK: - Options Summary

    private var optionsSummaryCard: some View {
        VStack(spacing: 16) {
            HStack {
                Text("Rsync Options")
                    .modernHeader(size: .small)
                Spacer()
                Text("\(enabledOptionsCount) enabled")
                    .font(.caption)
                    .foregroundColor(ModernColors.textSecondary)
            }

            FlowLayout(spacing: 8) {
                ForEach(enabledOptions, id: \.self) { option in
                    OptionBadge(option: option)
                }
            }
        }
        .padding(20)
        .glassCard()
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
                    .foregroundColor(ModernColors.purple)
                    .shadow(color: ModernColors.purple.opacity(0.5), radius: 8)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Scheduled")
                        .font(.headline)
                        .foregroundColor(ModernColors.textPrimary)

                    Text(schedule.frequency.description)
                        .font(.subheadline)
                        .foregroundColor(ModernColors.textSecondary)
                }

                Spacer()

                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(ModernColors.accentGreen)
            }

            if schedule.runAtStartup {
                HStack {
                    Image(systemName: "power.circle")
                        .foregroundColor(ModernColors.orange)
                    Text("Runs at system startup")
                        .font(.caption)
                        .foregroundColor(ModernColors.textSecondary)
                    Spacer()
                }
            }
        }
        .padding(20)
        .glassCard(prominent: true)
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
                .shadow(color: color.opacity(0.5), radius: 5)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.caption)
                    .foregroundColor(ModernColors.textSecondary)

                Text(path)
                    .font(.system(.body, design: .monospaced))
                    .foregroundColor(ModernColors.textPrimary)
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
                .shadow(color: color.opacity(0.5), radius: 5)

            Text(value)
                .font(.title3)
                .fontWeight(.bold)
                .foregroundColor(ModernColors.textPrimary)

            Text(title)
                .font(.caption2)
                .foregroundColor(ModernColors.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .glassCard()
    }
}

struct OptionBadge: View {
    let option: String

    var body: some View {
        Text(option)
            .font(.caption)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(ModernColors.cyan.opacity(0.2))
            .foregroundColor(ModernColors.cyan)
            .cornerRadius(6)
            .shadow(color: ModernColors.cyan.opacity(0.3), radius: 3)
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
