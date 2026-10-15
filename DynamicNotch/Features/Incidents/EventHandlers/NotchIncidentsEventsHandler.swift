import Combine
import Foundation
import NotchwatchCore
import SwiftUI

/// Traduce los eventos del view model de incidencias a estados del notch: live activity siempre
/// visible mientras haya fuente y monitorización, tarjeta de aviso para lo nuevo (o un pulso si el
/// panel está desplegado) y cierre diferido mientras el usuario lo tiene abierto.
@MainActor
final class NotchIncidentsEventsHandler {
    /// Tiempo que tarda el motor en restaurar el live activity tras ocultar una alerta.
    static let alertDismissalDelay: TimeInterval = 0.45

    private let notchViewModel: NotchViewModel
    private let incidentsViewModel: IncidentsViewModel
    private let settingsViewModel: SettingsViewModel
    private var deferredHideWhileExpanded = false
    private var currentAlertIncidentID: String?
    private var cancellables = Set<AnyCancellable>()

    init(
        notchViewModel: NotchViewModel,
        incidentsViewModel: IncidentsViewModel,
        settingsViewModel: SettingsViewModel
    ) {
        self.notchViewModel = notchViewModel
        self.incidentsViewModel = incidentsViewModel
        self.settingsViewModel = settingsViewModel
        incidentsViewModel.onHotKey = { [weak self] in
            self?.toggleExpansion()
        }
        incidentsViewModel.onExpandRequested = { [weak self] in
            self?.expandPanel()
        }
        observeExpansion()
        observeAttention()
    }

    func handle(_ event: IncidentsEvent) {
        switch event {
        case .arrived(let incidents, let asBatch):
            handleArrival(incidents, asBatch: asBatch)
        case .pendingChanged, .connection:
            syncLiveActivity()
        }
    }

    /// Re-envía (o retira) el live activity con el estado actual para que el motor recalcule tamaño.
    func syncLiveActivity() {
        guard incidentsViewModel.isMonitoring, incidentsViewModel.isConfigured else {
            hideLiveActivity()
            return
        }
        deferredHideWhileExpanded = false
        notchViewModel.send(
            .showLiveActivity(
                IncidentsNotchContent(
                    incidentsViewModel: incidentsViewModel,
                    notchViewModel: notchViewModel
                )
            )
        )
        dismissAlertIfStale(unattended: incidentsViewModel.unattendedLoud)
    }

    /// `@Published` avisa antes de cambiar `notchModel`, así que aquí no se vuelve a consultar
    /// `isPanelExpanded`: el cierre diferido se envía directamente, como hace NowPlaying.
    func handleExpansionChange(isExpanded: Bool) {
        if isExpanded, isPanelVisible {
            incidentsViewModel.acknowledgeAll()
            return
        }
        guard !isExpanded else { return }
        incidentsViewModel.resetPanelFilter()
        guard deferredHideWhileExpanded else { return }
        deferredHideWhileExpanded = false
        notchViewModel.send(.hideLiveActivity(id: NotchContentRegistry.Incidents.pending.id))
    }

    /// Atajo global: alterna desplegar y recoger el panel.
    func toggleExpansion() {
        if isPanelExpanded {
            notchViewModel.handleOutsideClick()
            return
        }
        expandPanel()
    }

    /// Despliega el panel; si hay una alerta nuestra delante, la retira primero.
    func expandPanel() {
        if isAlertVisible {
            acknowledgeAlert()
            notchViewModel.hideTemporaryNotification()
            DispatchQueue.main.asyncAfter(deadline: .now() + NotchIncidentsEventsHandler.alertDismissalDelay) { [weak self] in
                self?.expandLiveActivityIfVisible()
            }
            return
        }
        guard isPanelVisible else {
            syncLiveActivity()
            DispatchQueue.main.asyncAfter(deadline: .now() + NotchIncidentsEventsHandler.alertDismissalDelay) { [weak self] in
                self?.expandLiveActivityIfVisible()
            }
            return
        }
        expandLiveActivityIfVisible()
    }

