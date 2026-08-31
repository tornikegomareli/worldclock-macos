import Foundation

/// A Location's rendering of the Global Instant through its timezone rules.
/// Never stored; always derived (ADR-0001).
struct LocalTime: Equatable {
    let hour: Int
    let minute: Int

    init(hour: Int, minute: Int) {
        self.hour = hour
        self.minute = minute
    }

    init(of instant: Date, in timeZone: TimeZone) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let components = calendar.dateComponents([.hour, .minute], from: instant)
        hour = components.hour ?? 0
        minute = components.minute ?? 0
    }
}
