//
//  JobListView.swift
//  RsyncGUI
//
//  Created by Jordan Koch on 1/14/26.
//

import SwiftUI

struct JobListView: View {
    @EnvironmentObject var jobManager: JobManager
    @Binding var selectedJobId: UUID?

    var body: some View {
        List(selection: $selectedJobId) {
            Section {
                ForEach(jobManager.jobs) { job in
                    JobRow(job: job)
                        .tag(job.id)
                        .contextMenu {
                            Button("Run Now") {
                                runJob(job)
                            }

                            Button("Edit") {
                                jobManager.selectedJob = job
                                jobManager.isCreatingNewJob = true
                            }

                            Button("Duplicate") {
                                jobManager.duplicateJob(job)
                            }

                            Divider()

                            Button("Delete", role: .destructive) {
                                jobManager.deleteJob(job)
                            }
                        }
                }
                .onDelete(perform: deleteJobs)
            } header: {
                HStack {
                    Text("Sync Jobs (\(jobManager.jobs.count))")
                    Spacer()
                    Button(action: {
                        jobManager.createNewJob()
                    }) {
                        Image(systemName: "plus")
                    }
                    .buttonStyle(.borderless)
                }
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("RsyncGUI")
    }

    private func deleteJobs(at offsets: IndexSet) {
        for index in offsets {
            jobManager.deleteJob(jobManager.jobs[index])
        }
    }

    private func runJob(_ job: SyncJob) {
        Task {
            do {
                _ = try await jobManager.executeJob(job)
            } catch {
                print("Failed to run job: \(error)")
            }
        }
    }
}

// MARK: - Job Row

struct JobRow: View {
    let job: SyncJob
    @EnvironmentObject var jobManager: JobManager

    var body: some View {
        HStack(spacing: 12) {
            // Status indicator
            Circle()
                .fill(job.isEnabled ? Color.green : Color.gray)
                .frame(width: 8, height: 8)

            VStack(alignment: .leading, spacing: 4) {
                Text(job.name)
                    .font(.headline)

                HStack(spacing: 8) {
                    if let lastRun = job.lastRun {
                        HStack(spacing: 4) {
                            Image(systemName: statusIcon)
                                .foregroundColor(statusColor)
                            Text(lastRun.formatted(date: .abbreviated, time: .shortened))
                                .font(.caption)
                        }
                    } else {
                        Text("Never run")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    if let schedule = job.schedule, schedule.isEnabled {
                        HStack(spacing: 4) {
                            Image(systemName: "clock.fill")
                            Text(schedule.frequency.rawValue)
                        }
                        .font(.caption)
                        .foregroundColor(.blue)
                    }
                }
            }

            Spacer()

            // Run count badge
            if job.totalRuns > 0 {
                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(job.successfulRuns)")
                        .font(.caption2)
                        .foregroundColor(.green)
                    if job.failedRuns > 0 {
                        Text("\(job.failedRuns)")
                            .font(.caption2)
                            .foregroundColor(.red)
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }

    private var statusIcon: String {
        switch job.lastStatus {
        case .success: return "checkmark.circle.fill"
        case .failed: return "xmark.circle.fill"
        case .partialSuccess: return "exclamationmark.circle.fill"
        case .cancelled: return "stop.circle.fill"
        case .none: return "circle.fill"
        }
    }

    private var statusColor: Color {
        switch job.lastStatus {
        case .success: return .green
        case .failed: return .red
        case .partialSuccess: return .orange
        case .cancelled: return .gray
        case .none: return .secondary
        }
    }
}
