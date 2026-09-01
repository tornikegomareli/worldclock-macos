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

    func instant(_ iso: String) -> Date {
        ISO8601DateFormatter().date(from: iso)!
    }

    @Test("A Location on the same civil date as Home gets no date label")
    func sameDateNoLabel() {
        let label = TimeFormatting.relativeDayLabel(
            of: instant("2026-07-15T18:00:00Z"), in: TimeZone(identifier: "Europe/London")!,
            relativeTo: instant("2026-07-15T18:00:00Z"), in: TimeZone(identifier: "America/New_York")!
        )
        #expect(label == nil)
    }

    @Test("Adjacent civil dates label as Tomorrow and Yesterday")
    func adjacentDates() {
        // 22:00 EDT in New York is 11:00 the NEXT day in Tokyo.
        let evening = instant("2026-07-15T22:00:00-04:00")
        #expect(
            TimeFormatting.relativeDayLabel(
                of: evening, in: TimeZone(identifier: "Asia/Tokyo")!,
                relativeTo: evening, in: TimeZone(identifier: "America/New_York")!
            ) == "Tomorrow"
        )

        // 08:00 in Tokyo is 19:00 the PREVIOUS day in New York.
        let morning = instant("2026-07-16T08:00:00+09:00")
        #expect(
            TimeFormatting.relativeDayLabel(
                of: morning, in: TimeZone(identifier: "America/New_York")!,
                relativeTo: morning, in: TimeZone(identifier: "Asia/Tokyo")!
            ) == "Yesterday"
        )
    }

    @Test("Across the date line two civil dates apart shows weekday and date")
    func dateLineTwoDaysApart() {
        // Just after midnight in Kiritimati (UTC+14), Pago Pago (UTC-11) is
        // still on the date two days back: Monday July 13.
        let reference = instant("2026-07-15T00:30:00+14:00")
        #expect(
            TimeFormatting.relativeDayLabel(
                of: reference, in: TimeZone(identifier: "Pacific/Pago_Pago")!,
                relativeTo: reference, in: TimeZone(identifier: "Pacific/Kiritimati")!
            ) == "Mon, Jul 13"
        )
    }

    @Test("A scrubbed instant days away from Now labels with weekday and date, DST day included")
    func scrubbedDaysAway() {
        let newYork = TimeZone(identifier: "America/New_York")!
        // Real now March 6; simulated instant on the spring-forward day March 8.
        #expect(
            TimeFormatting.relativeDayLabel(
                of: instant("2026-03-08T15:00:00-04:00"), in: newYork,
                relativeTo: instant("2026-03-06T12:00:00-05:00"), in: newYork
            ) == "Sun, Mar 8"
        )
        // One day ahead is still Tomorrow, even across the DST change.
        #expect(
            TimeFormatting.relativeDayLabel(
                of: instant("2026-03-08T15:00:00-04:00"), in: newYork,
                relativeTo: instant("2026-03-07T12:00:00-05:00"), in: newYork
            ) == "Tomorrow"
        )
    }

    @Test("UTC Mode strings: whole hours, non-integer zones, and UTC itself")
    func utcOffsetStrings() {
        #expect(TimeFormatting.utcOffset(seconds: 9 * 3600) == "UTC+9")
        #expect(TimeFormatting.utcOffset(seconds: -5 * 3600) == "UTC-5")
        #expect(TimeFormatting.utcOffset(seconds: 330 * 60) == "UTC+5:30")   // Kolkata
        #expect(TimeFormatting.utcOffset(seconds: 345 * 60) == "UTC+5:45")   // Kathmandu
        #expect(TimeFormatting.utcOffset(seconds: -210 * 60) == "UTC-3:30")  // St. John's (winter)
        #expect(TimeFormatting.utcOffset(seconds: 0) == "UTC")
    }

    @Test("System clock format follows the locale's hour cycle, pinned locales only")
    func systemClockFormatFromLocale() {
        #expect(ClockFormat.system(for: Locale(identifier: "en_US")) == .twelveHour)
        #expect(ClockFormat.system(for: Locale(identifier: "de_DE")) == .twentyFourHour)
        #expect(ClockFormat.system(for: Locale(identifier: "en_GB")) == .twentyFourHour)
    }
}
