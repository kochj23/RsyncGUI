//
//  JobManager.swift
//  RsyncGUI
//
//  Created by Jordan Koch on 1/14/26.
//

import Foundation
import Combine

/// Manages all sync jobs - create, edit, delete, execute
@MainActor
class JobManager: ObservableObject {
    static let shared = JobManager()

    @Published var jobs: [SyncJob] = []
    @Published var selectedJob: SyncJob?
    @Published var isCreatingNewJob = false

    private let storageURL: URL
    private let fileManager = FileManager.default

    private init() {
        // Store jobs in Application Support
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        storageURL = appSupport.appendingPathComponent("RsyncGUI", isDirectory: true)

        // Create directory if needed
        try? fileManager.createDirectory(at: storageURL, withIntermediateDirectories: true)

        // Load saved jobs
        loadJobs()
    }

    // MARK: - Job Management

    func createNewJob() {
        let newJob = SyncJob(
            name: "New Sync Job",
            source: "",
            destination: ""
        )
        jobs.append(newJob)
        selectedJob = newJob
        isCreatingNewJob = true
        saveJobs()
    }

    func updateJob(_ job: SyncJob) {
        if let index = jobs.firstIndex(where: { $0.id == job.id }) {
            jobs[index] = job
            saveJobs()
        }
    }

    func deleteJob(_ job: SyncJob) {
        jobs.removeAll { $0.id == job.id }
        if selectedJob?.id == job.id {
            selectedJob = nil
        }
        saveJobs()

        // Remove launchd schedule if exists
        ScheduleManager.shared.removeSchedule(for: job.id.uuidString)
    }

    func duplicateJob(_ job: SyncJob) {
        var duplicate = job
        duplicate.id = UUID()
        duplicate.name = "\(job.name) (Copy)"
        duplicate.created = Date()
        duplicate.lastRun = nil
        duplicate.lastStatus = nil
        duplicate.totalRuns = 0
        duplicate.successfulRuns = 0
        duplicate.failedRuns = 0
        jobs.append(duplicate)
        saveJobs()
    }

    // MARK: - Execution

    func executeJob(_ job: SyncJob, dryRun: Bool = false) async throws -> ExecutionResult {
        var mutableJob = job
        mutableJob.totalRuns += 1

        let executor = RsyncExecutor()
        let result = try await executor.execute(job: job, dryRun: dryRun)

        // Update job statistics
        if result.status == .success {
            mutableJob.successfulRuns += 1
        } else if result.status == .failed {
            mutableJob.failedRuns += 1
        }
        mutableJob.lastRun = result.startTime
        mutableJob.lastStatus = result.status

        updateJob(mutableJob)

        return result
    }

    // MARK: - Persistence

    private func loadJobs() {
        let jobsFile = storageURL.appendingPathComponent("jobs.json")

        guard fileManager.fileExists(atPath: jobsFile.path),
              let data = try? Data(contentsOf: jobsFile),
              let loadedJobs = try? JSONDecoder().decode([SyncJob].self, from: data) else {
            // Create sample job for first launch
            createSampleJob()
            return
        }

        jobs = loadedJobs
    }

    func saveJobs() {
        let jobsFile = storageURL.appendingPathComponent("jobs.json")

        guard let data = try? JSONEncoder().encode(jobs) else {
            print("Failed to encode jobs")
            return
        }

        try? data.write(to: jobsFile, options: .atomic)
    }

    private func createSampleJob() {
        let sampleJob = SyncJob(
            name: "Example: Documents Backup",
            source: "~/Documents",
            destination: "/Volumes/Backup/Documents"
        )
        jobs = [sampleJob]
        saveJobs()
    }

    // MARK: - Scheduling

    func updateSchedule(for job: SyncJob) {
        guard let schedule = job.schedule, schedule.isEnabled else {
            // Remove schedule if disabled
            ScheduleManager.shared.removeSchedule(for: job.id.uuidString)
            return
        }

        // Create/update launchd schedule
        ScheduleManager.shared.scheduleJob(job)
    }
}
