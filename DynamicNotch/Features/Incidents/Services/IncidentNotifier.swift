import Foundation
import NotchwatchCore
import UserNotifications
import os

/// Notificaciones del Centro de notificaciones detrás de un protocolo (los tests no tocan
/// `UNUserNotificationCenter`).
protocol IncidentNotifying: AnyObject {
    var onResponse: (@MainActor (IncidentNotifier.Response) -> Void)? { get set }
    func requestAuthorization(_ completion: @escaping @MainActor (IncidentNotifier.Permission) -> Void)
    func currentPermission(_ completion: @escaping @MainActor (IncidentNotifier.Permission) -> Void)
    func post(_ payloads: [NotificationPayload])
    func withdraw(_ identifiers: [String])
    func withdrawAll()
}

/// Notificaciones de macOS para incidencias. UserNotifications exige un bundle con identificador:
/// fuera de la app (p. ej. en un ejecutable suelto) se usa `InactiveIncidentNotifier`.
final class IncidentNotifier: NSObject, IncidentNotifying, UNUserNotificationCenterDelegate {
    enum Permission: Equatable {
        case unavailable
        case notDetermined
        case allowed
        case denied
    }

    enum Action: Equatable {
        case open
        case startProgress
        case assign
        case snooze
        case dismissed

        static let startProgressIdentifier = "com.joandev.notchwatch.startProgress"
        static let assignIdentifier = "com.joandev.notchwatch.assign"
        static let snoozeIdentifier = "com.joandev.notchwatch.snooze"
        static let openIdentifier = "com.joandev.notchwatch.open"

        init(responseIdentifier: String) {
            switch responseIdentifier {
            case Action.startProgressIdentifier:
                self = .startProgress
            case Action.assignIdentifier:
                self = .assign
            case Action.snoozeIdentifier:
                self = .snooze
            case Action.openIdentifier, UNNotificationDefaultActionIdentifier:
                self = .open
            default:
                self = .dismissed
            }
        }
    }

    /// Qué pulsó el usuario en una notificación.
    struct Response: Equatable, Sendable {
        let incidentID: String?
        let url: URL?
        let action: Action
    }

    static let categoryIdentifier = "com.joandev.notchwatch.incident"

    nonisolated static var isSupported: Bool {
        Bundle.main.bundleIdentifier != nil
    }

    var onResponse: (@MainActor (Response) -> Void)?

    private let center: UNUserNotificationCenter
    private let log = Logger(subsystem: "com.joandev.notchwatch", category: "notifications")

    /// nil si el proceso no puede notificar.
    static func make() -> IncidentNotifier? {
        guard isSupported else { return nil }
        return IncidentNotifier(center: UNUserNotificationCenter.current())
    }

    private init(center: UNUserNotificationCenter) {
        self.center = center
        super.init()
        center.delegate = self
        center.setNotificationCategories([IncidentNotifier.makeCategory()])
    }

    private static func makeCategory() -> UNNotificationCategory {
        let open = UNNotificationAction(
            identifier: Action.openIdentifier,
            title: L10n.app("incidents.notification.action.open", fallback: "Open"),
            options: [.foreground]
        )
        let startProgress = UNNotificationAction(
            identifier: Action.startProgressIdentifier,
            title: L10n.app("incidents.notification.action.startProgress", fallback: "In progress"),
            options: []
        )
        let assign = UNNotificationAction(
            identifier: Action.assignIdentifier,
            title: L10n.app("incidents.notification.action.assign", fallback: "Assign to me"),
            options: []
        )
        let snooze = UNNotificationAction(
            identifier: Action.snoozeIdentifier,
            title: L10n.app("incidents.notification.action.snooze", fallback: "Snooze 1 h"),
            options: []
        )
        return UNNotificationCategory(
            identifier: categoryIdentifier,
            actions: [open, startProgress, assign, snooze],
            intentIdentifiers: [],
            options: []
        )
    }

    func requestAuthorization(_ completion: @escaping @MainActor (Permission) -> Void) {
        center.requestAuthorization(options: [.alert]) { granted, _ in
            Task { @MainActor in
                completion(granted ? .allowed : .denied)
            }
        }
    }

    func currentPermission(_ completion: @escaping @MainActor (Permission) -> Void) {
        center.getNotificationSettings { settings in
            let status = settings.authorizationStatus
            Task { @MainActor in
                completion(IncidentNotifier.permission(for: status))
            }
        }
    }

    private static func permission(for status: UNAuthorizationStatus) -> Permission {
        switch status {
        case .authorized, .provisional:
            return .allowed
        case .denied:
            return .denied
        case .notDetermined:
            return .notDetermined
        @unknown default:
            return .allowed
        }
    }

    func post(_ payloads: [NotificationPayload]) {
        // macOS apila arriba la última entregada: se envían de menos a más importante.
        for payload in payloads.reversed() {
            let request = UNNotificationRequest(
                identifier: payload.identifier,
                content: makeContent(for: payload),
                trigger: nil
            )
            center.add(request) { [log] error in
                if let error {
                    log.error("No se pudo notificar: \(error.localizedDescription, privacy: .public)")
                }
            }
        }
    }

    func makeContent(for payload: NotificationPayload) -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        content.title = payload.title
        content.subtitle = payload.subtitle
        content.body = payload.body
        content.threadIdentifier = payload.threadIdentifier
        if !payload.isSummary {
            content.categoryIdentifier = IncidentNotifier.categoryIdentifier
        }
        var info: [String: String] = [:]
        if let incidentID = payload.incidentGid {
            info["incidentID"] = incidentID
        }
        if let url = payload.url {
            info["url"] = url.absoluteString
        }
        content.userInfo = info
        return content
    }

    func withdraw(_ identifiers: [String]) {
        guard !identifiers.isEmpty else { return }
        center.removeDeliveredNotifications(withIdentifiers: identifiers)
    }

    func withdrawAll() {
        center.removeAllDeliveredNotifications()
    }

    // MARK: UNUserNotificationCenterDelegate

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .list])
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let info = response.notification.request.content.userInfo
        let incidentID = info["incidentID"] as? String
        let url = (info["url"] as? String).flatMap { URL(string: $0) }
        let actionIdentifier = response.actionIdentifier
        Task { @MainActor [weak self] in
            let reply = Response(
                incidentID: incidentID,
                url: url,
                action: Action(responseIdentifier: actionIdentifier)
            )
            self?.onResponse?(reply)
        }
        completionHandler()
    }
}

/// No notifica nada: tests y procesos sin bundle.
final class InactiveIncidentNotifier: IncidentNotifying {
    var onResponse: (@MainActor (IncidentNotifier.Response) -> Void)?

    func requestAuthorization(_ completion: @escaping @MainActor (IncidentNotifier.Permission) -> Void) {
        completion(.unavailable)
    }

    func currentPermission(_ completion: @escaping @MainActor (IncidentNotifier.Permission) -> Void) {
        completion(.unavailable)
    }

    func post(_ payloads: [NotificationPayload]) {}

    func withdraw(_ identifiers: [String]) {}

    func withdrawAll() {}
}
