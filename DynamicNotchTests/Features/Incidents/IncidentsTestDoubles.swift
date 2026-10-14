import Foundation
import NotchwatchCore
@testable import DynamicNotch

/// Monitorización falsa: devuelve los resultados encolados y, sin cola, el estado pendiente fijado.
@MainActor
final class FakeIncidentMonitoring: IncidentMonitoring {
    var pendingSnapshot: [Incident] = []
    private(set) var queuedOutcomes: [PollOutcome] = []
    private(set) var pollCount = 0
    private(set) var seen: [String] = []
    private(set) var snoozed: [(id: String, duration: TimeInterval)] = []
    private(set) var sourceUpdates: [[String]] = []

    func enqueue(pending: [Incident], new: [Incident] = [], errors: [String: SourceError] = [:], date: Date = Date()) {
        queuedOutcomes.append(PollOutcome(newIncidents: new, pending: pending, errors: errors, date: date))
        pendingSnapshot = pending
    }

    func poll() async -> PollOutcome {
        pollCount += 1
        if !queuedOutcomes.isEmpty {
            return queuedOutcomes.removeFirst()
        }
        return PollOutcome(newIncidents: [], pending: pendingSnapshot, errors: [:], date: Date())
    }

    func markSeen(_ id: String) async {
        seen.append(id)
        pendingSnapshot.removeAll { $0.id == id }
    }

    func snooze(_ id: String, for duration: TimeInterval) async {
        snoozed.append((id: id, duration: duration))
    }

    func updateSources(_ sources: [any IncidentSource]) async {
        sourceUpdates.append(sources.map(\.id))
    }
}

/// Fuente falsa que registra las acciones ejecutadas.
final class FakeIncidentSource: IncidentSource, @unchecked Sendable {
    let id: String
    let kind: SourceKind = .asana
    let displayName: String
    var collections: [WatchedCollection]
    var capabilities: SourceCapabilities = [.assignToMe, .resolve, .dueDate, .priority]
    var identityValue = SourceIdentity(userID: "u1", name: "Joan")
    var performError: SourceError?
    var openIncidentsValue: [Incident] = []

    private let lock = NSLock()
    private var recorded: [(action: IncidentAction, incidentID: String)] = []

    var performed: [(action: IncidentAction, incidentID: String)] {
        lock.lock()
        defer { lock.unlock() }
        return recorded
    }

    init(id: String = "src", displayName: String = "Test", collections: [WatchedCollection]) {
        self.id = id
        self.displayName = displayName
        self.collections = collections
    }

    func identity() async throws -> SourceIdentity {
        identityValue
    }

    func openIncidents(in collection: WatchedCollection) async throws -> [Incident] {
        openIncidentsValue.filter { $0.collectionID == collection.id }
    }

    func perform(_ action: IncidentAction, on incident: Incident) async throws {
        if let performError {
            throw performError
        }
        lock.lock()
        recorded.append((action: action, incidentID: incident.id))
        lock.unlock()
    }
}

@MainActor
final class FakeKeychain: KeychainStoring {
    var values: [String: String] = [:]
    var failsSaving = false

    func read(account: String) -> String? {
        values[account]
    }

    @discardableResult
    func save(_ value: String, account: String) -> Bool {
        guard !failsSaving else { return false }
        values[account] = value
        return true
    }

    @discardableResult
    func delete(account: String) -> Bool {
        values[account] = nil
        return true
    }
}

@MainActor
final class FakeIncidentNotifier: IncidentNotifying {
    var onResponse: (@MainActor (IncidentNotifier.Response) -> Void)?
    var permission: IncidentNotifier.Permission = .allowed
    private(set) var authorizationRequests = 0
    private(set) var posted: [NotificationPayload] = []
    private(set) var withdrawn: [String] = []
    private(set) var withdrawAllCount = 0

    func requestAuthorization(_ completion: @escaping @MainActor (IncidentNotifier.Permission) -> Void) {
        authorizationRequests += 1
        completion(permission)
    }

    func currentPermission(_ completion: @escaping @MainActor (IncidentNotifier.Permission) -> Void) {
        completion(permission)
    }

    func post(_ payloads: [NotificationPayload]) {
        posted.append(contentsOf: payloads)
    }

    func withdraw(_ identifiers: [String]) {
        withdrawn.append(contentsOf: identifiers)
    }

    func withdrawAll() {
        withdrawAllCount += 1
    }

    /// Simula que el usuario pulsa una acción de la notificación.
    func respond(_ response: IncidentNotifier.Response) {
        onResponse?(response)
    }
}

/// Construye un view model configurado con una fuente falsa y almacenamiento temporal.
@MainActor
enum IncidentsTestFactory {
    struct Fixture {
        let viewModel: IncidentsViewModel
        let monitoring: FakeIncidentMonitoring
        let source: FakeIncidentSource
        let notifier: FakeIncidentNotifier
        let keychain: FakeKeychain
        let profileStore: IncidentsProfileStore
        let collection: WatchedCollection
    }

    static let sourceID = "src"
    static let token = "token-123"

    static func makeTemporaryDirectory() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("IncidentsTests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static func makeConfig(collection: WatchedCollection) -> AsanaSourceConfig {
        AsanaSourceConfig(
            id: sourceID,
            displayName: "Test",
            workspaceGid: "w1",
            workspaceName: "Workspace",
            projects: [
                AsanaProjectConfig(
                    collection: collection,
                    projectGid: "p1",
                    projectName: "Project",
                    detectedSectionGid: "s-detected",
                    resolvedSectionGid: "s-resolved"
                ),
            ]
        )
    }

    static func makeFixture(configured: Bool = true, now: @escaping () -> Date = { Date() }) -> Fixture {
        let collection = WatchedCollection(id: WatchedCollection.makeID(sourceID: sourceID, key: "a"), name: "Alpha")
        let keychain = FakeKeychain()
        let profileStore = IncidentsProfileStore(directoryURL: makeTemporaryDirectory(), keychain: keychain)
        if configured {
            profileStore.profile.sources = [.asana(makeConfig(collection: collection))]
            keychain.save(token, account: sourceID)
        }
        let monitoring = FakeIncidentMonitoring()
        let source = FakeIncidentSource(collections: [collection])
        let notifier = FakeIncidentNotifier()
        let viewModel = IncidentsViewModel(
            profileStore: profileStore,
            monitoring: monitoring,
            notifier: notifier,
            sound: IncidentSoundPlayer(),
            hotKey: nil,
            makeSource: { _, _ in source },
            now: now
        )
        TestLifetime.retain(viewModel)
        TestLifetime.retain(profileStore)
        return Fixture(
            viewModel: viewModel,
            monitoring: monitoring,
            source: source,
            notifier: notifier,
            keychain: keychain,
            profileStore: profileStore,
            collection: collection
        )
    }

    static func makeIncident(
        id: String,
        priority: IncidentPriority = .media,
        collection: WatchedCollection,
        assigneeID: String? = nil,
        createdAt: Date = Date()
    ) -> Incident {
        Incident(
            id: id,
            collectionID: collection.id,
            collectionName: collection.name,
            name: "Incident \(id)",
            priority: priority,
            createdAt: createdAt,
            assigneeID: assigneeID,
            permalinkURL: URL(string: "https://app.asana.com/0/0/\(id)")
        )
    }
}
