internal import AppKit
import Combine
import Foundation
import NotchwatchCore

@MainActor
final class IncidentsViewModel: ObservableObject {
    typealias SourceFactory = @MainActor (SourceConfig, String) -> any IncidentSource

    /// Tiempo que un resultado de acción («Hecho»/«Error») se mantiene en la fila.
    static let activityResultDuration: TimeInterval = 2.6
    static let snoozeHour = 9

    let profileStore: IncidentsProfileStore
    let sound: IncidentSoundPlayer

    @Published private(set) var pending: [Incident] = []
    @Published private(set) var presence: IncidentsPresence = .idle
    @Published private(set) var arrivalPulse = 0
    @Published private(set) var connectionIssue: String?
    @Published private(set) var identity: SourceIdentity?
    @Published private(set) var activity: [String: IncidentRowActivity] = [:]
    @Published private(set) var lastPoll: Date?
    @Published private(set) var snoozedUntil: [String: Date] = [:]
    /// Altas y urgentes sin atender (para el parpadeo y la repetición del sonido).
    @Published private(set) var unattendedLoud: Set<String> = []
    @Published private(set) var isMonitoring = false
    @Published private(set) var notificationPermission: IncidentNotifier.Permission = .notDetermined
    @Published private(set) var hotKeyError: String?
    /// Lo consume el coordinator.
    @Published var event: IncidentsEvent?

    /// Lo fija el handler del notch: alternar desplegar/recoger el live activity.
    var onHotKey: (@MainActor () -> Void)?
    /// Lo fija el handler del notch: desplegar el panel (botón «Expandir» de la tarjeta de aviso).
    var onExpandRequested: (@MainActor () -> Void)?

    private let monitoring: any IncidentMonitoring
    private let notifier: any IncidentNotifying
    private let hotKey: IncidentsHotKey?
    private let makeSource: SourceFactory
    private let now: () -> Date

    private var sources: [any IncidentSource] = []
    private var localIncidents: [Incident] = []
    private var pollTask: Task<Void, Never>?
    private var loudRepeatTask: Task<Void, Never>?
    private var activityResetTasks: [String: Task<Void, Never>] = [:]
    private var hasPolledThisSession = false
    /// Notificaciones entregadas en esta sesión; se retiran cuando su incidencia se cierra.
    private var deliveredIdentifiers: Set<String> = []
    private var lastEmittedSignature: (count: Int, presence: IncidentsPresence, onlyMine: Bool)?
    private var cancellables = Set<AnyCancellable>()

    init(
        profileStore: IncidentsProfileStore,
        monitoring: any IncidentMonitoring,
        notifier: any IncidentNotifying,
        sound: IncidentSoundPlayer? = nil,
        hotKey: IncidentsHotKey? = nil,
        makeSource: SourceFactory? = nil,
        now: @escaping () -> Date = { Date() }
    ) {
        self.profileStore = profileStore
        self.monitoring = monitoring
        self.notifier = notifier
        self.sound = sound ?? IncidentSoundPlayer()
        self.hotKey = hotKey
        self.makeSource = makeSource ?? IncidentsViewModel.defaultSourceFactory
        self.now = now
        bindProfile()
        bindNotifier()
        hotKey?.action = { [weak self] in
            self?.onHotKey?()
        }
    }

    // MARK: - Estado derivado

    var profile: NotchwatchProfile {
        get { profileStore.profile }
        set { profileStore.profile = newValue }
    }

    /// Alguna fuente con token guardado.
    var isConfigured: Bool {
        profile.sources.contains { profileStore.token(for: $0.id) != nil }
    }

    var showsOnlyMine: Bool {
        profile.behavior.showOnlyMine
    }

    /// Filtro «Mías» aplicado; las activas primero y las pospuestas al final.
    var listedIncidents: [Incident] {
        let filtered = showsOnlyMine ? pending.filter(isMine) : pending
        let active = filtered.filter { !isSnoozed($0) }
        let snoozed = filtered.filter(isSnoozed)
        return active + snoozed
    }

    var visibleCount: Int {
        listedIncidents.filter { !isSnoozed($0) }.count
    }

    var mineCount: Int {
        pending.filter { isMine($0) && !isSnoozed($0) }.count
    }

    var topPendingPriority: IncidentPriority? {
        listedIncidents.filter { !isSnoozed($0) }.map(\.priority).max()
    }

