import Dependencies
import Foundation
import Testing
@testable import WorldClock

/// Weather is tested through a fake WeatherProvider (ADR-0003): display
/// mapping, cache TTL against the injected clock, and failure/recovery states.
@Suite("WeatherStore")
struct WeatherStoreTests {
    let tbilisi = Location(
        cityName: "Tbilisi",
        timeZone: TimeZone(identifier: "Asia/Tbilisi")!,
        latitude: 41.69,
        longitude: 44.80
    )

    final class FakeProvider: WeatherProvider, @unchecked Sendable {
        var result: Result<Weather, Error>
        private(set) var fetchCount = 0

        init(result: Result<Weather, Error>) {
            self.result = result
        }

        func weather(latitude: Double, longitude: Double) async throws -> Weather {
            fetchCount += 1
            return try result.get()
        }
    }

    func instant(_ iso: String) -> Date {
        ISO8601DateFormatter().date(from: iso)!
    }

    @Test("Conditions map to glyphs and temperatures format per unit system")
    func displayMapping() {
        #expect(WeatherCondition.clear.symbolName == "sun.max")
        #expect(WeatherCondition.cloudy.symbolName == "cloud")
        #expect(WeatherCondition.rain.symbolName == "cloud.rain")
        #expect(WeatherCondition.snow.symbolName == "cloud.snow")

        let mild = Weather(condition: .clear, temperatureCelsius: 23.4)
        #expect(mild.temperatureText(usesMetric: true) == "23°")
        #expect(mild.temperatureText(usesMetric: false) == "74°")

        let freezing = Weather(condition: .snow, temperatureCelsius: -3.6)
        #expect(freezing.temperatureText(usesMetric: true) == "-4°")
    }

    @Test("A fetched Weather is cached; within the TTL no refetch happens")
    @MainActor
    func cacheWithinTTL() async {
        let provider = FakeProvider(result: .success(Weather(condition: .clear, temperatureCelsius: 20)))
        let store = withDependencies {
            $0.date = DateGenerator { self.instant("2026-09-01T12:00:00Z") }
        } operation: {
            WeatherStore(provider: provider)
        }

        await store.refresh([tbilisi])
        #expect(store.weather(for: tbilisi) == Weather(condition: .clear, temperatureCelsius: 20))

        await store.refresh([tbilisi])
        #expect(provider.fetchCount == 1)
    }

    @Test("Past the TTL a refresh refetches")
    @MainActor
    func refetchAfterTTL() async {
        let provider = FakeProvider(result: .success(Weather(condition: .clear, temperatureCelsius: 20)))
        let now = LockIsolated(instant("2026-09-01T12:00:00Z"))
        let store = withDependencies {
            $0.date = DateGenerator { now.value }
        } operation: {
            WeatherStore(provider: provider)
        }

        await store.refresh([tbilisi])
        now.setValue(instant("2026-09-01T12:45:00Z")) // past the 30-minute TTL
        await store.refresh([tbilisi])

        #expect(provider.fetchCount == 2)
    }

    @Test("Failures expose an unavailable state without fabricated weather")
    @MainActor
    func failureMeansAbsence() async {
        struct Unavailable: Error {}
        let provider = FakeProvider(result: .failure(Unavailable()))
        let store = withDependencies {
            $0.date = DateGenerator { self.instant("2026-09-01T12:00:00Z") }
        } operation: {
            WeatherStore(provider: provider)
        }

        await store.refresh([tbilisi])

        #expect(store.weather(for: tbilisi) == nil)
        #expect(store.isUnavailable(for: tbilisi))
    }

    @Test("A failed request retries after a short delay and clears the error on success")
    @MainActor
    func recoveryAfterFailure() async {
        let provider = FakeProvider(result: .failure(URLError(.notConnectedToInternet)))
        let now = LockIsolated(instant("2026-09-01T12:00:00Z"))
        let store = withDependencies { $0.date = DateGenerator { now.value } } operation: {
            WeatherStore(provider: provider)
        }
        await store.refresh([tbilisi])
        await store.refresh([tbilisi])
        #expect(provider.fetchCount == 1)
        provider.result = .success(Weather(condition: .clear, temperatureCelsius: 20))
        let retryDate = now.value.addingTimeInterval(WeatherStore.retryDelay)
        now.setValue(retryDate)
        await store.refresh([tbilisi])
        #expect(provider.fetchCount == 2)
        #expect(!store.isUnavailable(for: tbilisi))
        #expect(store.weather(for: tbilisi)?.temperatureCelsius == 20)
    }

    @Test("Expired weather is hidden and a failed refresh marks it unavailable")
    @MainActor
    func staleWeatherIsNotCurrent() async {
        let provider = FakeProvider(result: .success(Weather(condition: .clear, temperatureCelsius: 20)))
        let now = LockIsolated(instant("2026-09-01T12:00:00Z"))
        let store = withDependencies { $0.date = DateGenerator { now.value } } operation: {
            WeatherStore(provider: provider)
        }
        await store.refresh([tbilisi])
        let expiryDate = now.value.addingTimeInterval(WeatherStore.timeToLive)
        now.setValue(expiryDate)
        #expect(store.weather(for: tbilisi) == nil)
        provider.result = .failure(URLError(.notConnectedToInternet))
        await store.refresh([tbilisi])
        #expect(store.weather(for: tbilisi) == nil)
        #expect(store.isUnavailable(for: tbilisi))
    }

    @Test("Clear weather uses the moon at night")
    func nightSymbol() {
        #expect(Weather(condition: .clear, temperatureCelsius: 20, isDaylight: false).symbolName == "moon")
        #expect(Weather(condition: .clear, temperatureCelsius: 20).symbolName == "sun.max")
    }

    @Test("A Location without coordinates gets no weather and no fetch")
    @MainActor
    func missingCoordinatesSkipped() async {
        let provider = FakeProvider(result: .success(Weather(condition: .clear, temperatureCelsius: 20)))
        let timeZoneOnly = Location(cityName: "Somewhere", timeZone: TimeZone(identifier: "Asia/Tbilisi")!)
        let store = withDependencies {
            $0.date = DateGenerator { self.instant("2026-09-01T12:00:00Z") }
        } operation: {
            WeatherStore(provider: provider)
        }

        await store.refresh([timeZoneOnly])

        #expect(provider.fetchCount == 0)
        #expect(store.weather(for: timeZoneOnly) == nil)
    }
}
