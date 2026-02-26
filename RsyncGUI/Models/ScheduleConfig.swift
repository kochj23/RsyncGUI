//
//  ScheduleConfig.swift
//  RsyncGUI
//
//  Created by Jordan Koch on 1/14/26.
//

import Foundation

/// Schedule configuration for automated job execution
struct ScheduleConfig: Codable {
    var isEnabled: Bool
    var frequency: ScheduleFrequency
    var time: Date? // For daily/weekly/monthly
    var dayOfWeek: Int? // 0-6 for weekly (Sunday = 0)
    var dayOfMonth: Int? // 1-31 for monthly
    var customCron: String? // For advanced scheduling
    var runAtStartup: Bool
    var runAfterIdleMinutes: Int?

    init() {
        self.isEnabled = false
        self.frequency = .manual
        self.runAtStartup = false
    }
}

/// Schedule frequency options
enum ScheduleFrequency: String, Codable, CaseIterable {
    case manual = "Manual"
    case hourly = "Hourly"
    case daily = "Daily"
    case weekly = "Weekly"
    case monthly = "Monthly"
    case custom = "Custom (cron)"

    var description: String {
        rawValue
    }
}

/// Extension for launchd plist generation
extension ScheduleConfig {
    /// Generate launchd plist configuration using PropertyListSerialization
    /// to prevent XML injection from user-supplied values.
    func toLaunchdPlist(jobId: String, rsyncCommand: String) -> String {
        var dict: [String: Any] = [
            "Label": "com.jordankoch.rsyncgui.\(jobId)",
            "ProgramArguments": ["/bin/sh", "-c", rsyncCommand],
            "RunAtLoad": runAtStartup
        ]

        // Add schedule based on frequency
        switch frequency {
        case .hourly:
            dict["StartCalendarInterval"] = ["Minute": 0]

        case .daily:
            if let scheduleTime = time {
                let hour = Calendar.current.component(.hour, from: scheduleTime)
                let minute = Calendar.current.component(.minute, from: scheduleTime)
                dict["StartCalendarInterval"] = ["Hour": hour, "Minute": minute]
            }

        case .weekly:
            if let scheduleTime = time, let day = dayOfWeek {
                let hour = Calendar.current.component(.hour, from: scheduleTime)
                let minute = Calendar.current.component(.minute, from: scheduleTime)
                dict["StartCalendarInterval"] = ["Weekday": day, "Hour": hour, "Minute": minute]
            }

        case .monthly:
            if let scheduleTime = time, let day = dayOfMonth {
                let hour = Calendar.current.component(.hour, from: scheduleTime)
                let minute = Calendar.current.component(.minute, from: scheduleTime)
                dict["StartCalendarInterval"] = ["Day": day, "Hour": hour, "Minute": minute]
            }

        case .custom, .manual:
            break
        }

        if runAfterIdleMinutes != nil {
            dict["StartOnMount"] = false
            dict["LowPriorityIO"] = true
            dict["Nice"] = 10
        }

        // Use PropertyListSerialization for safe XML generation
        guard let data = try? PropertyListSerialization.data(
            fromPropertyList: dict,
            format: .xml,
            options: 0
        ), let xml = String(data: data, encoding: .utf8) else {
            NSLog("[ScheduleConfig] Failed to serialize plist for job %@", jobId)
            return ""
        }

        return xml
    }
}