    var isDoNotDisturb: Bool {
        profile.sound.doNotDisturb.isActive(at: now())
    }

    var isMuted: Bool {
        profile.sound.muted
    }

    func isSnoozed(_ incident: Incident) -> Bool {
        guard let until = snoozedUntil[incident.id] else { return false }
        return until > now()
    }

    func isMine(_ incident: Incident) -> Bool {
        incident.isAssigned(toUserID: identity?.userID, name: identity?.name)
    }

    func style(for collectionID: String) -> CollectionStyle {
        profile.collection(id: collectionID)?.style ?? .default
    }

    func can(_ action: IncidentAction, on incident: Incident) -> Bool {
        if IncidentDemoData.isDemo(incident) { return true }
        guard let source = source(for: incident) else { return false }
        return source.capabilities.contains(action.requiredCapability)
    }

    /// Qué hacer al llegar una incidencia de esa prioridad ahora mismo.
    func alertDecision(for incident: Incident) -> AlertDecision {
        profile.sound.decision(for: incident.priority, at: now())
    }

    // MARK: - Monitorización

    func startMonitoring() {
        guard !isMonitoring else { return }
        isMonitoring = true
        hasPolledThisSession = false
        applyHotKey()
        refreshNotificationPermission()
        pollTask = Task { [weak self] in
            await self?.rebuildSources()
            await self?.refreshIdentity()
            while !Task.isCancelled {
                guard let self, self.isMonitoring else { return }
                await self.pollOnce()
                let interval = self.profile.behavior.pollInterval
                try? await Task.sleep(nanoseconds: UInt64(max(interval, 10) * 1_000_000_000))
            }
        }
        emitPendingChanged(force: true)
    }

    func stopMonitoring() {
        guard isMonitoring else { return }
        isMonitoring = false
        pollTask?.cancel()
        pollTask = nil
        loudRepeatTask?.cancel()
        loudRepeatTask = nil
        hotKey?.unregister()
        hotKeyError = nil
        unattendedLoud = []
        pending = localIncidents
        updatePresence()
        emitPendingChanged(force: true)
    }

    func refreshNow() {
        guard isMonitoring else { return }
        Task { [weak self] in
            await self?.pollOnce()
        }
    }

    // MARK: - Atención

    /// Pide al notch que despliegue el panel de incidencias.
    func requestExpand() {
        onExpandRequested?()
    }

    func acknowledge(_ incident: Incident) {
        guard unattendedLoud.remove(incident.id) != nil else { return }
        updatePresence()
        scheduleLoudRepeat()
        emitPendingChanged()
    }

    func acknowledgeAll() {
        guard !unattendedLoud.isEmpty else { return }
        unattendedLoud = []
        updatePresence()
        scheduleLoudRepeat()
        emitPendingChanged()
    }

    // MARK: - Acciones

    func open(_ incident: Incident) {
        acknowledge(incident)
        if IncidentDemoData.isDemo(incident) {
            showActivity(.done(L10n.app("incidents.action.openDemo", fallback: "Test incident: nothing to open")), for: incident.id)
            return
        }
        guard let url = incident.permalinkURL else {
            showActivity(.failed(L10n.app("incidents.action.noLink", fallback: "This incident has no link")), for: incident.id)
            return
        }
        NSWorkspace.shared.open(url)
    }

    func assignToMe(_ incident: Incident) {
        let identity = identity
        run(
            .assignToMe,
            on: incident,
            doneText: L10n.app("incidents.action.assigned", fallback: "Assigned to you"),
            mutate: { updated in
                updated.assigneeID = identity?.userID
                updated.assigneeName = identity?.name
            }
        )
    }

    func resolve(_ incident: Incident) {
        run(
            .resolve,
            on: incident,
            doneText: L10n.app("incidents.action.resolved", fallback: "Moved to verification"),
            removing: true
        )
    }

    func setPriority(_ incident: Incident, to priority: IncidentPriority) {
        run(
            .setPriority(priority),
            on: incident,
            doneText: L10n.app("incidents.action.priorityChanged", fallback: "Priority updated"),
            mutate: { $0.priority = priority }
        )
    }

    func setDueDate(_ incident: Incident, to date: Date?) {
        let dueOn = date.map { IncidentFormatters.isoDay($0) }
        run(
            .setDueDate(dueOn),
            on: incident,
            doneText: L10n.app("incidents.action.dueDateChanged", fallback: "Due date updated"),
            mutate: { $0.dueOn = dueOn }
        )
    }

