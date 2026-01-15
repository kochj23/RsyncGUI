//
//  ScheduleManager.swift
//  RsyncGUI
//
//  Created by Jordan Koch on 1/14/26.
//

import Foundation

/// Manages launchd scheduling for sync jobs
class ScheduleManager {
    static let shared = ScheduleManager()

    private let fileManager = FileManager.default
    private var launchAgentsDir: URL {
        let homeDir = fileManager.homeDirectoryForCurrentUser
        return homeDir.appendingPathComponent("Library/LaunchAgents")
    }

    private init() {
        // Ensure LaunchAgents directory exists
        try? fileManager.createDirectory(at: launchAgentsDir, withIntermediateDirectories: true)
    }

    // MARK: - Schedule Management

    func scheduleJob(_ job: SyncJob) {
        guard let schedule = job.schedule, schedule.isEnabled else { return }

        // Build rsync command
        let command = buildRsyncCommand(for: job)

        // Generate launchd plist
        let plistContent = schedule.toLaunchdPlist(jobId: job.id.uuidString, rsyncCommand: command)

        // Write plist file
        let plistURL = launchAgentsDir.appendingPathComponent("com.jordankoch.rsyncgui.\(job.id.uuidString).plist")

        do {
            try plistContent.write(to: plistURL, atomically: true, encoding: .utf8)
            print("✅ Created launchd plist: \(plistURL.path)")

            // Load into launchd
            loadSchedule(plistURL: plistURL)
        } catch {
            print("❌ Failed to create launchd plist: \(error)")
        }
    }

    func removeSchedule(for jobId: String) {
        let plistURL = launchAgentsDir.appendingPathComponent("com.jordankoch.rsyncgui.\(jobId).plist")

        guard fileManager.fileExists(atPath: plistURL.path) else { return }

        // Unload from launchd
        unloadSchedule(plistURL: plistURL)

        // Remove plist file
        try? fileManager.removeItem(at: plistURL)
        print("✅ Removed launchd plist: \(plistURL.path)")
    }

    func updateSchedule(for job: SyncJob) {
        // Remove existing schedule
        removeSchedule(for: job.id.uuidString)

        // Create new schedule if enabled
        if let schedule = job.schedule, schedule.isEnabled {
            scheduleJob(job)
        }
    }

    // MARK: - Launchd Integration

    private func loadSchedule(plistURL: URL) {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        task.arguments = ["load", plistURL.path]

        do {
            try task.run()
            task.waitUntilExit()

            if task.terminationStatus == 0 {
                print("✅ Loaded schedule into launchd")
            } else {
                print("⚠️  launchctl load returned status: \(task.terminationStatus)")
            }
        } catch {
            print("❌ Failed to load schedule: \(error)")
        }
    }

    private func unloadSchedule(plistURL: URL) {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        task.arguments = ["unload", plistURL.path]

        do {
            try task.run()
            task.waitUntilExit()

            if task.terminationStatus == 0 {
                print("✅ Unloaded schedule from launchd")
            } else {
                print("⚠️  launchctl unload returned status: \(task.terminationStatus)")
            }
        } catch {
            print("❌ Failed to unload schedule: \(error)")
        }
    }

    // MARK: - Command Building

    private func buildRsyncCommand(for job: SyncJob) -> String {
        var args = ["/usr/bin/rsync"]

        // Add options
        args.append(contentsOf: job.options.toArguments())

        // Handle remote connections
        if job.isRemote, let host = job.remoteHost, let user = job.remoteUser {
            var sshCommand = "ssh"
            if let keyPath = job.sshKeyPath {
                sshCommand += " -i \(keyPath)"
            }
            args.append("-e '\(sshCommand)'")

            let remotePrefix = "\(user)@\(host):"
            args.append(job.source.starts(with: remotePrefix) ? job.source : job.source)
            args.append(job.destination.starts(with: remotePrefix) ? job.destination : job.destination)
        } else {
            // Expand ~ to home directory
            let homeDir = fileManager.homeDirectoryForCurrentUser.path
            let expandedSource = job.source.replacingOccurrences(of: "~", with: homeDir)
            let expandedDest = job.destination.replacingOccurrences(of: "~", with: homeDir)

            args.append(expandedSource)
            args.append(expandedDest)
        }

        // Escape for shell
        let escapedArgs = args.map { arg in
            if arg.contains(" ") {
                return "'\(arg)'"
            }
            return arg
        }

        return escapedArgs.joined(separator: " ")
    }

    // MARK: - Status Checking

    func isScheduled(jobId: String) -> Bool {
        let plistURL = launchAgentsDir.appendingPathComponent("com.jordankoch.rsyncgui.\(jobId).plist")
        return fileManager.fileExists(atPath: plistURL.path)
    }

    func getScheduleStatus(jobId: String) -> String? {
        guard isScheduled(jobId: jobId) else { return nil }

        // Query launchctl for status
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        task.arguments = ["list", "com.jordankoch.rsyncgui.\(jobId)"]

        let pipe = Pipe()
        task.standardOutput = pipe

        do {
            try task.run()
            task.waitUntilExit()

            if task.terminationStatus == 0 {
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                return String(data: data, encoding: .utf8)
            }
        } catch {
            print("❌ Failed to get schedule status: \(error)")
        }

        return nil
    }
}
