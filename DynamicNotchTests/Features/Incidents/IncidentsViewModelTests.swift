import XCTest
import NotchwatchCore
@testable import DynamicNotch

@MainActor
final class IncidentsViewModelTests: XCTestCase {

    func testIsConfiguredRequiresSourceWithToken() {
        let configured = IncidentsTestFactory.makeFixture(configured: true)
        let unconfigured = IncidentsTestFactory.makeFixture(configured: false)

        XCTAssertTrue(configured.viewModel.isConfigured)
        XCTAssertFalse(unconfigured.viewModel.isConfigured)
    }

    func testPollPopulatesPendingAndPresence() async {
        let fixture = IncidentsTestFactory.makeFixture()
        let incident = IncidentsTestFactory.makeIncident(id: "1", priority: .urgente, collection: fixture.collection)
        fixture.monitoring.enqueue(pending: [incident])

        fixture.viewModel.startMonitoring()

        await assertEventually {
            await MainActor.run {
                fixture.viewModel.pending.count == 1 && fixture.viewModel.presence == .pending(.urgente)
            }
        }
        XCTAssertEqual(fixture.viewModel.visibleCount, 1)
        XCTAssertEqual(fixture.viewModel.topPendingPriority, .urgente)
        XCTAssertTrue(fixture.viewModel.isMonitoring)
        XCTAssertEqual(fixture.monitoring.sourceUpdates.first, [IncidentsTestFactory.sourceID])
    }

    func testNewLoudIncidentRequestsAttentionAndEmitsArrival() async {
        let fixture = IncidentsTestFactory.makeFixture()
        let incident = IncidentsTestFactory.makeIncident(id: "loud", priority: .alta, collection: fixture.collection)
        fixture.monitoring.enqueue(pending: [incident], new: [incident])

        fixture.viewModel.startMonitoring()

        await assertEventually {
            await MainActor.run {
                fixture.viewModel.presence == .attention(.alta)
            }
        }
        XCTAssertTrue(fixture.viewModel.unattendedLoud.contains("loud"))
        XCTAssertEqual(fixture.viewModel.arrivalPulse, 1)
        XCTAssertEqual(fixture.notifier.posted.map(\.identifier), ["loud"])

        fixture.viewModel.acknowledge(incident)

        XCTAssertTrue(fixture.viewModel.unattendedLoud.isEmpty)
        XCTAssertEqual(fixture.viewModel.presence, .pending(.alta))
    }

    func testShowOnlyMineFiltersListedIncidents() async {
        let fixture = IncidentsTestFactory.makeFixture()
        let mine = IncidentsTestFactory.makeIncident(id: "mine", collection: fixture.collection, assigneeID: "u1")
        let other = IncidentsTestFactory.makeIncident(id: "other", priority: .alta, collection: fixture.collection, assigneeID: "u2")
        fixture.monitoring.enqueue(pending: [other, mine])

        fixture.viewModel.startMonitoring()

        await assertEventually {
            await MainActor.run {
                fixture.viewModel.pending.count == 2 && fixture.viewModel.identity != nil
            }
        }
        XCTAssertTrue(fixture.viewModel.isMine(mine))
        XCTAssertFalse(fixture.viewModel.isMine(other))
        XCTAssertEqual(fixture.viewModel.mineCount, 1)

        fixture.viewModel.setShowOnlyMine(true)

        XCTAssertEqual(fixture.viewModel.listedIncidents.map(\.id), ["mine"])
        XCTAssertEqual(fixture.viewModel.visibleCount, 1)
        XCTAssertTrue(fixture.viewModel.profile.behavior.showOnlyMine)
    }

    func testSnoozeMovesIncidentToTheEndAndForwardsToMonitor() async {
        let fixture = IncidentsTestFactory.makeFixture()
        let first = IncidentsTestFactory.makeIncident(id: "1", priority: .alta, collection: fixture.collection)
        let second = IncidentsTestFactory.makeIncident(id: "2", priority: .media, collection: fixture.collection)
        fixture.monitoring.enqueue(pending: [first, second])
        fixture.viewModel.startMonitoring()
        await assertEventually {
            await MainActor.run { fixture.viewModel.pending.count == 2 }
        }

        fixture.viewModel.snooze(first, minutes: 30)

        XCTAssertTrue(fixture.viewModel.isSnoozed(first))
        XCTAssertEqual(fixture.viewModel.listedIncidents.map(\.id), ["2", "1"])
        XCTAssertEqual(fixture.viewModel.visibleCount, 1)
        await assertEventually {
            await MainActor.run { fixture.monitoring.snoozed.first?.id == "1" }
        }
        XCTAssertEqual(fixture.monitoring.snoozed.first.map { Int($0.duration.rounded()) }, 1800)
    }

