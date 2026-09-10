import Dependencies
import Foundation
import RealityKit
import Testing
@testable import WorldClock

@Suite("Globe city inspection")
struct GlobeStateTests {
    @MainActor
    @Test("World View reuses prepared resources across concurrent and repeated opens")
    func preparedResourcesAreReused() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let controller = withDependencies {
            $0.date = .constant(Date(timeIntervalSince1970: 0))
            $0.timeZone = TimeZone(secondsFromGMT: 0)!
        } operation: {
            GlobeSceneController(
                engine: TimeEngine(), store: LocationsStore(storageDirectory: directory), state: GlobeState()
            )
        }
        let firstLoad = Task { try await controller.prepareResources() }
        let secondLoad = Task { try await controller.prepareResources() }
        let first = try await firstLoad.value
        let second = try await secondLoad.value
        let start = ContinuousClock.now
        let reopened = try await controller.prepareResources()
        print("GLOBE_CACHED_PREPARATION \(start.duration(to: .now))")
        #expect(first.globeMesh === second.globeMesh)
        #expect(first.globeMesh === reopened.globeMesh)
        #expect(first.haloMesh === reopened.haloMesh)
        let night = try #require(first.surface.emissiveColor.texture?.resource)
        #expect(night.width > 0)
        #expect(reopened.surface.emissiveColor.texture != nil)
        #expect(first.surface.custom.texture != nil)
        #expect(first.surface.roughness.texture != nil)
    }

    @MainActor
    @Test("Reduced-motion flight arrives immediately; camera input clears the arrival label")
    func immediateFlightAndInterruption() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let state = GlobeState()
        let controller = withDependencies {
            $0.date = .constant(Date(timeIntervalSince1970: 0))
            $0.timeZone = TimeZone(secondsFromGMT: 0)!
        } operation: {
            GlobeSceneController(
                engine: TimeEngine(), store: LocationsStore(storageDirectory: directory), state: state
            )
        }
        controller.fly(toLatitude: 41.69, longitude: 44.8, animated: false)
        #expect(!state.isFlying && state.hasArrived)
        controller.fly(toLatitude: 41.69, longitude: 44.8)
        #expect(!state.isFlying && state.hasArrived)
        controller.zoom(by: 1.2)
        #expect(!state.hasArrived)
        controller.fly(toLatitude: 35.68, longitude: 139.69)
        #expect(state.isFlying && !state.hasArrived)
        controller.orbit(by: CGSize(width: 20, height: 0))
        #expect(!state.isFlying && !state.hasArrived)
        controller.fly(toLatitude: 40.71, longitude: -74.01)
        controller.magnify(to: 1.2)
        #expect(!state.isFlying && !state.hasArrived)
        controller.fly(toLatitude: 41.69, longitude: 44.8)
        controller.cancelFlight()
        #expect(!state.isFlying && !state.hasArrived)
    }

    let city = City(name: "Cambridge", asciiName: "Cambridge", country: "GB",
                    latitude: 52.2, longitude: 0.12, timeZone: "Europe/London",
                    alternates: [], population: 150_000)
    let london = Location(cityName: "London", timeZone: TimeZone(identifier: "Europe/London")!,
                          latitude: 51.5, longitude: -0.12, country: "GB")

    @Test("Saving a location updates the existing inspector's saved status")
    func savedStatusFollowsLocations() throws {
        let inspection = try #require(GlobeInspection(city: city, savedLocations: []))
        #expect(inspection.savedLocation(in: []) == nil)
        #expect(inspection.savedLocation(in: [london]) == london)
        #expect(inspection.savedLocation(in: []) == nil)
    }

    @Test("A city sharing Home's timezone is not labeled Home")
    func homeMatchesTheCity() throws {
        let inspection = try #require(GlobeInspection(city: city, savedLocations: [london]))
        #expect(!inspection.isHome(london))
        #expect(GlobeInspection(location: london).isHome(london))
        #expect(!inspection.isHome(nil))
    }

    @Test("Cities sharing a timezone have distinct search identities")
    func distinctDestinations() throws {
        let inspection = try #require(GlobeInspection(city: city, savedLocations: [london]))
        #expect(inspection.id != GlobeInspection(location: london).id)
    }

    @MainActor
    @Test("Canceling Jump clears the query and selection, preserving inspection")
    func cancelJump() {
        let state = GlobeState()
        state.inspection = GlobeInspection(location: london)
        state.isJumping = true
        state.jumpQuery = "Cambridge"
        state.jumpSelection = 3
        state.cancelJump()
        #expect(!state.isJumping)
        #expect(state.jumpQuery.isEmpty)
        #expect(state.jumpSelection == 0)
        #expect(state.inspection == GlobeInspection(location: london))
    }
}
