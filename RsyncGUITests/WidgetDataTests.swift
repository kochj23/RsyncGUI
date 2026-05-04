//
//  WidgetDataTests.swift
//  RsyncGUITests
//
//  Created by Jordan Koch on 5/3/26.
//
//  Tests for widget data models and the backup health score calculation.
//  WidgetDataSyncService contains private methods that cannot be tested
//  directly, so we replicate the calculation logic for verification.

import XCTest
@testable import RsyncGUI

final class WidgetDataTests: XCTestCase {

    // MARK: - Backup Health Score Calculation

    /// Replicates the private calculateBackupHealthScore() method from WidgetDataSyncService
    private func calculateBackupHealthScore(jobs: [SyncJob]) -> (score: Int, grade: String) {
        guard !jobs.isEmpty else {
            return (0, "?")
        }

        var score = 100

        // Deduct for disabled jobs
        let disabledCount = jobs.filter { !$0.isEnabled }.count
        score -= disabledCount * 5

        // Deduct for failed jobs
        let failedJobs = jobs.filter { $0.lastStatus == .failed }
        score -= failedJobs.count * 15

        // Deduct for partial success
        let partialJobs = jobs.filter { $0.lastStatus == .partialSuccess }
        score -= partialJobs.count * 10

        // Deduct for jobs never run
        let neverRun = jobs.filter { $0.lastRun == nil }
        score -= neverRun.count * 10

        // Deduct for stale backups (no sync in 7 days)
        let sevenDaysAgo = Calendar.current.date(byAdding: .day, value: -7, to: Date())!
        let staleJobs = jobs.filter { job in
            guard let lastRun = job.lastRun else { return false }
            return lastRun < sevenDaysAgo
        }
        score -= staleJobs.count * 5

        // Bonus for scheduled jobs
        let scheduledJobs = jobs.filter { $0.schedule?.isEnabled == true }
        score += min(scheduledJobs.count * 2, 10)

        // Clamp to 0-100
        score = max(0, min(100, score))

        // Calculate grade
        let grade: String
        switch score {
        case 90...100: grade = "A"
        case 80..<90: grade = "B"
        case 70..<80: grade = "C"
        case 60..<70: grade = "D"
        default: grade = "F"
        }

        return (score, grade)
    }

    func testHealthScoreEmptyJobsReturnsZero() {
        let (score, grade) = calculateBackupHealthScore(jobs: [])
        XCTAssertEqual(score, 0)
        XCTAssertEqual(grade, "?")
    }

    func testHealthScorePerfectSetup() {
        // All jobs successful, recently run, scheduled
        var job1 = SyncJob(name: "Job 1", source: "/src1", destination: "/dst1")
        job1.lastStatus = .success
        job1.lastRun = Date() // Just ran
        var schedule1 = ScheduleConfig()
        schedule1.isEnabled = true
        schedule1.frequency = .daily
        job1.schedule = schedule1

        var job2 = SyncJob(name: "Job 2", source: "/src2", destination: "/dst2")
        job2.lastStatus = .success
        job2.lastRun = Date()
        var schedule2 = ScheduleConfig()
        schedule2.isEnabled = true
        schedule2.frequency = .hourly
        job2.schedule = schedule2

        let (score, grade) = calculateBackupHealthScore(jobs: [job1, job2])

        // Both jobs: successful, recent, scheduled (+2 each, max 10)
        // No deductions
        // Score = 100 + min(4, 10) = clamped at 100
        XCTAssertGreaterThanOrEqual(score, 90, "Perfect setup should score 90+")
        XCTAssertEqual(grade, "A")
    }

    func testHealthScoreWithFailedJobs() {
        var job = SyncJob(name: "Failed", source: "/src", destination: "/dst")
        job.lastStatus = .failed
        job.lastRun = Date()

        let (score, grade) = calculateBackupHealthScore(jobs: [job])

        // Base 100 - 15 (failed) = 85
        XCTAssertEqual(score, 85)
        XCTAssertEqual(grade, "B")
    }

    func testHealthScoreWithPartialSuccess() {
        var job = SyncJob(name: "Partial", source: "/src", destination: "/dst")
        job.lastStatus = .partialSuccess
        job.lastRun = Date()

        let (score, grade) = calculateBackupHealthScore(jobs: [job])

        // Base 100 - 10 (partial) = 90
        XCTAssertEqual(score, 90)
        XCTAssertEqual(grade, "A")
    }

    func testHealthScoreWithNeverRunJobs() {
        let job = SyncJob(name: "Never Run", source: "/src", destination: "/dst")
        // lastRun is nil, lastStatus is nil

        let (score, grade) = calculateBackupHealthScore(jobs: [job])

        // Base 100 - 10 (never run) = 90
        XCTAssertEqual(score, 90)
        XCTAssertEqual(grade, "A")
    }

    func testHealthScoreWithDisabledJobs() {
        var job = SyncJob(name: "Disabled", source: "/src", destination: "/dst")
        job.isEnabled = false
        job.lastRun = Date()
        job.lastStatus = .success

        let (score, grade) = calculateBackupHealthScore(jobs: [job])

        // Base 100 - 5 (disabled) = 95
        XCTAssertEqual(score, 95)
        XCTAssertEqual(grade, "A")
    }

