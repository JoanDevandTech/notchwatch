import XCTest
import NotchwatchCore
@testable import DynamicNotch

/// Solo a través del protocolo: el `UNUserNotificationCenter` real nunca se toca en tests.
@MainActor
final class IncidentNotifierTests: XCTestCase {

    func testInactiveNotifierReportsUnavailablePermission() {
        let notifier = InactiveIncidentNotifier()
        var requested: IncidentNotifier.Permission?
        var current: IncidentNotifier.Permission?

        notifier.requestAuthorization { requested = $0 }
        notifier.currentPermission { current = $0 }

        XCTAssertEqual(requested, .unavailable)
        XCTAssertEqual(current, .unavailable)
    }

    func testActionMapsResponseIdentifiers() {
        XCTAssertEqual(IncidentNotifier.Action(responseIdentifier: IncidentNotifier.Action.assignIdentifier), .assign)
        XCTAssertEqual(IncidentNotifier.Action(responseIdentifier: IncidentNotifier.Action.snoozeIdentifier), .snooze)
        XCTAssertEqual(IncidentNotifier.Action(responseIdentifier: IncidentNotifier.Action.openIdentifier), .open)
        XCTAssertEqual(IncidentNotifier.Action(responseIdentifier: "com.apple.UNNotificationDefaultActionIdentifier"), .open)
        XCTAssertEqual(IncidentNotifier.Action(responseIdentifier: "com.apple.UNNotificationDismissActionIdentifier"), .dismissed)
    }

    func testViewModelPostsSummaryForFirstBatchWhenAllowed() async {
        let fixture = IncidentsTestFactory.makeFixture()
        let urgent = IncidentsTestFactory.makeIncident(id: "u", priority: .urgente, collection: fixture.collection)
        let low = IncidentsTestFactory.makeIncident(id: "l", priority: .baja, collection: fixture.collection)
        fixture.monitoring.enqueue(pending: [urgent, low], new: [urgent, low])

        fixture.viewModel.startMonitoring()

        await assertEventually {
            await MainActor.run { fixture.notifier.posted.count == 1 }
        }
        let summary = fixture.notifier.posted[0]
        XCTAssertTrue(summary.isSummary, "The first poll of the session is announced as a batch")
        XCTAssertEqual(summary.identifier, NotificationPlanner.summaryIdentifier)
        XCTAssertEqual(fixture.viewModel.notificationPermission, .allowed)
    }

    func testViewModelSkipsNotificationsWhenPermissionIsDenied() async {
        let fixture = IncidentsTestFactory.makeFixture()
        fixture.notifier.permission = .denied
        let incident = IncidentsTestFactory.makeIncident(id: "d", priority: .alta, collection: fixture.collection)
        fixture.monitoring.enqueue(pending: [incident], new: [incident])

        fixture.viewModel.startMonitoring()

        await assertEventually {
            await MainActor.run { fixture.viewModel.pending.count == 1 }
        }
        XCTAssertTrue(fixture.notifier.posted.isEmpty)
        XCTAssertEqual(fixture.viewModel.notificationPermission, .denied)
    }

    func testViewModelSkipsNotificationsWhenDisabledInProfile() async {
        let fixture = IncidentsTestFactory.makeFixture()
        fixture.profileStore.profile.behavior.systemNotifications = false
        let incident = IncidentsTestFactory.makeIncident(id: "off", priority: .alta, collection: fixture.collection)
        fixture.monitoring.enqueue(pending: [incident], new: [incident])

        fixture.viewModel.startMonitoring()

        await assertEventually {
            await MainActor.run { fixture.viewModel.pending.count == 1 }
        }
        XCTAssertTrue(fixture.notifier.posted.isEmpty)
    }

    func testRequestPermissionUpdatesViewModel() {
        let fixture = IncidentsTestFactory.makeFixture()
        fixture.notifier.permission = .allowed

        fixture.viewModel.requestNotificationPermission()

        XCTAssertEqual(fixture.notifier.authorizationRequests, 1)
        XCTAssertEqual(fixture.viewModel.notificationPermission, .allowed)
    }

    func testClosedIncidentsAreWithdrawnFromNotificationCenter() async {
        let fixture = IncidentsTestFactory.makeFixture()
        let incident = IncidentsTestFactory.makeIncident(id: "w", priority: .media, collection: fixture.collection)
        fixture.monitoring.enqueue(pending: [incident], new: [incident])
        fixture.viewModel.startMonitoring()
        await assertEventually {
            await MainActor.run { fixture.notifier.posted.map(\.identifier) == ["w"] }
        }

        fixture.monitoring.enqueue(pending: [])
        fixture.viewModel.refreshNow()

        await assertEventually {
            await MainActor.run { fixture.notifier.withdrawn.contains("w") }
        }
    }
}
