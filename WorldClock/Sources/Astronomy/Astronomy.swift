import Foundation

/// Hand-rolled NOAA solar equations (Meeus-derived, per the NOAA solar
/// calculator spreadsheet — see docs/research/globe-rendering.md). Good for
/// years 1800–2100; sunrise/sunset within ~1 minute for |lat| ≤ 72°.
enum Astronomy {
    enum SunDay: Equatable {
        case risesAndSets(civilDawn: Date, sunrise: Date, sunset: Date, civilDusk: Date)
        /// High-latitude days where the sun stays below the horizon but civil
        /// twilight still occurs.
        case twilightOnly(civilDawn: Date, civilDusk: Date)
        case polarDay
        case polarNight
    }

    /// Sun events for the civil day containing `date` in `timeZone`. Events
    /// are built as absolute instants around the solar-noon instant, so
    /// DST-transition days come out right (ADR-0001: no offset arithmetic).
    static func sunDay(latitude: Double, longitude: Double, on date: Date, timeZone: TimeZone) -> SunDay {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        // Noon-ish reference instant: δ and EoT are slow-moving, and DST
        // transitions never happen midday, so the offset here is the day's
        // settled one.
        let referenceInstant = calendar.startOfDay(for: date).addingTimeInterval(12 * 3600)
        let timeZoneHours = Double(timeZone.secondsFromGMT(for: referenceInstant)) / 3600

        let solar = solarParameters(at: referenceInstant)
        let solarNoonClockMinutes = 720 - 4 * longitude - solar.equationOfTimeMinutes + timeZoneHours * 60

        let reference = calendar.dateComponents([.hour, .minute, .second], from: referenceInstant)
        let referenceClockMinutes = Double((reference.hour ?? 0) * 60 + (reference.minute ?? 0))
            + Double(reference.second ?? 0) / 60
        let solarNoon = referenceInstant
            .addingTimeInterval((solarNoonClockMinutes - referenceClockMinutes) * 60)

        let latitudeR = radians(latitude)
        let declinationR = radians(solar.declinationDegrees)

        /// The two instants the sun crosses `zenith`, or nil when it never
        /// does on this day.
        func crossings(zenithDegrees: Double) -> (rise: Date, set: Date)? {
            let cosHourAngle = (cos(radians(zenithDegrees)) - sin(latitudeR) * sin(declinationR))
                / (cos(latitudeR) * cos(declinationR))
            guard (-1.0...1.0).contains(cosHourAngle) else { return nil }
            let halfDaySeconds = degrees(acos(cosHourAngle)) * 4 * 60
            return (solarNoon.addingTimeInterval(-halfDaySeconds), solarNoon.addingTimeInterval(halfDaySeconds))
        }

        let twilight = crossings(zenithDegrees: 96)

        guard let sun = crossings(zenithDegrees: 90.833) else {
            if let twilight {
                return .twilightOnly(civilDawn: twilight.rise, civilDusk: twilight.set)
            }
            // Above or below the horizon all day: the noon elevation decides.
            let noonElevationSine = sin(latitudeR) * sin(declinationR) + cos(latitudeR) * cos(declinationR)
            return noonElevationSine > 0 ? .polarDay : .polarNight
        }

        // At high latitudes twilight may never end even though the sun sets —
        // clamp to the day's edges.
        let midnight = calendar.startOfDay(for: date)
        let nextMidnight = calendar.date(byAdding: .day, value: 1, to: midnight) ?? midnight.addingTimeInterval(86400)
        let clampedTwilight = twilight ?? (rise: midnight, set: nextMidnight)

        return .risesAndSets(
            civilDawn: clampedTwilight.rise,
            sunrise: sun.rise,
            sunset: sun.set,
            civilDusk: clampedTwilight.set
        )
    }

    /// Moon phase as a fraction of the synodic month: 0 new, 0.25 first
    /// quarter, 0.5 full, 0.75 last quarter. Mean-cycle approximation from
    /// the 2000-01-06 18:14 UT new moon; good to about a phase-day.
    static func moonPhase(at instant: Date) -> Double {
        let julianDay = 2440587.5 + instant.timeIntervalSince1970 / 86400
        let referenceNewMoon = 2451550.26  // 2000-01-06 18:14 UT
        let synodicMonth = 29.530588853
        let phase = ((julianDay - referenceNewMoon) / synodicMonth)
            .truncatingRemainder(dividingBy: 1)
        return phase < 0 ? phase + 1 : phase
    }

    struct SubsolarPoint: Equatable {
        let latitude: Double
        let longitude: Double
    }

    /// The point on Earth where the sun is directly overhead at `instant`.
    /// Latitude is the solar declination; longitude follows UTC time of day
    /// corrected by the equation of time.
    static func subsolarPoint(at instant: Date) -> SubsolarPoint {
        let solar = solarParameters(at: instant)
        let secondsIntoUTCDay = instant.timeIntervalSince1970
            .truncatingRemainder(dividingBy: 86400)
        let hoursUTC = secondsIntoUTCDay / 3600
        var longitude = -15 * (hoursUTC - 12 + solar.equationOfTimeMinutes / 60)
        if longitude < -180 { longitude += 360 }
        if longitude > 180 { longitude -= 360 }
        return SubsolarPoint(latitude: solar.declinationDegrees, longitude: longitude)
    }

    // MARK: NOAA solar position

    struct SolarParameters {
        let declinationDegrees: Double
        let equationOfTimeMinutes: Double
    }

    static func solarParameters(at instant: Date) -> SolarParameters {
        let julianDay = 2440587.5 + instant.timeIntervalSince1970 / 86400
        let t = (julianDay - 2451545.0) / 36525.0

        let meanLongitude = (280.46646 + t * (36000.76983 + t * 0.0003032))
            .truncatingRemainder(dividingBy: 360)
        let meanAnomaly = 357.52911 + t * (35999.05029 - 0.0001537 * t)
        let eccentricity = 0.016708634 - t * (0.000042037 + 0.0000001267 * t)

        let equationOfCenter =
            sin(radians(meanAnomaly)) * (1.914602 - t * (0.004817 + 0.000014 * t))
            + sin(radians(2 * meanAnomaly)) * (0.019993 - 0.000101 * t)
            + sin(radians(3 * meanAnomaly)) * 0.000289
        let trueLongitude = meanLongitude + equationOfCenter
        let omega = 125.04 - 1934.136 * t
        let apparentLongitude = trueLongitude - 0.00569 - 0.00478 * sin(radians(omega))

        let meanObliquity = 23.0 + (26.0 + (21.448 - t * (46.815 + t * (0.00059 - t * 0.001813))) / 60) / 60
        let obliquity = meanObliquity + 0.00256 * cos(radians(omega))

        let declination = degrees(asin(sin(radians(obliquity)) * sin(radians(apparentLongitude))))

        let y = pow(tan(radians(obliquity / 2)), 2)
        let equationOfTime = 4 * degrees(
            y * sin(2 * radians(meanLongitude))
                - 2 * eccentricity * sin(radians(meanAnomaly))
                + 4 * eccentricity * y * sin(radians(meanAnomaly)) * cos(2 * radians(meanLongitude))
                - 0.5 * y * y * sin(4 * radians(meanLongitude))
                - 1.25 * eccentricity * eccentricity * sin(2 * radians(meanAnomaly))
        )

        return SolarParameters(declinationDegrees: declination, equationOfTimeMinutes: equationOfTime)
    }

    private static func radians(_ degrees: Double) -> Double { degrees * .pi / 180 }
    private static func degrees(_ radians: Double) -> Double { radians * 180 / .pi }
}
