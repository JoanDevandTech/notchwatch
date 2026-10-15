internal import AppKit
import Combine
import SwiftUI

/// Mientras un menú de las filas está abierto, bloquea el notch (`isNotchLocked`) para que el clic
/// en el menú no cuente como clic fuera y recoja el panel. Precedente: `CameraNotchView`.
final class IncidentsMenuLock {
    private static let lockKey = "isNotchLocked"
    private var observers: [NSObjectProtocol] = []
    private var isLockedByMenu = false

    func start() {
        guard observers.isEmpty else { return }
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: NSMenu.didBeginTrackingNotification, object: nil, queue: .main) { _ in
            UserDefaults.standard.set(true, forKey: IncidentsMenuLock.lockKey)
        })
        observers.append(center.addObserver(forName: NSMenu.didEndTrackingNotification, object: nil, queue: .main) { _ in
            UserDefaults.standard.set(false, forKey: IncidentsMenuLock.lockKey)
        })
        isLockedByMenu = true
    }

    func stop() {
        observers.forEach { NotificationCenter.default.removeObserver($0) }
        observers.removeAll()
        if isLockedByMenu {
            UserDefaults.standard.set(false, forKey: IncidentsMenuLock.lockKey)
            isLockedByMenu = false
        }
    }
}

private struct IncidentsMenuLockModifier: ViewModifier {
    @State private var lock = IncidentsMenuLock()

    func body(content: Content) -> some View {
        content
            .onAppear { lock.start() }
            .onDisappear { lock.stop() }
    }
}

extension View {
    /// Instalar una sola vez, en la raíz del panel desplegado.
    func incidentsMenuLock() -> some View {
        modifier(IncidentsMenuLockModifier())
    }
}
