//
//  ContentView.swift
//  RsyncGUI
//
//  Created by Jordan Koch on 1/14/26.
//

import SwiftUI

struct ContentView: View {
    @EnvironmentObject var jobManager: JobManager
    @State private var selectedJobId: UUID?
    @State private var showingJobEditor = false
    @State private var showingProgress = false
    @State private var runningJobId: UUID?

    var body: some View {
        NavigationSplitView {
            // Sidebar - Job List
            JobListView(selectedJobId: $selectedJobId)
                .navigationSplitViewColumnWidth(min: 250, ideal: 300)
        } detail: {
            // Detail - Job Details or Welcome
            if let jobId = selectedJobId,
               let job = jobManager.jobs.first(where: { $0.id == jobId }) {
                JobDetailView(
                    job: job,
                    onRun: { dryRun in
                        runJob(job, dryRun: dryRun)
                    },
                    onEdit: {
                        jobManager.selectedJob = job
                        showingJobEditor = true
                    }
                )
            } else {
                WelcomeView()
            }
        }
        .sheet(isPresented: $showingJobEditor) {
            if let job = jobManager.selectedJob {
                JobEditorView(job: job, isPresented: $showingJobEditor)
            }
        }
        .sheet(isPresented: $showingProgress) {
            if let jobId = runningJobId,
               let job = jobManager.jobs.first(where: { $0.id == jobId }) {
                SyncProgressView(job: job)
            }
        }
    }

    private func runJob(_ job: SyncJob, dryRun: Bool) {
        runningJobId = job.id
        showingProgress = true

        Task {
            do {
                _ = try await jobManager.executeJob(job, dryRun: dryRun)
            } catch {
                print("Job execution failed: \(error)")
            }
        }
    }
}

// MARK: - Welcome View

struct WelcomeView: View {
    @EnvironmentObject var jobManager: JobManager

    var body: some View {
        VStack(spacing: 30) {
            Image(systemName: "arrow.triangle.2.circlepath.circle.fill")
                .font(.system(size: 80))
                .foregroundStyle(.blue.gradient)

            VStack(spacing: 12) {
                Text("Welcome to RsyncGUI")
                    .font(.largeTitle)
                    .fontWeight(.bold)

                Text("Professional rsync management for macOS")
                    .font(.title3)
                    .foregroundColor(.secondary)
            }

            VStack(alignment: .leading, spacing: 16) {
                FeatureRow(icon: "checkmark.circle.fill", title: "All rsync options", description: "100+ options organized by category")
                FeatureRow(icon: "clock.fill", title: "Scheduled syncs", description: "Set it and forget it with launchd integration")
                FeatureRow(icon: "chart.line.uptrend.xyaxis", title: "Real-time progress", description: "Beautiful visualization for huge syncs")
                FeatureRow(icon: "key.fill", title: "SSH support", description: "Secure remote synchronization")
            }
            .padding()
            .background(Color.secondary.opacity(0.1))
            .cornerRadius(12)

            Button(action: {
                jobManager.createNewJob()
            }) {
                Label("Create Your First Sync Job", systemImage: "plus.circle.fill")
                    .font(.headline)
                    .padding()
                    .frame(maxWidth: 300)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct FeatureRow: View {
    let icon: String
    let title: String
    let description: String

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(.blue)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                Text(description)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            Spacer()
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(JobManager.shared)
        .frame(width: 1000, height: 700)
}
