import SwiftUI
import XCTest
import NotchwatchCore
@testable import DynamicNotch

@MainActor
final class IncidentsNotchContentTests: XCTestCase {
    private let baseWidth: CGFloat = 190
    private let baseHeight: CGFloat = 38

    private func makeContent(rows: Int, connectionIssue: Bool = false) -> (IncidentsNotchContent, IncidentsTestFactory.Fixture) {
        let fixture = IncidentsTestFactory.makeFixture()
        let settings = TestNotchSettings()
        let notchViewModel = NotchViewModel(settings: settings, hideDelay: 0.01, queueDelay: 0)
        TestLifetime.retain(notchViewModel)
        let incidents = (0..<rows).map { index in
            IncidentsTestFactory.makeIncident(id: "\(index)", collection: fixture.collection)
        }
        fixture.monitoring.enqueue(
            pending: incidents,
            errors: connectionIssue ? [fixture.collection.id: .network("offline")] : [:]
        )
        let content = IncidentsNotchContent(incidentsViewModel: fixture.viewModel, notchViewModel: notchViewModel)
        return (content, fixture)
    }

    private func loadRows(_ fixture: IncidentsTestFactory.Fixture, expected: Int) async {
        fixture.viewModel.startMonitoring()
        await assertEventually {
            await MainActor.run { fixture.viewModel.pending.count == expected && fixture.viewModel.lastPoll != nil }
        }
    }

    func testDescriptorsAndFlags() {
        let (content, _) = makeContent(rows: 0)

        XCTAssertEqual(content.id, "incidents.pending")
        XCTAssertTrue(content.isExpandable)
        XCTAssertNotNil(content.windowLink)
        XCTAssertEqual(content.priority, NotchContentRegistry.Incidents.pending.priority)
    }

    func testCompactSizeKeepsBaseHeightAndAddsWidth() {
        let (content, _) = makeContent(rows: 0)

        let notch = content.size(baseWidth: baseWidth, baseHeight: baseHeight)
        let island = content.dynamicIslandSize(baseWidth: baseWidth, baseHeight: baseHeight)

        XCTAssertEqual(notch.height, baseHeight)
        XCTAssertEqual(island.height, baseHeight)
        XCTAssertGreaterThan(notch.width, baseWidth)
        XCTAssertGreaterThan(island.width, baseWidth)
    }

    func testExpandedHeightGrowsWithRows() async {
        let (single, singleFixture) = makeContent(rows: 1)
        let (several, severalFixture) = makeContent(rows: IncidentsLayout.maxVisibleRows)
        await loadRows(singleFixture, expected: 1)
        await loadRows(severalFixture, expected: IncidentsLayout.maxVisibleRows)

        let singleSize = single.expandedSize(baseWidth: baseWidth, baseHeight: baseHeight)
        let severalSize = several.expandedSize(baseWidth: baseWidth, baseHeight: baseHeight)

        XCTAssertGreaterThan(singleSize.height, baseHeight)
        XCTAssertGreaterThan(severalSize.height, singleSize.height)
        XCTAssertGreaterThan(several.expandedDynamicIslandSize(baseWidth: baseWidth, baseHeight: baseHeight).height, baseHeight)
    }

    func testExpandedHeightIsCappedAtMaxVisibleRows() async {
        let max = IncidentsLayout.maxVisibleRows
        let (capped, cappedFixture) = makeContent(rows: max)
        let (overflow, overflowFixture) = makeContent(rows: max + 4)
        await loadRows(cappedFixture, expected: max)
        await loadRows(overflowFixture, expected: max + 4)

        let cappedSize = capped.expandedSize(baseWidth: baseWidth, baseHeight: baseHeight)
        let overflowSize = overflow.expandedSize(baseWidth: baseWidth, baseHeight: baseHeight)

        XCTAssertEqual(cappedSize.height, overflowSize.height)
        XCTAssertEqual(cappedSize.width, overflowSize.width)
    }

    func testConnectionBannerAddsHeight() async {
        let (plain, plainFixture) = makeContent(rows: 1)
        let (banner, bannerFixture) = makeContent(rows: 1, connectionIssue: true)
        await loadRows(plainFixture, expected: 1)
        await loadRows(bannerFixture, expected: 1)
        await assertEventually {
            await MainActor.run { bannerFixture.viewModel.connectionIssue != nil }
        }

        let plainSize = plain.expandedSize(baseWidth: baseWidth, baseHeight: baseHeight)
        let bannerSize = banner.expandedSize(baseWidth: baseWidth, baseHeight: baseHeight)

        XCTAssertGreaterThanOrEqual(bannerSize.height, plainSize.height)
    }

    func testCornerRadiiComeFromLayout() {
        let (content, _) = makeContent(rows: 0)

        XCTAssertEqual(content.expandedCornerRadius(baseRadius: baseHeight / 3).top, IncidentsLayout.panelCornerRadius.top)
        XCTAssertEqual(content.expandedCornerRadius(baseRadius: baseHeight / 3).bottom, IncidentsLayout.panelCornerRadius.bottom)
        XCTAssertEqual(content.dynamicIslandCornerRadius(baseHeight: baseHeight), baseHeight * 0.5)
    }

    func testAlertContentUsesLayoutSizes() {
        let fixture = IncidentsTestFactory.makeFixture()
        let incident = IncidentsTestFactory.makeIncident(id: "a", priority: .urgente, collection: fixture.collection)
        let content = IncidentAlertNotchContent(incidentsViewModel: fixture.viewModel, incident: incident, extra: 2)

        let size = content.size(baseWidth: baseWidth, baseHeight: baseHeight)
        let island = content.dynamicIslandSize(baseWidth: baseWidth, baseHeight: baseHeight)

        XCTAssertEqual(content.id, "incidents.alert")
        XCTAssertFalse(content.isExpandable)
        XCTAssertFalse(content.isRestorable)
        XCTAssertNotNil(content.windowLink)
        XCTAssertEqual(size, IncidentsLayout.alertSize(baseWidth: baseWidth, baseHeight: baseHeight, isNotchless: false))
        XCTAssertEqual(island, IncidentsLayout.alertSize(baseWidth: baseWidth, baseHeight: baseHeight, isNotchless: true))
        XCTAssertGreaterThan(size.height, baseHeight)
        XCTAssertEqual(content.cornerRadius(baseRadius: baseHeight / 3).top, IncidentsLayout.alertCornerRadius.top)
    }

    func testStrokePaletteParsesHexAndFollowsPresence() {
        let appearance = AppearanceSettings.default

        XCTAssertEqual(IncidentsStrokePalette.color(hex: "#FFFFFF"), Color(red: 1, green: 1, blue: 1))
        XCTAssertEqual(IncidentsStrokePalette.color(hex: "nope"), .white)
        XCTAssertEqual(IncidentsStrokePalette.color(for: .idle, appearance: appearance), Color.white.opacity(IncidentsStrokePalette.idleOpacity))
        XCTAssertNotEqual(
            IncidentsStrokePalette.color(for: .attention(.urgente), appearance: appearance),
            IncidentsStrokePalette.color(for: .pending(.urgente), appearance: appearance)
        )
    }
}