    // MARK: - Privado

    private var isPanelVisible: Bool {
        notchViewModel.notchModel.liveActivityContent?.id == NotchContentRegistry.Incidents.pending.id &&
        notchViewModel.notchModel.temporaryNotificationContent == nil
    }

    private var isPanelExpanded: Bool {
        notchViewModel.notchModel.liveActivityContent?.id == NotchContentRegistry.Incidents.pending.id &&
        notchViewModel.notchModel.isLiveActivityExpanded
    }

    private var isAlertVisible: Bool {
        notchViewModel.notchModel.temporaryNotificationContent?.id == NotchContentRegistry.Incidents.alert.id
    }

    private func handleArrival(_ incidents: [Incident], asBatch: Bool) {
        guard let top = mostImportant(incidents) else { return }
        let isDemo = incidents.contains(where: IncidentDemoData.isDemo)
        guard incidentsViewModel.isMonitoring || isDemo else { return }
        guard incidentsViewModel.alertDecision(for: top).showsAlert else { return }

        if isPanelExpanded {
            notchViewModel.pulseNotch()
            return
        }

        currentAlertIncidentID = top.id
        let duration: TimeInterval = top.priority.isLoud ? .infinity : incidentsViewModel.profile.behavior.alertDuration
        notchViewModel.send(
            .showTemporaryNotification(
                IncidentAlertNotchContent(
                    incidentsViewModel: incidentsViewModel,
                    incident: top,
                    extra: max(0, incidents.count - 1)
                ),
                duration: duration
            )
        )
    }

    private func mostImportant(_ incidents: [Incident]) -> Incident? {
        incidents.max { lhs, rhs in
            if lhs.priority != rhs.priority {
                return lhs.priority < rhs.priority
            }
            return lhs.createdAt < rhs.createdAt
        }
    }

    private func hideLiveActivity() {
        if isPanelExpanded {
            deferredHideWhileExpanded = true
            return
        }
        deferredHideWhileExpanded = false
        notchViewModel.send(.hideLiveActivity(id: NotchContentRegistry.Incidents.pending.id))
    }

    private func expandLiveActivityIfVisible() {
        guard isPanelVisible, !isPanelExpanded else { return }
        notchViewModel.expandActiveLiveActivity()
    }

    private func acknowledgeAlert() {
        guard let currentAlertIncidentID,
              let incident = incidentsViewModel.pending.first(where: { $0.id == currentAlertIncidentID }) else {
            incidentsViewModel.acknowledgeAll()
            return
        }
        incidentsViewModel.acknowledge(incident)
    }

    /// Una alerta fija (alta/urgente) se retira cuando su incidencia se atiende o deja de estar pendiente.
    /// `unattended` llega como parámetro porque `@Published` avisa antes de cambiar el valor.
    private func dismissAlertIfStale(unattended: Set<String>) {
        guard isAlertVisible, let currentAlertIncidentID else { return }
        let isStillPending = incidentsViewModel.pending.contains { $0.id == currentAlertIncidentID }
        let isUnattended = unattended.contains(currentAlertIncidentID)
        let isLoud = incidentsViewModel.pending.first { $0.id == currentAlertIncidentID }?.priority.isLoud ?? false
        guard !isStillPending || (isLoud && !isUnattended) else { return }
        self.currentAlertIncidentID = nil
        notchViewModel.hideTemporaryNotification()
    }

    private func observeExpansion() {
        notchViewModel.$notchModel
            .map(\.isLiveActivityExpanded)
            .removeDuplicates()
            .dropFirst()
            .sink { [weak self] isExpanded in
                self?.handleExpansionChange(isExpanded: isExpanded)
            }
            .store(in: &cancellables)
    }

    private func observeAttention() {
        incidentsViewModel.$unattendedLoud
            .removeDuplicates()
            .dropFirst()
            .sink { [weak self] unattended in
                self?.dismissAlertIfStale(unattended: unattended)
            }
            .store(in: &cancellables)
    }
}