    func testHealthScoreWithStaleJobs() {
        var job = SyncJob(name: "Stale", source: "/src", destination: "/dst")
        job.lastStatus = .success
        job.lastRun = Calendar.current.date(byAdding: .day, value: -14, to: Date()) // 2 weeks ago

        let (score, grade) = calculateBackupHealthScore(jobs: [job])

        // Base 100 - 5 (stale) = 95
        XCTAssertEqual(score, 95)
        XCTAssertEqual(grade, "A")
    }

    func testHealthScoreWorstCase() {
        // Multiple disabled, failed, never-run jobs
        var jobs: [SyncJob] = []

        for i in 0..<5 {
            var job = SyncJob(name: "Bad Job \(i)", source: "/src\(i)", destination: "/dst\(i)")
            job.isEnabled = false
            job.lastStatus = .failed
            // Never run (lastRun = nil)
            jobs.append(job)
        }

        let (score, grade) = calculateBackupHealthScore(jobs: jobs)

        // Base 100
        // - 5 * 5 (disabled) = -25
        // - 5 * 15 (failed) = -75
        // - 5 * 10 (never run) = -50
        // = 100 - 25 - 75 - 50 = -50, clamped to 0
        XCTAssertEqual(score, 0)
        XCTAssertEqual(grade, "F")
    }

    func testHealthScoreScheduledJobsBonus() {
        var jobs: [SyncJob] = []

        for i in 0..<6 {
            var job = SyncJob(name: "Scheduled \(i)", source: "/src\(i)", destination: "/dst\(i)")
            job.lastStatus = .success
            job.lastRun = Date()
            var sched = ScheduleConfig()
            sched.isEnabled = true
            sched.frequency = .daily
            job.schedule = sched
            jobs.append(job)
        }

        let (score, _) = calculateBackupHealthScore(jobs: jobs)

        // Base 100 + min(6 * 2, 10) = 100 + 10 = clamped to 100
        XCTAssertEqual(score, 100)
    }

    func testHealthScoreBonusCappedAt10() {
        // Even with many scheduled jobs, bonus caps at 10
        var jobs: [SyncJob] = []

        for i in 0..<20 {
            var job = SyncJob(name: "Job \(i)", source: "/s\(i)", destination: "/d\(i)")
            job.lastStatus = .success
            job.lastRun = Date()
            var sched = ScheduleConfig()
            sched.isEnabled = true
            job.schedule = sched
            jobs.append(job)
        }

        let (score, _) = calculateBackupHealthScore(jobs: jobs)

        // 100 + min(20 * 2, 10) = 100 + 10 = clamped to 100
        XCTAssertEqual(score, 100)
    }

    // MARK: - Grade Boundaries

    func testGradeBoundaries() {
        // Test the exact score-to-grade boundaries
        // We construct jobs to produce specific scores

        // Score 90 -> A
        var job90 = SyncJob(name: "90", source: "/s", destination: "/d")
        job90.lastStatus = .partialSuccess
        job90.lastRun = Date()
        let (score90, grade90) = calculateBackupHealthScore(jobs: [job90])
        XCTAssertEqual(score90, 90)
        XCTAssertEqual(grade90, "A")

        // Score 85 -> B (one failed job, recently run)
        var job85 = SyncJob(name: "85", source: "/s", destination: "/d")
        job85.lastStatus = .failed
        job85.lastRun = Date()
        let (score85, grade85) = calculateBackupHealthScore(jobs: [job85])
        XCTAssertEqual(score85, 85)
        XCTAssertEqual(grade85, "B")
    }

    // MARK: - Next Run Calculation

    /// Replicates the private calculateNextRun() logic from WidgetDataSyncService
    private func calculateNextRun(for schedule: ScheduleConfig) -> Date? {
        guard schedule.isEnabled else { return nil }

        let now = Date()
        let calendar = Calendar.current

        switch schedule.frequency {
        case .manual:
            return nil

        case .hourly:
            var components = calendar.dateComponents([.year, .month, .day, .hour], from: now)
            components.minute = 0
            components.second = 0
            if let date = calendar.date(from: components) {
                return calendar.date(byAdding: .hour, value: 1, to: date)
            }

        case .daily:
            if let scheduleTime = schedule.time {
                let timeComponents = calendar.dateComponents([.hour, .minute], from: scheduleTime)
                var nextRun = calendar.date(bySettingHour: timeComponents.hour ?? 0,
                                           minute: timeComponents.minute ?? 0,
                                           second: 0,
                                           of: now)
                if let next = nextRun, next <= now {
                    nextRun = calendar.date(byAdding: .day, value: 1, to: next)
                }
                return nextRun
            }

        case .weekly, .monthly, .custom:
            return nil  // Simplified for testing
        }

        return nil
    }