    func snooze(_ incident: Incident, minutes: Int) {
        snooze(incident, until: now().addingTimeInterval(TimeInterval(minutes) * 60))
    }

    func snoozeUntilTomorrow(_ incident: Incident) {
        let calendar = Calendar.current
        let tomorrow = calendar.nextDate(
            after: now(),
            matching: DateComponents(hour: IncidentsViewModel.snoozeHour, minute: 0),
            matchingPolicy: .nextTime
        ) ?? now().addingTimeInterval(24 * 3600)
        snooze(incident, until: tomorrow)
    }

    func markSeen(_ incident: Incident) {
        acknowledge(incident)
        pending.removeAll { $0.id == incident.id }
        localIncidents.removeAll { $0.id == incident.id }
        snoozedUntil[incident.id] = nil
        notifier.withdraw([incident.id])
        updatePresence()
        emitPendingChanged()
        guard !IncidentDemoData.isDemo(incident) else { return }
        Task { [monitoring] in
            await monitoring.markSeen(incident.id)
        }
    }

    // MARK: - Preferencias rápidas

    func setShowOnlyMine(_ onlyMine: Bool) {
        guard profile.behavior.showOnlyMine != onlyMine else { return }
        profile.behavior.showOnlyMine = onlyMine
    }

    func toggleMuted() {
        profile.sound.muted.toggle()
        if profile.sound.muted {
            loudRepeatTask?.cancel()
            loudRepeatTask = nil
        } else {
            scheduleLoudRepeat()
        }
    }

    func setDoNotDisturb(_ manual: DoNotDisturb.Manual) {
        profile.sound.doNotDisturb.manual = manual
    }

    func previewSound(_ motif: SoundMotif) {
        sound.play(motif, volume: profile.sound.volume)
    }

    /// Incidencia local de prueba: se comporta como una recién llegada.
    func simulate(priority: IncidentPriority) {
        let incident = IncidentDemoData.makeIncident(priority: priority, now: now())
        localIncidents.append(incident)
        pending = IncidentsViewModel.ordered(pending + [incident])
        handleArrivals([incident], asBatch: false)
    }

    // MARK: - Fuentes

    func saveAsanaSource(_ config: AsanaSourceConfig, token: String) async -> Result<SourceIdentity, IncidentsFailure> {
        guard let token = Text.nonEmpty(token) else {
            return .failure(IncidentsFailure(L10n.app("incidents.source.error.emptyToken", fallback: "Paste a personal access token first")))
        }
        do {
            let identity = try await makeDiscoveryClient(token: token).me()
            guard profileStore.saveToken(token, for: config.id) else {
                return .failure(IncidentsFailure(L10n.app("incidents.source.error.keychain", fallback: "The token could not be saved in the Keychain")))
            }
            upsert(.asana(config))
            self.identity = identity
            await rebuildSources()
            refreshNow()
            emitPendingChanged(force: true)
            return .success(identity)
        } catch {
            return .failure(IncidentsFailure(describe(error)))
        }
    }

    func applyTubuencaminoPreset(token: String) async -> Result<SourceIdentity, IncidentsFailure> {
        await saveAsanaSource(AsanaPresets.tubuencamino, token: token)
    }

    func removeSource(id: String) {
        let removedCollections = Set(profile.sources.filter { $0.id == id }.flatMap { $0.collections.map(\.id) })
        profile.sources.removeAll { $0.id == id }
        profileStore.deleteToken(for: id)
        pending.removeAll { removedCollections.contains($0.collectionID) }
        unattendedLoud = unattendedLoud.filter { id in pending.contains { $0.id == id } }
        if !isConfigured {
            identity = nil
            connectionIssue = nil
        }
        updatePresence()
        emitPendingChanged(force: true)
        Task { [weak self] in
            await self?.rebuildSources()
        }
    }

    func makeDiscoveryClient(token: String) -> AsanaClient {
        AsanaClient(token: token)
    }

    // MARK: - Notificaciones

    func requestNotificationPermission() {
        notifier.requestAuthorization { [weak self] permission in
            self?.notificationPermission = permission
        }
    }

    func openNotificationSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension") else { return }
        NSWorkspace.shared.open(url)
    }
}

// MARK: - Privado

private extension IncidentsViewModel {
    static let defaultSourceFactory: SourceFactory = { config, token in
        switch config {
        case .asana(let asanaConfig):
            return AsanaSource(config: asanaConfig, token: token)
        }
    }

