import Foundation
import Testing
@testable import WorldClock

/// Formatting is pure string construction from components — no DateFormatter,
/// no machine locale. Expected strings are pinned literals.
@Suite("TimeFormatting")
struct TimeFormattingTests {
    @Test("Whole-hour relative offsets format as signed hours")
    func wholeHourOffsets() {
        #expect(TimeFormatting.relativeOffset(seconds: 5 * 3600) == "+5h")
        #expect(TimeFormatting.relativeOffset(seconds: -9 * 3600) == "-9h")
        #expect(TimeFormatting.relativeOffset(seconds: 0) == "0h")
    }

    @Test("Half-hour zones format with minutes, like Kolkata from Tbilisi")
    func halfHourOffsets() {
        // Asia/Kolkata (+5:30) from Home Asia/Tbilisi (+4) is +1:30.
        #expect(TimeFormatting.relativeOffset(seconds: 90 * 60) == "+1:30")
        // America/St_Johns (-3:30 in winter) from Home UTC is -3:30.
        #expect(TimeFormatting.relativeOffset(seconds: -210 * 60) == "-3:30")
        // Asia/Kathmandu (+5:45) from Home UTC is +5:45.
        #expect(TimeFormatting.relativeOffset(seconds: 345 * 60) == "+5:45")
    }

    @Test("24-hour times are zero-padded")
    func twentyFourHourTimes() {
        #expect(TimeFormatting.timeString(LocalTime(hour: 8, minute: 5), clockFormat: .twentyFourHour) == "08:05")
        #expect(TimeFormatting.timeString(LocalTime(hour: 21, minute: 30), clockFormat: .twentyFourHour) == "21:30")
        #expect(TimeFormatting.timeString(LocalTime(hour: 0, minute: 0), clockFormat: .twentyFourHour) == "00:00")
    }

    @Test("12-hour times carry AM/PM, with midnight and noon as 12")
    func twelveHourTimes() {
        #expect(TimeFormatting.timeString(LocalTime(hour: 8, minute: 5), clockFormat: .twelveHour) == "8:05 AM")
        #expect(TimeFormatting.timeString(LocalTime(hour: 21, minute: 30), clockFormat: .twelveHour) == "9:30 PM")
        #expect(TimeFormatting.timeString(LocalTime(hour: 0, minute: 0), clockFormat: .twelveHour) == "12:00 AM")
        #expect(TimeFormatting.timeString(LocalTime(hour: 12, minute: 0), clockFormat: .twelveHour) == "12:00 PM")
    }

    @Test("System clock format follows the locale's hour cycle, pinned locales only")
    func systemClockFormatFromLocale() {
        #expect(ClockFormat.system(for: Locale(identifier: "en_US")) == .twelveHour)
        #expect(ClockFormat.system(for: Locale(identifier: "de_DE")) == .twentyFourHour)
        #expect(ClockFormat.system(for: Locale(identifier: "en_GB")) == .twentyFourHour)
    }
}
