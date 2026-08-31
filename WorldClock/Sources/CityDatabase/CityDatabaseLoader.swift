import Foundation
import Observation

/// Loads the bundled City index off the main thread once at startup; the
/// search overlay shows results as soon as it lands.
@MainActor
@Observable
final class CityDatabaseLoader {
    private(set) var database: CityDatabase?

    func load() {
        guard database == nil else { return }
        Task.detached(priority: .utility) {
            let database = try? CityDatabase.loadBundled()
            await MainActor.run { [weak self] in
                self?.database = database
            }
        }
    }
}
