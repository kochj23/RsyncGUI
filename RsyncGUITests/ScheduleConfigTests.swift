//
//  ScheduleConfigTests.swift
//  RsyncGUITests
//
//  Created by Jordan Koch on 4/21/26.
//

import XCTest
@testable import RsyncGUI

final class ScheduleConfigTests: XCTestCase {

    // MARK: - Default Initialization

    func testDefaultScheduleConfigIsDisabledAndManual() {
        let config = ScheduleConfig()

        XCTAssertFalse(config.isEnabled)
        XCTAssertEqual(config.frequency, .manual)
        XCTAssertFalse(config.runAtStartup)
        XCTAssertNil(config.time)
        XCTAssertNil(config.dayOfWeek)
        XCTAssertNil(config.dayOfMonth)
        XCTAssertNil(config.customCron)
        XCTAssertNil(config.runAfterIdleMinutes)
    }

    // MARK: - Hourly Schedule Plist

    func testHourlyScheduleGeneratesMinuteZeroInterval() {
        var config = ScheduleConfig()
        config.isEnabled = true
        config.frequency = .hourly

        let plist = config.toLaunchdPlist(jobId: "test-job-1", rsyncCommand: "/usr/bin/rsync -a /src/ /dst/")

        XCTAssertFalse(plist.isEmpty, "Plist should not be empty")
        XCTAssertTrue(plist.contains("com.jordankoch.rsyncgui.test-job-1"), "Should contain job label")
        XCTAssertTrue(plist.contains("StartCalendarInterval"), "Hourly should have StartCalendarInterval")
        XCTAssertTrue(plist.contains("<key>Minute</key>"), "Hourly should set Minute key")
    }

    func testHourlyScheduleParsesAsValidPlist() throws {
        var config = ScheduleConfig()
        config.isEnabled = true
        config.frequency = .hourly

        let plist = config.toLaunchdPlist(jobId: "test-hourly", rsyncCommand: "echo test")

        let data = plist.data(using: .utf8)!
        let parsed = try PropertyListSerialization.propertyList(from: data, format: nil) as! [String: Any]

        XCTAssertEqual(parsed["Label"] as? String, "com.jordankoch.rsyncgui.test-hourly")

        let interval = parsed["StartCalendarInterval"] as? [String: Int]
        XCTAssertNotNil(interval)
        XCTAssertEqual(interval?["Minute"], 0)
    }

    // MARK: - Daily Schedule Plist

    func testDailyScheduleGeneratesHourAndMinute() throws {
        var config = ScheduleConfig()
        config.isEnabled = true
        config.frequency = .daily

        // Create a date for 3:30 AM
        var components = DateComponents()
        components.hour = 3
        components.minute = 30
        config.time = Calendar.current.date(from: components)

        let plist = config.toLaunchdPlist(jobId: "daily-backup", rsyncCommand: "/usr/bin/rsync -a /src /dst")

        XCTAssertFalse(plist.isEmpty)

        let data = plist.data(using: .utf8)!
        let parsed = try PropertyListSerialization.propertyList(from: data, format: nil) as! [String: Any]

        let interval = parsed["StartCalendarInterval"] as? [String: Int]
        XCTAssertNotNil(interval, "Daily schedule should have calendar interval")
        XCTAssertEqual(interval?["Hour"], 3)
        XCTAssertEqual(interval?["Minute"], 30)
    }

    func testDailyScheduleWithoutTimeHasNoInterval() throws {
        var config = ScheduleConfig()
        config.isEnabled = true
        config.frequency = .daily
        config.time = nil  // No time set

        let plist = config.toLaunchdPlist(jobId: "no-time", rsyncCommand: "echo test")

        let data = plist.data(using: .utf8)!
        let parsed = try PropertyListSerialization.propertyList(from: data, format: nil) as! [String: Any]

        // Without a time, the daily case won't add StartCalendarInterval
        XCTAssertNil(parsed["StartCalendarInterval"],
                     "Daily without time should not add StartCalendarInterval")
    }

    // MARK: - Weekly Schedule Plist

    func testWeeklyScheduleGeneratesWeekdayHourMinute() throws {
        var config = ScheduleConfig()
        config.isEnabled = true
        config.frequency = .weekly
        config.dayOfWeek = 1  // Monday

        var components = DateComponents()
        components.hour = 22
        components.minute = 0
        config.time = Calendar.current.date(from: components)

        let plist = config.toLaunchdPlist(jobId: "weekly-backup", rsyncCommand: "/usr/bin/rsync -a /src /dst")

        let data = plist.data(using: .utf8)!
        let parsed = try PropertyListSerialization.propertyList(from: data, format: nil) as! [String: Any]

        let interval = parsed["StartCalendarInterval"] as? [String: Int]
        XCTAssertNotNil(interval)
        XCTAssertEqual(interval?["Weekday"], 1)
        XCTAssertEqual(interval?["Hour"], 22)
        XCTAssertEqual(interval?["Minute"], 0)
    }