    func testMarkSeenRemovesIncidentAndForwardsToMonitor() async {
        let fixture = IncidentsTestFactory.makeFixture()
        let incident = IncidentsTestFactory.makeIncident(id: "seen", collection: fixture.collection)
        fixture.monitoring.enqueue(pending: [incident])
        fixture.viewModel.startMonitoring()
        await assertEventually {
            await MainActor.run { fixture.viewModel.pending.count == 1 }
        }

        fixture.viewModel.markSeen(incident)

        XCTAssertTrue(fixture.viewModel.pending.isEmpty)
        XCTAssertEqual(fixture.viewModel.presence, .idle)
        XCTAssertEqual(fixture.notifier.withdrawn, ["seen"])
        await assertEventually {
            await MainActor.run { fixture.monitoring.seen == ["seen"] }
        }
    }

    func testAssignToMeIsOptimisticAndPerformsOnSource() async {
        let fixture = IncidentsTestFactory.makeFixture()
        let incident = IncidentsTestFactory.makeIncident(id: "a", collection: fixture.collection)
        fixture.monitoring.enqueue(pending: [incident])
        fixture.viewModel.startMonitoring()
        await assertEventually {
            await MainActor.run { fixture.viewModel.pending.count == 1 && fixture.viewModel.identity != nil }
        }

        fixture.viewModel.assignToMe(incident)

        XCTAssertEqual(fixture.viewModel.pending.first?.assigneeID, "u1")
        XCTAssertEqual(fixture.viewModel.activity["a"], .working)
        await assertEventually {
            await MainActor.run {
                fixture.source.performed.contains { $0.action == .assignToMe && $0.incidentID == "a" }
            }
        }
        await assertEventually {
            await MainActor.run {
                if case .done = fixture.viewModel.activity["a"] { return true }
                return false
            }
        }
    }

    func testResolveRemovesLocallyAndPerformsOnSource() async {
        let fixture = IncidentsTestFactory.makeFixture()
        let incident = IncidentsTestFactory.makeIncident(id: "r", priority: .alta, collection: fixture.collection)
        fixture.monitoring.enqueue(pending: [incident], new: [incident])
        fixture.viewModel.startMonitoring()
        await assertEventually {
            await MainActor.run { fixture.viewModel.pending.count == 1 }
        }
        fixture.monitoring.pendingSnapshot = []

        fixture.viewModel.resolve(incident)

        XCTAssertTrue(fixture.viewModel.pending.isEmpty)
        XCTAssertTrue(fixture.viewModel.unattendedLoud.isEmpty)
        await assertEventually {
            await MainActor.run {
                fixture.source.performed.contains { $0.action == .resolve && $0.incidentID == "r" }
            }
        }
    }

    func testFailedActionRestoresPendingAndReportsError() async {
        let fixture = IncidentsTestFactory.makeFixture()
        let incident = IncidentsTestFactory.makeIncident(id: "f", collection: fixture.collection)
        fixture.monitoring.enqueue(pending: [incident])
        fixture.viewModel.startMonitoring()
        await assertEventually {
            await MainActor.run { fixture.viewModel.pending.count == 1 }
        }
        fixture.source.performError = .unauthorized

        fixture.viewModel.resolve(incident)

        await assertEventually {
            await MainActor.run {
                if case .failed = fixture.viewModel.activity["f"] { return true }
                return false
            }
        }
        XCTAssertEqual(fixture.viewModel.pending.map(\.id), ["f"])
    }

    func testSetPriorityAndDueDateUpdateLocallyAndPerform() async {
        let fixture = IncidentsTestFactory.makeFixture()
        let incident = IncidentsTestFactory.makeIncident(id: "p", collection: fixture.collection)
        fixture.monitoring.enqueue(pending: [incident])
        fixture.viewModel.startMonitoring()
        await assertEventually {
            await MainActor.run { fixture.viewModel.pending.count == 1 }
        }
        let due = DueDateOption.tomorrow.date()

        fixture.viewModel.setPriority(incident, to: .urgente)
        fixture.viewModel.setDueDate(incident, to: due)

        XCTAssertEqual(fixture.viewModel.pending.first?.priority, .urgente)
        XCTAssertEqual(fixture.viewModel.pending.first?.dueOn, IncidentFormatters.isoDay(due))
        await assertEventually {
            await MainActor.run {
                fixture.source.performed.contains { $0.action == .setPriority(.urgente) } &&
                fixture.source.performed.contains { $0.action == .setDueDate(IncidentFormatters.isoDay(due)) }
            }
        }
    }

