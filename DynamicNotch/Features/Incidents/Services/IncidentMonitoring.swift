import Foundation
import NotchwatchCore

/// Monitorización detrás de un protocolo para poder falsearla en tests.
nonisolated protocol IncidentMonitoring: AnyObject, Sendable {
    func poll() async -> PollOutcome
    func markSeen(_ id: String) async
    func snooze(_ id: String, for duration: TimeInterval) async
    func updateSources(_ sources: [any IncidentSource]) async
}

/// Envuelve el actor `IncidentMonitor` del núcleo.
nonisolated final class LiveIncidentMonitoring: IncidentMonitoring {
    private let monitor: IncidentMonitor

    init(storeURL: URL, sources: [any IncidentSource] = []) {
        self.monitor = IncidentMonitor(sources: sources, storeURL: storeURL)
    }

    func poll() async -> PollOutcome {
        await monitor.poll()
    }

    func markSeen(_ id: String) async {
        await monitor.markSeen(id)
    }

    func snooze(_ id: String, for duration: TimeInterval) async {
        await monitor.snooze(id, for: duration)
    }

    func updateSources(_ sources: [any IncidentSource]) async {
        await monitor.updateSources(sources)
    }
}

/// No consulta nada: se usa en tests y cuando la feature no está disponible.
nonisolated final class InactiveIncidentMonitoring: IncidentMonitoring {
    func poll() async -> PollOutcome {
        PollOutcome(newIncidents: [], pending: [], errors: [:], date: Date())
    }

    func markSeen(_ id: String) async {}

    func snooze(_ id: String, for duration: TimeInterval) async {}

    func updateSources(_ sources: [any IncidentSource]) async {}
}