    /// Orden: prioridad desc, fecha desc e id como desempate estable.
    static func ordered(_ incidents: [Incident]) -> [Incident] {
        incidents.sorted { lhs, rhs in
            if lhs.priority != rhs.priority {
                return lhs.priority > rhs.priority
            }
            if lhs.createdAt != rhs.createdAt {
                return lhs.createdAt > rhs.createdAt
            }
            return lhs.id < rhs.id
        }
    }

    func bindProfile() {
        profileStore.objectWillChange
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)

        profileStore.$profile
            .map(\.behavior.hotKey)
            .removeDuplicates()
            .dropFirst()
            .sink { [weak self] _ in
                self?.applyHotKey()
            }
            .store(in: &cancellables)

        profileStore.$profile
            .map(\.behavior.showOnlyMine)
            .removeDuplicates()
            .dropFirst()
            .sink { [weak self] _ in
                self?.updatePresence()
                self?.emitPendingChanged()
            }
            .store(in: &cancellables)

        profileStore.$profile
            .map(\.sources)
            .removeDuplicates()
            .dropFirst()
            .sink { [weak self] _ in
                guard let self, isMonitoring else { return }
                Task { [weak self] in
                    await self?.rebuildSources()
                    self?.refreshNow()
                }
            }
            .store(in: &cancellables)
    }

    func bindNotifier() {
        notifier.onResponse = { [weak self] response in
            self?.handleNotificationResponse(response)
        }
    }

    func handleNotificationResponse(_ response: IncidentNotifier.Response) {
        guard let incidentID = response.incidentID,
              let incident = pending.first(where: { $0.id == incidentID }) else {
            if response.action == .open, let url = response.url {
                NSWorkspace.shared.open(url)
            }
            return
        }
        switch response.action {
        case .open:
            open(incident)
        case .assign:
            assignToMe(incident)
        case .snooze:
            snooze(incident, minutes: 60)
        case .dismissed:
            break
        }
    }

    func applyHotKey() {
        guard let hotKey, isMonitoring else { return }
        hotKeyError = hotKey.apply(profile.behavior.hotKey)
    }

    func refreshNotificationPermission() {
        notifier.currentPermission { [weak self] permission in
            self?.notificationPermission = permission
        }
    }

    func rebuildSources() async {
        sources = profile.sources.compactMap { config in
            profileStore.token(for: config.id).map { makeSource(config, $0) }
        }
        await monitoring.updateSources(sources)
    }

    func refreshIdentity() async {
        guard let source = sources.first else {
            identity = nil
            return
        }
        do {
            identity = try await source.identity()
        } catch {
            setConnectionIssue(describe(error))
        }
    }

    func source(for incident: Incident) -> (any IncidentSource)? {
        sources.first { source in
            source.collections.contains { $0.id == incident.collectionID }
        }
    }

    func upsert(_ config: SourceConfig) {
        var sources = profile.sources
        if let index = sources.firstIndex(where: { $0.id == config.id }) {
            sources[index] = config
        } else {
            sources.append(config)
        }
        profile.sources = sources
    }

    // MARK: Lecturas

    func pollOnce() async {
        let outcome = await monitoring.poll()
        guard isMonitoring else { return }
        apply(outcome)
    }

    func apply(_ outcome: PollOutcome) {
        let isFirstPoll = !hasPolledThisSession
        hasPolledThisSession = true
        lastPoll = outcome.date

        pending = IncidentsViewModel.ordered(outcome.pending + localIncidents)
        let openIDs = Set(pending.map(\.id))
        snoozedUntil = snoozedUntil.filter { openIDs.contains($0.key) && $0.value > outcome.date }
        for incident in outcome.newIncidents {
            snoozedUntil[incident.id] = nil
        }
        unattendedLoud = unattendedLoud.filter { openIDs.contains($0) }
        withdrawClosedNotifications(openIDs: openIDs)

        setConnectionIssue(connectionMessage(for: outcome.errors))

        if outcome.newIncidents.isEmpty {
            updatePresence()
            emitPendingChanged()
        } else {
            handleArrivals(outcome.newIncidents, asBatch: isFirstPoll)
        }
    }

    func withdrawClosedNotifications(openIDs: Set<String>) {
        let closed = deliveredIdentifiers.subtracting(openIDs).subtracting([NotificationPlanner.summaryIdentifier])
        guard !closed.isEmpty else { return }
        deliveredIdentifiers.subtract(closed)
        notifier.withdraw(Array(closed))
    }

    func handleArrivals(_ incidents: [Incident], asBatch: Bool) {
        arrivalPulse += 1
        for incident in incidents where alertDecision(for: incident).repeats {
            unattendedLoud.insert(incident.id)
        }
        updatePresence()
        playArrivalSound(for: incidents)
        postNotifications(for: incidents, asBatch: asBatch)
        scheduleLoudRepeat()
        // Primero el live activity (el motor lo deja suspendido bajo la tarjeta) y después el aviso.
        emitPendingChanged(force: true)
        event = .arrived(incidents, asBatch: asBatch)
    }

    func playArrivalSound(for incidents: [Incident]) {
        guard let top = IncidentsViewModel.ordered(incidents).first else { return }
        guard let motif = alertDecision(for: top).motif else { return }
        sound.play(motif, volume: profile.sound.volume)
    }

    func postNotifications(for incidents: [Incident], asBatch: Bool) {
        guard profile.behavior.systemNotifications, notificationPermission == .allowed else { return }
        let audible = incidents.filter { alertDecision(for: $0).showsAlert }
        guard !audible.isEmpty else { return }
        let payloads = NotificationPlanner.payloads(for: audible, asBatch: asBatch, strings: makeNotificationStrings())
        deliveredIdentifiers.formUnion(payloads.map(\.identifier))
        notifier.post(payloads)
    }

    func scheduleLoudRepeat() {
        loudRepeatTask?.cancel()
        loudRepeatTask = nil
        guard isMonitoring, profile.sound.repeatsLoud, !profile.sound.muted, !unattendedLoud.isEmpty else { return }
        let interval = max(profile.sound.loudRepeatInterval, 5)
        loudRepeatTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
            guard !Task.isCancelled, let self else { return }
            self.repeatLoudSound()
        }
    }

    func repeatLoudSound() {
        let loud = pending.filter { unattendedLoud.contains($0.id) && !isSnoozed($0) }
        guard let top = IncidentsViewModel.ordered(loud).first else {
            unattendedLoud = []
            updatePresence()
            return
        }
        if let motif = alertDecision(for: top).motif {
            sound.play(motif, volume: profile.sound.volume)
        }
        scheduleLoudRepeat()
    }

    func updatePresence() {
        let active = listedIncidents.filter { !isSnoozed($0) }
        let loud = active.filter { unattendedLoud.contains($0.id) }
        let newPresence: IncidentsPresence
        if let top = loud.map(\.priority).max() {
            newPresence = .attention(top)
        } else if let top = active.map(\.priority).max() {
            newPresence = .pending(top)
        } else {
            newPresence = .idle
        }
        if presence != newPresence {
            presence = newPresence
        }
    }

    /// Re-envía el live activity solo cuando cambia algo que afecta a su tamaño o aspecto.
    func emitPendingChanged(force: Bool = false) {
        let signature = (count: visibleCount, presence: presence, onlyMine: showsOnlyMine)
        if !force, let last = lastEmittedSignature,
           last.count == signature.count, last.presence == signature.presence, last.onlyMine == signature.onlyMine {
            return
        }
        lastEmittedSignature = signature
        event = .pendingChanged(signature.count)
    }

    func setConnectionIssue(_ message: String?) {
        guard connectionIssue != message else { return }
        connectionIssue = message
        event = .connection(message)
    }

    func connectionMessage(for errors: [String: SourceError]) -> String? {
        guard let (collectionID, error) = errors.sorted(by: { $0.key < $1.key }).first else { return nil }
        let name = profile.collection(id: collectionID)?.name ?? collectionID
        return "\(name): \(describe(error))"
    }

    // MARK: Acciones

    func snooze(_ incident: Incident, until date: Date) {
        acknowledge(incident)
        snoozedUntil[incident.id] = date
        notifier.withdraw([incident.id])
        updatePresence()
        emitPendingChanged()
        guard !IncidentDemoData.isDemo(incident) else { return }
        let duration = date.timeIntervalSince(now())
        Task { [monitoring] in
            await monitoring.snooze(incident.id, for: duration)
        }
    }

    func run(
        _ action: IncidentAction,
        on incident: Incident,
        doneText: String,
        mutate: ((inout Incident) -> Void)? = nil,
        removing: Bool = false
    ) {
        acknowledge(incident)
        let snapshot = pending
        activity[incident.id] = .working
        if removing {
            pending.removeAll { $0.id == incident.id }
            localIncidents.removeAll { $0.id == incident.id }
        } else if let mutate, let index = pending.firstIndex(where: { $0.id == incident.id }) {
            mutate(&pending[index])
            if let localIndex = localIncidents.firstIndex(where: { $0.id == incident.id }) {
                mutate(&localIncidents[localIndex])
            }
        }
        updatePresence()
        emitPendingChanged()

        if IncidentDemoData.isDemo(incident) {
            showActivity(.done(doneText), for: incident.id)
            return
        }
        guard let source = source(for: incident) else {
            pending = snapshot
            showActivity(.failed(L10n.app("incidents.action.noSource", fallback: "No source for this incident")), for: incident.id)
            return
        }
        Task { [weak self] in
            do {
                try await source.perform(action, on: incident)
                self?.showActivity(.done(doneText), for: incident.id)
                self?.refreshNow()
            } catch {
                guard let self else { return }
                self.pending = snapshot
                self.updatePresence()
                self.emitPendingChanged()
                self.showActivity(.failed(self.describe(error)), for: incident.id)
            }
        }
    }

    func showActivity(_ state: IncidentRowActivity, for id: String) {
        activity[id] = state
        activityResetTasks[id]?.cancel()
        activityResetTasks[id] = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(IncidentsViewModel.activityResultDuration * 1_000_000_000))
            guard !Task.isCancelled else { return }
            self?.activity[id] = nil
            self?.activityResetTasks[id] = nil
        }
    }

    func describe(_ error: Error) -> String {
        guard let sourceError = error as? SourceError else {
            return error.localizedDescription
        }
        switch sourceError {
        case .unauthorized:
            return L10n.app("incidents.error.unauthorized", fallback: "The token is not valid or has expired")
        case .rateLimited:
            return L10n.app("incidents.error.rateLimited", fallback: "Asana is rate limiting requests; retrying shortly")
        case .network(let detail):
            return String(format: L10n.app("incidents.error.network", fallback: "No connection (%@)"), detail)
        case .http(let status, let detail):
            return String(format: L10n.app("incidents.error.http", fallback: "Asana answered %d: %@"), status, detail)
        case .decoding(let detail):
            return String(format: L10n.app("incidents.error.decoding", fallback: "Unexpected answer: %@"), detail)
        case .invalidConfiguration(let detail):
            return String(format: L10n.app("incidents.error.configuration", fallback: "Configuration problem: %@"), detail)
        }
    }

    /// Textos de las notificaciones, resueltos aquí (en el hilo principal) y capturados como valores
    /// para que las clausuras `@Sendable` del núcleo no toquen `L10n`.
    func makeNotificationStrings() -> NotificationStrings {
        let labels = Dictionary(uniqueKeysWithValues: IncidentPriority.allCases.map { ($0, IncidentFormatters.priorityLabel($0)) })
        let reportedBy = L10n.app("incidents.notification.reportedBy", fallback: "Reported by %@")
        let oneError = L10n.app("incidents.notification.consoleErrors.one", fallback: "%d console error")
        let manyErrors = L10n.app("incidents.notification.consoleErrors.many", fallback: "%d console errors")
        let oneNew = L10n.app("incidents.notification.new.one", fallback: "%d new incident")
        let manyNew = L10n.app("incidents.notification.new.many", fallback: "%d new incidents")
        let onePending = L10n.app("incidents.notification.pending.one", fallback: "%d pending incident")
        let manyPending = L10n.app("incidents.notification.pending.many", fallback: "%d pending incidents")
        let mostImportant = L10n.app("incidents.notification.mostImportant", fallback: "Most important: %@")
        let andMore = L10n.app("incidents.notification.andMore", fallback: "%@ and %d more")
        return NotificationStrings(
            priorityLabel: { labels[$0] ?? $0.rawValue },
            reportedBy: { String(format: reportedBy, $0) },
            consoleErrors: { String(format: $0 == 1 ? oneError : manyErrors, $0) },
            newIncidents: { String(format: $0 == 1 ? oneNew : manyNew, $0) },
            pendingIncidents: { String(format: $0 == 1 ? onePending : manyPending, $0) },
            mostImportant: { String(format: mostImportant, $0) },
            andMore: { String(format: andMore, $0, $1) }
        )
    }
}
