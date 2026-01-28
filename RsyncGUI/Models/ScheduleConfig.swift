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
    /// Generate launchd plist configuration
    func toLaunchdPlist(jobId: String, rsyncCommand: String) -> String {
        var plist = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>Label</key>
            <string>com.jordankoch.rsyncgui.\(jobId)</string>
            <key>ProgramArguments</key>
            <array>
                <string>/bin/sh</string>
                <string>-c</string>
                <string>\(rsyncCommand)</string>
            </array>
            <key>RunAtLoad</key>
            <\(runAtStartup ? "true" : "false")/>
        """

        // Add schedule based on frequency
        switch frequency {
        case .hourly:
            plist += """

                <key>StartCalendarInterval</key>
                <dict>
                    <key>Minute</key>
                    <integer>0</integer>
                </dict>
            """

        case .daily:
            if let scheduleTime = time {
                let hour = Calendar.current.component(.hour, from: scheduleTime)
                let minute = Calendar.current.component(.minute, from: scheduleTime)
                plist += """

                    <key>StartCalendarInterval</key>
                    <dict>
                        <key>Hour</key>
                        <integer>\(hour)</integer>
                        <key>Minute</key>
                        <integer>\(minute)</integer>
                    </dict>
                """
            }

        case .weekly:
            if let scheduleTime = time, let day = dayOfWeek {
                let hour = Calendar.current.component(.hour, from: scheduleTime)
                let minute = Calendar.current.component(.minute, from: scheduleTime)
                plist += """

                    <key>StartCalendarInterval</key>
                    <dict>
                        <key>Weekday</key>
                        <integer>\(day)</integer>
                        <key>Hour</key>
                        <integer>\(hour)</integer>
                        <key>Minute</key>
                        <integer>\(minute)</integer>
                    </dict>
                """
            }

        case .monthly:
            if let scheduleTime = time, let day = dayOfMonth {
                let hour = Calendar.current.component(.hour, from: scheduleTime)
                let minute = Calendar.current.component(.minute, from: scheduleTime)
                plist += """

                    <key>StartCalendarInterval</key>
                    <dict>
                        <key>Day</key>
                        <integer>\(day)</integer>
                        <key>Hour</key>
                        <integer>\(hour)</integer>
                        <key>Minute</key>
                        <integer>\(minute)</integer>
                    </dict>
                """
            }

        case .custom:
            // Custom cron expressions require different handling
            // Would need to convert to StartCalendarInterval format
            break

        case .manual:
            // No schedule
            break
        }

        if runAfterIdleMinutes != nil {
            plist += """

                <key>StartOnMount</key>
                <false/>
                <key>LowPriorityIO</key>
                <true/>
                <key>Nice</key>
                <integer>10</integer>
            """
        }

        plist += """

        </dict>
        </plist>
        """

        return plist
    }
}