    func testWeeklyScheduleSundayIsZero() throws {
        var config = ScheduleConfig()
        config.isEnabled = true
        config.frequency = .weekly
        config.dayOfWeek = 0  // Sunday

        var components = DateComponents()
        components.hour = 6
        components.minute = 15
        config.time = Calendar.current.date(from: components)

        let plist = config.toLaunchdPlist(jobId: "sunday-backup", rsyncCommand: "echo test")

        let data = plist.data(using: .utf8)!
        let parsed = try PropertyListSerialization.propertyList(from: data, format: nil) as! [String: Any]

        let interval = parsed["StartCalendarInterval"] as? [String: Int]
        XCTAssertEqual(interval?["Weekday"], 0, "Sunday should be weekday 0")
    }

    func testWeeklyScheduleWithoutTimeOrDayHasNoInterval() throws {
        var config = ScheduleConfig()
        config.isEnabled = true
        config.frequency = .weekly
        config.time = nil
        config.dayOfWeek = nil

        let plist = config.toLaunchdPlist(jobId: "incomplete-weekly", rsyncCommand: "echo test")

        let data = plist.data(using: .utf8)!
        let parsed = try PropertyListSerialization.propertyList(from: data, format: nil) as! [String: Any]

        XCTAssertNil(parsed["StartCalendarInterval"],
                     "Weekly without time and day should not add calendar interval")
    }

    // MARK: - Monthly Schedule Plist

    func testMonthlyScheduleGeneratesDayHourMinute() throws {
        var config = ScheduleConfig()
        config.isEnabled = true
        config.frequency = .monthly
        config.dayOfMonth = 15

        var components = DateComponents()
        components.hour = 2
        components.minute = 0
        config.time = Calendar.current.date(from: components)

        let plist = config.toLaunchdPlist(jobId: "monthly-backup", rsyncCommand: "/usr/bin/rsync -a /src /dst")

        let data = plist.data(using: .utf8)!
        let parsed = try PropertyListSerialization.propertyList(from: data, format: nil) as! [String: Any]

        let interval = parsed["StartCalendarInterval"] as? [String: Int]
        XCTAssertNotNil(interval)
        XCTAssertEqual(interval?["Day"], 15)
        XCTAssertEqual(interval?["Hour"], 2)
        XCTAssertEqual(interval?["Minute"], 0)
    }

    func testMonthlyScheduleFirstDayOfMonth() throws {
        var config = ScheduleConfig()
        config.isEnabled = true
        config.frequency = .monthly
        config.dayOfMonth = 1

        var components = DateComponents()
        components.hour = 0
        components.minute = 0
        config.time = Calendar.current.date(from: components)

        let plist = config.toLaunchdPlist(jobId: "first-of-month", rsyncCommand: "echo test")

        let data = plist.data(using: .utf8)!
        let parsed = try PropertyListSerialization.propertyList(from: data, format: nil) as! [String: Any]

        let interval = parsed["StartCalendarInterval"] as? [String: Int]
        XCTAssertEqual(interval?["Day"], 1)
        XCTAssertEqual(interval?["Hour"], 0)
        XCTAssertEqual(interval?["Minute"], 0)
    }

    func testMonthlyScheduleLastDayOfMonth() throws {
        var config = ScheduleConfig()
        config.isEnabled = true
        config.frequency = .monthly
        config.dayOfMonth = 31

        var components = DateComponents()
        components.hour = 23
        components.minute = 59
        config.time = Calendar.current.date(from: components)

        let plist = config.toLaunchdPlist(jobId: "end-of-month", rsyncCommand: "echo test")

        let data = plist.data(using: .utf8)!
        let parsed = try PropertyListSerialization.propertyList(from: data, format: nil) as! [String: Any]

        let interval = parsed["StartCalendarInterval"] as? [String: Int]
        XCTAssertEqual(interval?["Day"], 31)
        XCTAssertEqual(interval?["Hour"], 23)
        XCTAssertEqual(interval?["Minute"], 59)
    }

    // MARK: - Manual and Custom Frequencies

