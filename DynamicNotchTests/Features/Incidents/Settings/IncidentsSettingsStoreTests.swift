import Combine
import XCTest
@testable import DynamicNotch

@MainActor
final class IncidentsSettingsStoreTests: XCTestCase {
    private var testDefaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "DynamicNotch.Tests.IncidentsSettingsStore.\(UUID().uuidString)"
        testDefaults = UserDefaults(suiteName: suiteName)!
        testDefaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        testDefaults.removePersistentDomain(forName: suiteName)
        testDefaults = nil
        suiteName = nil
        super.tearDown()
    }

    func testIncidentsAreEnabledByDefault() {
        let store = IncidentsSettingsStore(defaults: testDefaults)

        XCTAssertTrue(store.isIncidentsEnabled)
        XCTAssertEqual(GeneralSettingsStorage.defaultValues[GeneralSettingsStorage.Keys.incidentsEnabled] as? Bool, true)
    }

    func testDisablingPersistsInSuiteDefaults() {
        let store = IncidentsSettingsStore(defaults: testDefaults)

        store.isIncidentsEnabled = false

        XCTAssertEqual(testDefaults.object(forKey: GeneralSettingsStorage.Keys.incidentsEnabled) as? Bool, false)
        let freshStore = IncidentsSettingsStore(defaults: testDefaults)
        XCTAssertFalse(freshStore.isIncidentsEnabled)
    }

    func testResetRestoresDefault() {
        let store = IncidentsSettingsStore(defaults: testDefaults)
        store.isIncidentsEnabled = false

        store.resetIncidents()

        XCTAssertTrue(store.isIncidentsEnabled)
        XCTAssertEqual(testDefaults.object(forKey: GeneralSettingsStorage.Keys.incidentsEnabled) as? Bool, true)
    }

    func testObjectWillChangeFiresOnToggle() {
        let store = IncidentsSettingsStore(defaults: testDefaults)
        var changeCount = 0
        var cancellables = Set<AnyCancellable>()

        store.objectWillChange.sink {
            changeCount += 1
        }.store(in: &cancellables)

        store.isIncidentsEnabled = false
        XCTAssertEqual(changeCount, 1)
    }

    func testSettingsViewModelExposesIncidentsStoreAndResetGroup() {
        let settingsViewModel = SettingsViewModel(defaults: testDefaults)
        settingsViewModel.incidents.isIncidentsEnabled = false

        settingsViewModel.reset(.incidents)

        XCTAssertTrue(settingsViewModel.incidents.isIncidentsEnabled)
    }

    func testPublisherEmitsCurrentValueThenChanges() {
        let store = IncidentsSettingsStore(defaults: testDefaults)
        var received: [Bool] = []
        var cancellables = Set<AnyCancellable>()

        store.$isIncidentsEnabled
            .sink { received.append($0) }
            .store(in: &cancellables)
        store.isIncidentsEnabled = false

        XCTAssertEqual(received, [true, false])
    }
}