    func testNextRunManualReturnsNil() {
        var config = ScheduleConfig()
        config.isEnabled = true
        config.frequency = .manual

        let nextRun = calculateNextRun(for: config)
        XCTAssertNil(nextRun, "Manual frequency should have no next run")
    }

    func testNextRunDisabledReturnsNil() {
        var config = ScheduleConfig()
        config.isEnabled = false
        config.frequency = .hourly

        let nextRun = calculateNextRun(for: config)
        XCTAssertNil(nextRun, "Disabled schedule should have no next run")
    }

    func testNextRunHourlyReturnsNextHour() {
        var config = ScheduleConfig()
        config.isEnabled = true
        config.frequency = .hourly

        let nextRun = calculateNextRun(for: config)
        XCTAssertNotNil(nextRun, "Hourly schedule should have a next run")

        if let next = nextRun {
            XCTAssertTrue(next > Date(), "Next run should be in the future")

            let calendar = Calendar.current
            let minute = calendar.component(.minute, from: next)
            XCTAssertEqual(minute, 0, "Hourly should run at minute 0")
        }
    }

    func testNextRunDailyWithTime() {
        var config = ScheduleConfig()
        config.isEnabled = true
        config.frequency = .daily

        // Set time to a future hour
        var components = DateComponents()
        components.hour = 23
        components.minute = 59
        config.time = Calendar.current.date(from: components)

        let nextRun = calculateNextRun(for: config)
        XCTAssertNotNil(nextRun, "Daily with time should produce a next run")
    }

    func testNextRunDailyWithoutTimeReturnsNil() {
        var config = ScheduleConfig()
        config.isEnabled = true
        config.frequency = .daily
        config.time = nil

        let nextRun = calculateNextRun(for: config)
        XCTAssertNil(nextRun, "Daily without time should return nil")
    }

    // MARK: - Widget Data Model Completeness

    func testWidgetSyncDataAllFieldsSettable() {
        var data = WidgetSyncData()

        data.lastSyncTime = Date()
        data.lastSyncStatus = "success"
        data.lastSyncJobName = "Test"
        data.nextScheduledSync = Date().addingTimeInterval(3600)
        data.nextScheduledJobName = "Hourly Backup"
        data.backupHealthScore = 95
        data.backupHealthGrade = "A"
        data.totalJobs = 10
        data.enabledJobs = 8

        let error = WidgetJobError(
            id: UUID(),
            jobName: "Failed Job",
            errorMessage: "Connection timeout",
            lastFailedTime: Date(),
            failureCount: 2
        )
        data.jobsWithErrors = [error]

        let recent = WidgetRecentSync(
            id: UUID(),
            jobName: "Quick Sync",
            timestamp: Date(),
            status: "success",
            filesTransferred: 10,
            bytesTransferred: 5000
        )
        data.recentSyncs = [recent]

        data.lastUpdated = Date()

        // Verify all fields are set
        XCTAssertNotNil(data.lastSyncTime)
        XCTAssertEqual(data.lastSyncStatus, "success")
        XCTAssertEqual(data.backupHealthScore, 95)
        XCTAssertEqual(data.backupHealthGrade, "A")
        XCTAssertEqual(data.totalJobs, 10)
        XCTAssertEqual(data.enabledJobs, 8)
        XCTAssertEqual(data.jobsWithErrors.count, 1)
        XCTAssertEqual(data.recentSyncs.count, 1)
        XCTAssertEqual(data.jobsWithErrors[0].errorMessage, "Connection timeout")
        XCTAssertEqual(data.recentSyncs[0].filesTransferred, 10)
    }

    func testWidgetSyncDataFullCodableRoundtrip() throws {
        var data = WidgetSyncData()
        data.lastSyncTime = Date()
        data.lastSyncStatus = "partialSuccess"
        data.lastSyncJobName = "Big Sync"
        data.nextScheduledSync = Date().addingTimeInterval(7200)
        data.nextScheduledJobName = "Next Job"
        data.backupHealthScore = 72
        data.backupHealthGrade = "C"
        data.totalJobs = 15
        data.enabledJobs = 12

        data.jobsWithErrors = [
            WidgetJobError(id: UUID(), jobName: "Bad", errorMessage: "Err", lastFailedTime: Date(), failureCount: 1)
        ]
        data.recentSyncs = [
            WidgetRecentSync(id: UUID(), jobName: "Recent", timestamp: Date(), status: "success", filesTransferred: 5, bytesTransferred: 999)
        ]
        data.lastUpdated = Date()

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let encoded = try encoder.encode(data)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(WidgetSyncData.self, from: encoded)

        XCTAssertEqual(decoded.lastSyncStatus, "partialSuccess")
        XCTAssertEqual(decoded.backupHealthScore, 72)
        XCTAssertEqual(decoded.backupHealthGrade, "C")
        XCTAssertEqual(decoded.totalJobs, 15)
        XCTAssertEqual(decoded.enabledJobs, 12)
        XCTAssertEqual(decoded.jobsWithErrors.count, 1)
        XCTAssertEqual(decoded.recentSyncs.count, 1)
        XCTAssertEqual(decoded.recentSyncs[0].bytesTransferred, 999)
    }
}