    func testManualFrequencyProducesNoInterval() throws {
        var config = ScheduleConfig()
        config.isEnabled = true
        config.frequency = .manual

        let plist = config.toLaunchdPlist(jobId: "manual-job", rsyncCommand: "echo test")

        let data = plist.data(using: .utf8)!
        let parsed = try PropertyListSerialization.propertyList(from: data, format: nil) as! [String: Any]

        XCTAssertNil(parsed["StartCalendarInterval"],
                     "Manual frequency should not add any calendar interval")
    }

    func testCustomFrequencyProducesNoInterval() throws {
        var config = ScheduleConfig()
        config.isEnabled = true
        config.frequency = .custom
        config.customCron = "*/15 * * * *"

        let plist = config.toLaunchdPlist(jobId: "custom-job", rsyncCommand: "echo test")

        let data = plist.data(using: .utf8)!
        let parsed = try PropertyListSerialization.propertyList(from: data, format: nil) as! [String: Any]

        // Custom cron is stored but not translated to launchd interval
        XCTAssertNil(parsed["StartCalendarInterval"],
                     "Custom frequency should not add calendar interval (cron not translated)")
    }

    // MARK: - RunAtLoad / RunAtStartup

    func testRunAtStartupSetsRunAtLoadTrue() throws {
        var config = ScheduleConfig()
        config.isEnabled = true
        config.frequency = .manual
        config.runAtStartup = true

        let plist = config.toLaunchdPlist(jobId: "startup-job", rsyncCommand: "echo test")

        let data = plist.data(using: .utf8)!
        let parsed = try PropertyListSerialization.propertyList(from: data, format: nil) as! [String: Any]

        XCTAssertEqual(parsed["RunAtLoad"] as? Bool, true, "RunAtLoad should be true when runAtStartup is true")
    }

    func testRunAtStartupFalseSetsRunAtLoadFalse() throws {
        var config = ScheduleConfig()
        config.isEnabled = true
        config.frequency = .hourly
        config.runAtStartup = false

        let plist = config.toLaunchdPlist(jobId: "no-startup", rsyncCommand: "echo test")

        let data = plist.data(using: .utf8)!
        let parsed = try PropertyListSerialization.propertyList(from: data, format: nil) as! [String: Any]

        XCTAssertEqual(parsed["RunAtLoad"] as? Bool, false, "RunAtLoad should be false when runAtStartup is false")
    }

    // MARK: - Idle Minutes Configuration

    func testRunAfterIdleSetsLowPriorityFlags() throws {
        var config = ScheduleConfig()
        config.isEnabled = true
        config.frequency = .manual
        config.runAfterIdleMinutes = 10

        let plist = config.toLaunchdPlist(jobId: "idle-job", rsyncCommand: "echo test")

        let data = plist.data(using: .utf8)!
        let parsed = try PropertyListSerialization.propertyList(from: data, format: nil) as! [String: Any]

        XCTAssertEqual(parsed["LowPriorityIO"] as? Bool, true)
        XCTAssertEqual(parsed["Nice"] as? Int, 10)
        XCTAssertEqual(parsed["StartOnMount"] as? Bool, false)
    }

    func testNoIdleMinutesDoesNotSetLowPriorityFlags() throws {
        var config = ScheduleConfig()
        config.isEnabled = true
        config.frequency = .hourly
        config.runAfterIdleMinutes = nil

        let plist = config.toLaunchdPlist(jobId: "no-idle", rsyncCommand: "echo test")

        let data = plist.data(using: .utf8)!
        let parsed = try PropertyListSerialization.propertyList(from: data, format: nil) as! [String: Any]

        XCTAssertNil(parsed["LowPriorityIO"])
        XCTAssertNil(parsed["Nice"])
        XCTAssertNil(parsed["StartOnMount"])
    }

    // MARK: - ProgramArguments

    func testProgramArgumentsContainRsyncCommand() throws {
        let command = "/usr/bin/rsync -avz --delete /source/ /dest/"

        var config = ScheduleConfig()
        config.isEnabled = true
        config.frequency = .hourly

        let plist = config.toLaunchdPlist(jobId: "prog-args-test", rsyncCommand: command)

        let data = plist.data(using: .utf8)!
        let parsed = try PropertyListSerialization.propertyList(from: data, format: nil) as! [String: Any]

        let progArgs = parsed["ProgramArguments"] as? [String]
        XCTAssertNotNil(progArgs)
        XCTAssertEqual(progArgs?[0], "/bin/sh")
        XCTAssertEqual(progArgs?[1], "-c")
        XCTAssertEqual(progArgs?[2], command)
    }

    // MARK: - XML Injection Prevention

