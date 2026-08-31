import Foundation

/// 12-hour or 24-hour clock display.
enum ClockFormat: Equatable {
    case twelveHour
    case twentyFourHour

    /// The locale's hour-cycle preference ("12/24h from system"). The "j"
    /// skeleton resolves to a pattern containing the AM/PM field only for
    /// 12-hour locales.
    static func system(for locale: Locale = .current) -> ClockFormat {
        let template = DateFormatter.dateFormat(fromTemplate: "j", options: 0, locale: locale) ?? ""
        return template.contains("a") ? .twelveHour : .twentyFourHour
    }
}

/// Pure string rendering of offsets and times. No DateFormatter, no locale —
/// callers pass explicit components, tests pin explicit fixtures.
enum TimeFormatting {
    static func timeString(_ localTime: LocalTime, clockFormat: ClockFormat) -> String {
        switch clockFormat {
        case .twentyFourHour:
            return String(format: "%02d:%02d", localTime.hour, localTime.minute)
        case .twelveHour:
            let hour12 = localTime.hour % 12 == 0 ? 12 : localTime.hour % 12
            let suffix = localTime.hour < 12 ? "AM" : "PM"
            return String(format: "%d:%02d %@", hour12, localTime.minute, suffix)
        }
    }

    /// Labels `target`'s civil date relative to `reference`'s: nil when they
    /// match, "Yesterday"/"Tomorrow" one day apart, otherwise "Mon, Jul 13"
    /// (pinned en_US names — localization comes with GreetingProvider).
    static func relativeDayLabel(
        of target: Date, in targetZone: TimeZone,
        relativeTo reference: Date, in referenceZone: TimeZone
    ) -> String? {
        let dayDelta = civilDayNumber(of: target, in: targetZone) - civilDayNumber(of: reference, in: referenceZone)
        switch dayDelta {
        case 0:
            return nil
        case 1:
            return "Tomorrow"
        case -1:
            return "Yesterday"
        default:
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = targetZone
            formatter.dateFormat = "EEE, MMM d"
            return formatter.string(from: target)
        }
    }

    /// A civil date as a comparable day count, independent of timezone.
    private static func civilDayNumber(of date: Date, in timeZone: TimeZone) -> Int {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let components = calendar.dateComponents([.year, .month, .day], from: date)

        var utcCalendar = Calendar(identifier: .gregorian)
        utcCalendar.timeZone = .gmt
        let civilDate = utcCalendar.date(from: components) ?? date
        return Int((civilDate.timeIntervalSince1970 / 86400).rounded(.down))
    }

    /// "+5h", "-9h", "+4:30", "0h" for zero.
    static func relativeOffset(seconds: Int) -> String {
        if seconds == 0 { return "0h" }
        let sign = seconds < 0 ? "-" : "+"
        let totalMinutes = abs(seconds) / 60
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        if minutes == 0 {
            return "\(sign)\(hours)h"
        }
        return String(format: "%@%d:%02d", sign, hours, minutes)
    }
}
