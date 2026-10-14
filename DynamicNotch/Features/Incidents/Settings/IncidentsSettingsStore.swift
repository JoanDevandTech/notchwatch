import Combine
import Foundation

@MainActor
final class IncidentsSettingsStore: SettingsStoreBase {
    @StoredDefault(key: GeneralSettingsStorage.Keys.incidentsEnabled, defaultValue: true)
    var isIncidentsEnabled: Bool

    override init(defaults: UserDefaults) {
        super.init(defaults: defaults)
    }

    func resetIncidents() {
        isIncidentsEnabled = defaultBool(for: GeneralSettingsStorage.Keys.incidentsEnabled)
    }
}