    func testJobIdWithXMLSpecialCharactersIsSafelyEncoded() throws {
        // PropertyListSerialization handles XML escaping, but verify it
        var config = ScheduleConfig()
        config.isEnabled = true
        config.frequency = .hourly

        let maliciousJobId = "test<script>alert('xss')</script>"
        let plist = config.toLaunchdPlist(jobId: maliciousJobId, rsyncCommand: "echo test")

        XCTAssertFalse(plist.isEmpty, "Should produce valid plist even with special characters in jobId")

        // Verify the plist is parseable (PropertyListSerialization escapes XML)
        let data = plist.data(using: .utf8)!
        let parsed = try PropertyListSerialization.propertyList(from: data, format: nil) as! [String: Any]
        let label = parsed["Label"] as? String
        XCTAssertTrue(label?.contains("test<script>alert('xss')</script>") ?? false,
                      "Label should contain the literal string, properly XML-escaped in the plist")
    }

    func testRsyncCommandWithQuotesIsSafelyEncoded() throws {
        var config = ScheduleConfig()
        config.isEnabled = true
        config.frequency = .manual

        let command = "/usr/bin/rsync -a '/path with \"quotes\"/' /dest/"
        let plist = config.toLaunchdPlist(jobId: "quotes-test", rsyncCommand: command)

        let data = plist.data(using: .utf8)!
        let parsed = try PropertyListSerialization.propertyList(from: data, format: nil) as! [String: Any]

        let progArgs = parsed["ProgramArguments"] as? [String]
        XCTAssertEqual(progArgs?[2], command, "Command with quotes should be preserved exactly")
    }

    // MARK: - Valid Plist Format

    func testGeneratedPlistIsValidXML() {
        var config = ScheduleConfig()
        config.isEnabled = true
        config.frequency = .daily
        config.runAtStartup = true

        var components = DateComponents()
        components.hour = 12
        components.minute = 0
        config.time = Calendar.current.date(from: components)

        let plist = config.toLaunchdPlist(jobId: "valid-xml-test", rsyncCommand: "/usr/bin/rsync -a /src/ /dst/")

        XCTAssertTrue(plist.hasPrefix("<?xml"), "Generated plist should start with XML declaration")
        XCTAssertTrue(plist.contains("<!DOCTYPE plist"), "Generated plist should contain DOCTYPE")
        XCTAssertTrue(plist.contains("<plist version=\"1.0\">"), "Generated plist should have plist element")
    }

    // MARK: - ScheduleFrequency Enum

    func testScheduleFrequencyAllCases() {
        let allCases = ScheduleFrequency.allCases
        XCTAssertEqual(allCases.count, 6)
        XCTAssertTrue(allCases.contains(.manual))
        XCTAssertTrue(allCases.contains(.hourly))
        XCTAssertTrue(allCases.contains(.daily))
        XCTAssertTrue(allCases.contains(.weekly))
        XCTAssertTrue(allCases.contains(.monthly))
        XCTAssertTrue(allCases.contains(.custom))
    }

    func testScheduleFrequencyRawValues() {
        XCTAssertEqual(ScheduleFrequency.manual.rawValue, "Manual")
        XCTAssertEqual(ScheduleFrequency.hourly.rawValue, "Hourly")
        XCTAssertEqual(ScheduleFrequency.daily.rawValue, "Daily")
        XCTAssertEqual(ScheduleFrequency.weekly.rawValue, "Weekly")
        XCTAssertEqual(ScheduleFrequency.monthly.rawValue, "Monthly")
        XCTAssertEqual(ScheduleFrequency.custom.rawValue, "Custom (cron)")
    }

    // MARK: - Codable

    func testScheduleConfigCodableRoundtrip() throws {
        var config = ScheduleConfig()
        config.isEnabled = true
        config.frequency = .weekly
        config.dayOfWeek = 3
        config.runAtStartup = true
        config.runAfterIdleMinutes = 15
        config.customCron = "0 * * * *"

        var components = DateComponents()
        components.hour = 14
        components.minute = 30
        config.time = Calendar.current.date(from: components)

        let data = try JSONEncoder().encode(config)
        let decoded = try JSONDecoder().decode(ScheduleConfig.self, from: data)

        XCTAssertEqual(decoded.isEnabled, config.isEnabled)
        XCTAssertEqual(decoded.frequency, config.frequency)
        XCTAssertEqual(decoded.dayOfWeek, config.dayOfWeek)
        XCTAssertEqual(decoded.runAtStartup, config.runAtStartup)
        XCTAssertEqual(decoded.runAfterIdleMinutes, config.runAfterIdleMinutes)
        XCTAssertEqual(decoded.customCron, config.customCron)
    }
}
