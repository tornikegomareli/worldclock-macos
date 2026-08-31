import Foundation
import Observation

/// Loads the bundled City index off the main thread once at startup; the
/// search overlay shows results as soon as it lands.
@MainActor
@Observable
final class CityDatabaseLoader {
    private(set) var database: CityDatabase?

    func load(onLoad: (@MainActor (CityDatabase) -> Void)? = nil) {
        guard database == nil else {
            if let database { onLoad?(database) }
            return
        }
        Task.detached(priority: .utility) {
            let database = try? CityDatabase.loadBundled()
            await MainActor.run { [weak self] in
                self?.database = database
                if let database { onLoad?(database) }
            }
        }
    }
}
