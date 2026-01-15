//
//  DeltaReportView.swift
//  RsyncGUI
//
//  Created by Jordan Koch on 1/14/26.
//

import SwiftUI

/// View for displaying delta reports (what changed during sync)
struct DeltaReportView: View {
    let report: DeltaReport
    @Environment(\.dismiss) private var dismiss
    @State private var showingCopyConfirmation = false

    var body: some View {
        VStack(spacing: 0) {
            // Header
            header

            Divider()

            // Statistics
            statistics

            Divider()

            // Changes list
            ScrollView {
                VStack(spacing: 24) {
                    if !report.filesAdded.isEmpty {
                        changeSection(
                            title: "Added Files",
                            icon: "plus.circle.fill",
                            color: .green,
                            files: report.filesAdded
                        )
                    }

                    if !report.filesModified.isEmpty {
                        changeSection(
                            title: "Modified Files",
                            icon: "pencil.circle.fill",
                            color: .orange,
                            files: report.filesModified
                        )
                    }

                    if !report.filesDeleted.isEmpty {
                        changeSection(
                            title: "Deleted Files",
                            icon: "trash.circle.fill",
                            color: .red,
                            files: report.filesDeleted
                        )
                    }

                    if report.totalChanges == 0 {
                        VStack(spacing: 16) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 60))
                                .foregroundStyle(.green.gradient)

                            Text("No Changes")
                                .font(.title2)
                                .foregroundColor(.secondary)

                            Text("All files were already in sync")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(40)
                    }
                }
                .padding()
            }

            Divider()

            // Footer
            footer
        }
        .frame(width: 800, height: 700)
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Image(systemName: "chart.bar.doc.horizontal.fill")
                .font(.title)
                .foregroundStyle(.blue.gradient)

            VStack(alignment: .leading, spacing: 4) {
                Text("Delta Report")
                    .font(.title2)
                    .fontWeight(.bold)

                Text(report.timestamp.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            Button("Close") {
                dismiss()
            }
        }
        .padding()
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // MARK: - Statistics

    private var statistics: some View {
        HStack(spacing: 40) {
            DeltaStatCard(
                icon: "plus.circle.fill",
                title: "Added",
                count: report.filesAdded.count,
                bytes: report.bytesAdded,
                color: .green
            )

            DeltaStatCard(
                icon: "pencil.circle.fill",
                title: "Modified",
                count: report.filesModified.count,
                bytes: report.bytesModified,
                color: .orange
            )

            DeltaStatCard(
                icon: "trash.circle.fill",
                title: "Deleted",
                count: report.filesDeleted.count,
                bytes: report.bytesDeleted,
                color: .red
            )

            if report.filesSkipped > 0 {
                VStack(spacing: 8) {
                    Image(systemName: "arrow.uturn.forward.circle.fill")
                        .font(.title2)
                        .foregroundColor(.gray)

                    Text("\(report.filesSkipped)")
                        .font(.title3)
                        .fontWeight(.bold)

                    Text("Skipped")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding()
        .background(Color.secondary.opacity(0.05))
    }

    // MARK: - Change Section

    private func changeSection(title: String, icon: String, color: Color, files: [String]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: icon)
                    .foregroundColor(color)
                Text(title)
                    .font(.headline)
                Spacer()
                Text("\(files.count)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            VStack(alignment: .leading, spacing: 4) {
                ForEach(files.prefix(100), id: \.self) { file in
                    HStack(spacing: 8) {
                        Image(systemName: "doc.text.fill")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text(file)
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                    }
                }

                if files.count > 100 {
                    Text("... and \(files.count - 100) more")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .italic()
                }
            }
            .padding()
            .background(color.opacity(0.05))
            .cornerRadius(8)
        }
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            Button(action: {
                copyToClipboard(report.copyableReport)
            }) {
                Label("Copy Report", systemImage: "doc.on.doc")
            }
            .buttonStyle(.bordered)

            if showingCopyConfirmation {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                    Text("Copied!")
                        .foregroundColor(.green)
                }
                .transition(.scale)
            }

            Spacer()

            Button(action: {
                exportReport()
            }) {
                Label("Export to File", systemImage: "square.and.arrow.up")
            }
            .buttonStyle(.bordered)
        }
        .padding()
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // MARK: - Actions

    private func copyToClipboard(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        withAnimation {
            showingCopyConfirmation = true
        }

        Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            withAnimation {
                showingCopyConfirmation = false
            }
        }
    }

    private func exportReport() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.plainText]
        panel.nameFieldStringValue = "delta-report-\(report.timestamp.formatted(date: .numeric, time: .omitted)).txt"

        if panel.runModal() == .OK, let url = panel.url {
            try? report.copyableReport.write(to: url, atomically: true, encoding: .utf8)
        }
    }
}

// MARK: - Delta Stat Card

struct DeltaStatCard: View {
    let icon: String
    let title: String
    let count: Int
    let bytes: Int64
    let color: Color

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(color)

            Text("\(count)")
                .font(.title2)
                .fontWeight(.bold)
                .foregroundStyle(color.gradient)

            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)

            if bytes > 0 {
                Text(ByteCountFormatter.string(fromByteCount: bytes, countStyle: .binary))
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(Color.secondary.opacity(0.05))
        .cornerRadius(8)
    }
}
