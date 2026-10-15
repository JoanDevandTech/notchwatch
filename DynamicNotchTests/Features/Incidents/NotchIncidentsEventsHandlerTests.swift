import Combine
import XCTest
import NotchwatchCore
@testable import DynamicNotch

@MainActor
final class NotchIncidentsEventsHandlerTests: XCTestCase {

    private var cancellables = Set<AnyCancellable>()

    private struct Harness {
        let handler: NotchIncidentsEventsHandler
        let notchViewModel: NotchViewModel
        let fixture: IncidentsTestFactory.Fixture
    }

    private func makeHarness(configured: Bool = true, scope: IncidentScope = .all) -> Harness {
        let suiteName = "NotchIncidentsEventsHandlerTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)

        let settingsViewModel = SettingsViewModel(defaults: defaults)
        let notchViewModel = NotchViewModel(
            settings: settingsViewModel.application,
            hideDelay: 0.01,
            queueDelay: 0
        )
        let fixture = IncidentsTestFactory.makeFixture(configured: configured, scope: scope)
        let handler = NotchIncidentsEventsHandler(
            notchViewModel: notchViewModel,
            incidentsViewModel: fixture.viewModel,
            settingsViewModel: settingsViewModel
        )
        TestLifetime.retain(settingsViewModel)
        TestLifetime.retain(notchViewModel)
        TestLifetime.retain(handler)
        return Harness(handler: handler, notchViewModel: notchViewModel, fixture: fixture)
    }

    /// Conecta el view model al handler como hace el coordinator.
    private func start(_ harness: Harness) {
        harness.fixture.viewModel.$event
            .compactMap { $0 }
            .sink { [handler = harness.handler] event in
                handler.handle(event)
            }
            .store(in: &cancellables)
        harness.fixture.viewModel.startMonitoring()
    }

    func testLiveActivityAppearsWhenConfiguredAndMonitoring() async {
        let harness = makeHarness()

        start(harness)

        await assertEventually {
            await MainActor.run {
                harness.notchViewModel.notchModel.liveActivityContent?.id == NotchContentRegistry.Incidents.pending.id
            }
        }
        XCTAssertNil(harness.notchViewModel.notchModel.temporaryNotificationContent)
    }

    func testNoLiveActivityWithoutConfiguredSource() async {
        let harness = makeHarness(configured: false)

        start(harness)

        try? await Task.sleep(nanoseconds: 80_000_000)
        XCTAssertNil(harness.notchViewModel.notchModel.liveActivityContent)
    }

    func testNewUrgentIncidentShowsStickyAlert() async {
        let harness = makeHarness()
        let incident = IncidentsTestFactory.makeIncident(id: "u", priority: .urgente, collection: harness.fixture.collection)
        harness.fixture.monitoring.enqueue(pending: [incident], new: [incident])

        start(harness)

        await assertEventually {
            await MainActor.run {
                harness.notchViewModel.notchModel.temporaryNotificationContent?.id == NotchContentRegistry.Incidents.alert.id
            }
        }
        try? await Task.sleep(nanoseconds: 80_000_000)
        XCTAssertEqual(
            harness.notchViewModel.notchModel.temporaryNotificationContent?.id,
            NotchContentRegistry.Incidents.alert.id,
            "Loud alerts stay until acknowledged"
        )

        harness.fixture.viewModel.acknowledge(incident)

        await assertEventually {
            await MainActor.run {
                harness.notchViewModel.notchModel.temporaryNotificationContent == nil &&
                harness.notchViewModel.notchModel.liveActivityContent?.id == NotchContentRegistry.Incidents.pending.id
            }
        }
    }

    func testCollapsingThePanelRestoresTheMineFilter() {
        let harness = makeHarness(scope: .mine)
        harness.fixture.viewModel.setShowOnlyMine(false)

        harness.handler.handleExpansionChange(isExpanded: true)
        XCTAssertFalse(harness.fixture.viewModel.showsOnlyMine)

        harness.handler.handleExpansionChange(isExpanded: false)
        XCTAssertTrue(harness.fixture.viewModel.showsOnlyMine)
    }