    func testSimulateAddsDemoIncidentAndCanActWithoutSource() {
        let fixture = IncidentsTestFactory.makeFixture(configured: false)

        fixture.viewModel.simulate(priority: .urgente)

        XCTAssertEqual(fixture.viewModel.pending.count, 1)
        XCTAssertEqual(fixture.viewModel.presence, .attention(.urgente))
        guard let demo = fixture.viewModel.pending.first else { return XCTFail("Missing demo incident") }
        XCTAssertTrue(IncidentDemoData.isDemo(demo))
        XCTAssertTrue(fixture.viewModel.can(.resolve, on: demo))
        if case .arrived(let incidents, let asBatch) = fixture.viewModel.event {
            XCTAssertEqual(incidents.map(\.id), [demo.id])
            XCTAssertFalse(asBatch)
        } else {
            XCTFail("Expected an arrival event")
        }

        fixture.viewModel.markSeen(demo)

        XCTAssertTrue(fixture.viewModel.pending.isEmpty)
        XCTAssertTrue(fixture.monitoring.seen.isEmpty)
    }

    func testStopMonitoringClearsStateAndEmitsPendingChanged() async {
        let fixture = IncidentsTestFactory.makeFixture()
        let incident = IncidentsTestFactory.makeIncident(id: "s", priority: .alta, collection: fixture.collection)
        fixture.monitoring.enqueue(pending: [incident], new: [incident])
        fixture.viewModel.startMonitoring()
        await assertEventually {
            await MainActor.run { fixture.viewModel.pending.count == 1 }
        }

        fixture.viewModel.stopMonitoring()

        XCTAssertFalse(fixture.viewModel.isMonitoring)
        XCTAssertTrue(fixture.viewModel.pending.isEmpty)
        XCTAssertTrue(fixture.viewModel.unattendedLoud.isEmpty)
        XCTAssertEqual(fixture.viewModel.presence, .idle)
        XCTAssertEqual(fixture.viewModel.event, .pendingChanged(0))
    }

    func testConnectionErrorsSurfaceAsConnectionIssue() async {
        let fixture = IncidentsTestFactory.makeFixture()
        fixture.monitoring.enqueue(pending: [], errors: [fixture.collection.id: .unauthorized])

        fixture.viewModel.startMonitoring()

        await assertEventually {
            await MainActor.run { fixture.viewModel.connectionIssue != nil }
        }
        XCTAssertTrue(fixture.viewModel.connectionIssue?.hasPrefix("Alpha:") == true)
    }

    func testNotificationResponseSnoozesIncident() async {
        let fixture = IncidentsTestFactory.makeFixture()
        let incident = IncidentsTestFactory.makeIncident(id: "n", collection: fixture.collection)
        fixture.monitoring.enqueue(pending: [incident])
        fixture.viewModel.startMonitoring()
        await assertEventually {
            await MainActor.run { fixture.viewModel.pending.count == 1 }
        }

        fixture.notifier.respond(IncidentNotifier.Response(incidentID: "n", url: nil, action: .snooze))

        XCTAssertTrue(fixture.viewModel.isSnoozed(incident))
    }

    func testRemoveSourceDropsItsIncidentsAndToken() async {
        let fixture = IncidentsTestFactory.makeFixture()
        let incident = IncidentsTestFactory.makeIncident(id: "x", collection: fixture.collection)
        fixture.monitoring.enqueue(pending: [incident])
        fixture.viewModel.startMonitoring()
        await assertEventually {
            await MainActor.run { fixture.viewModel.pending.count == 1 }
        }

        fixture.viewModel.removeSource(id: IncidentsTestFactory.sourceID)

        XCTAssertFalse(fixture.viewModel.isConfigured)
        XCTAssertTrue(fixture.viewModel.pending.isEmpty)
        XCTAssertNil(fixture.keychain.read(account: IncidentsTestFactory.sourceID))
        XCTAssertNil(fixture.viewModel.identity)
    }
}
