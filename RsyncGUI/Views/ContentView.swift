//
//  ContentView.swift
//  RsyncGUI
//
//  Created by Jordan Koch on 1/14/26.
//

import SwiftUI
import AppKit

/// Sidebar selection type - either a job or the history tab
enum SidebarSelection: Hashable {
    case job(UUID)
    case history
}

struct ContentView: View {
    @EnvironmentObject var jobManager: JobManager
    @State private var sidebarSelection: SidebarSelection?
    @State private var showingJobEditor = false
    @State private var showingProgress = false
    @State private var runningJobId: UUID?
    @State private var progressWindow: NSWindow?

    var body: some View {
        ZStack {
            GlassmorphicBackground()

            NavigationSplitView {
                // Sidebar - Job List with History
                JobListView(sidebarSelection: $sidebarSelection)
                    .navigationSplitViewColumnWidth(min: 250, ideal: 300)
            } detail: {
                // Detail - Job Details, History, or Welcome
                switch sidebarSelection {
                case .job(let jobId):
                    if let job = jobManager.jobs.first(where: { $0.id == jobId }) {
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
                case .history:
                    JobHistoryTabView()
                case .none:
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
                    TestProgressView(job: job)
                }
            }
        }
    }

    private func runJob(_ job: SyncJob, dryRun: Bool) {
        runningJobId = job.id

        // Open in separate window instead of sheet
        openProgressWindow(for: job, dryRun: dryRun)
    }

    private func openProgressWindow(for job: SyncJob, dryRun: Bool) {
        let progressView = SyncProgressView(job: job)
        let hostingController = NSHostingController(rootView: progressView)

        let window = NSWindow(contentViewController: hostingController)
        window.title = "Sync Progress - \(job.name)"
        window.setContentSize(NSSize(width: 1000, height: 700))
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.minSize = NSSize(width: 800, height: 600)
        window.maxSize = NSSize(width: 2000, height: 1400)
        window.center()
        window.makeKeyAndOrderFront(nil)

        progressWindow = window

        // Start the sync
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
                .foregroundColor(ModernColors.cyan)
                .shadow(color: ModernColors.cyan.opacity(0.5), radius: 20)

            VStack(spacing: 12) {
                Text("Welcome to RsyncGUI")
                    .modernHeader(size: .large)

                Text("Professional rsync management for macOS")
                    .font(.title3)
                    .foregroundColor(ModernColors.textSecondary)
            }

            VStack(alignment: .leading, spacing: 16) {
                FeatureRow(icon: "checkmark.circle.fill", title: "All rsync options", description: "100+ options organized by category", color: ModernColors.accentGreen)
                FeatureRow(icon: "clock.fill", title: "Scheduled syncs", description: "Set it and forget it with launchd integration", color: ModernColors.purple)
                FeatureRow(icon: "chart.line.uptrend.xyaxis", title: "Real-time progress", description: "Beautiful visualization for huge syncs", color: ModernColors.cyan)
                FeatureRow(icon: "key.fill", title: "SSH support", description: "Secure remote synchronization", color: ModernColors.orange)
            }
            .padding()
            .glassCard()

            Button(action: {
                jobManager.createNewJob()
            }) {
                Label("Create Your First Sync Job", systemImage: "plus.circle.fill")
                    .font(.headline)
                    .padding()
                    .frame(maxWidth: 300)
            }
            .buttonStyle(ModernButtonStyle(color: ModernColors.cyan, style: .filled))
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct FeatureRow: View {
    let icon: String
    let title: String
    let description: String
    let color: Color

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(color)
                .frame(width: 32)
                .shadow(color: color.opacity(0.5), radius: 5)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                    .foregroundColor(ModernColors.textPrimary)
                Text(description)
                    .font(.subheadline)
                    .foregroundColor(ModernColors.textSecondary)
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