    func testNoAlertWhilePanelIsExpanded() async {
        let harness = makeHarness()
        let existing = IncidentsTestFactory.makeIncident(id: "e", collection: harness.fixture.collection)
        harness.fixture.monitoring.enqueue(pending: [existing])
        start(harness)
        await assertEventually {
            await MainActor.run {
                harness.notchViewModel.notchModel.liveActivityContent?.id == NotchContentRegistry.Incidents.pending.id
            }
        }

        harness.notchViewModel.expandActiveLiveActivity()
        await assertEventually {
            await MainActor.run { harness.notchViewModel.notchModel.isLiveActivityExpanded }
        }

        let arrived = IncidentsTestFactory.makeIncident(id: "n", priority: .urgente, collection: harness.fixture.collection)
        harness.fixture.monitoring.enqueue(pending: [existing, arrived], new: [arrived])
        harness.fixture.viewModel.refreshNow()
        await assertEventually {
            await MainActor.run { harness.fixture.viewModel.pending.count == 2 }
        }

        try? await Task.sleep(nanoseconds: 80_000_000)
        XCTAssertNil(harness.notchViewModel.notchModel.temporaryNotificationContent)
        XCTAssertTrue(harness.notchViewModel.notchModel.isLiveActivityExpanded)
        XCTAssertEqual(harness.notchViewModel.notchModel.liveActivityContent?.id, NotchContentRegistry.Incidents.pending.id)
    }

    func testLiveActivityIsResentWhenCountChanges() async {
        let harness = makeHarness()
        let first = IncidentsTestFactory.makeIncident(id: "1", collection: harness.fixture.collection)
        harness.fixture.monitoring.enqueue(pending: [first])
        start(harness)
        await assertEventually {
            await MainActor.run {
                harness.notchViewModel.notchModel.liveActivityContent?.id == NotchContentRegistry.Incidents.pending.id &&
                harness.fixture.viewModel.pending.count == 1
            }
        }
        let token = harness.notchViewModel.notchModel.updateToken

        let second = IncidentsTestFactory.makeIncident(id: "2", collection: harness.fixture.collection, createdAt: Date().addingTimeInterval(-3600))
        harness.fixture.monitoring.enqueue(pending: [first, second])
        harness.fixture.viewModel.refreshNow()

        await assertEventually {
            await MainActor.run {
                harness.notchViewModel.notchModel.updateToken != token &&
                harness.notchViewModel.notchModel.liveActivityContent?.id == NotchContentRegistry.Incidents.pending.id
            }
        }
    }

    func testLiveActivityHidesWhenMonitoringStops() async {
        let harness = makeHarness()
        start(harness)
        await assertEventually {
            await MainActor.run {
                harness.notchViewModel.notchModel.liveActivityContent?.id == NotchContentRegistry.Incidents.pending.id
            }
        }

        harness.fixture.viewModel.stopMonitoring()

        await assertEventually {
            await MainActor.run { harness.notchViewModel.notchModel.liveActivityContent == nil }
        }
    }

    func testDoNotDisturbSuppressesAlertButKeepsCounter() async {
        let harness = makeHarness()
        harness.fixture.viewModel.setDoNotDisturb(.indefinite)
        harness.fixture.profileStore.profile.sound.doNotDisturb.urgentBreaksThrough = false
        let incident = IncidentsTestFactory.makeIncident(id: "d", priority: .alta, collection: harness.fixture.collection)
        harness.fixture.monitoring.enqueue(pending: [incident], new: [incident])

        start(harness)

        await assertEventually {
            await MainActor.run { harness.fixture.viewModel.pending.count == 1 }
        }
        try? await Task.sleep(nanoseconds: 80_000_000)
        XCTAssertNil(harness.notchViewModel.notchModel.temporaryNotificationContent)
        XCTAssertEqual(harness.notchViewModel.notchModel.liveActivityContent?.id, NotchContentRegistry.Incidents.pending.id)
    }
}
