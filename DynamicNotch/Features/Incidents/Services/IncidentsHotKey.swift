internal import AppKit
import Carbon.HIToolbox
import Foundation
import NotchwatchCore

/// Callback de Carbon. No puede capturar contexto ni estar aislado a un actor.
nonisolated private func handleIncidentsHotKeyEvent(
    _ callRef: EventHandlerCallRef?,
    _ event: EventRef?,
    _ userData: UnsafeMutableRawPointer?
) -> OSStatus {
    var hotKeyID = EventHotKeyID()
    let status = GetEventParameter(
        event,
        EventParamName(kEventParamDirectObject),
        EventParamType(typeEventHotKeyID),
        nil,
        MemoryLayout<EventHotKeyID>.size,
        nil,
        &hotKeyID
    )
    guard status == noErr, hotKeyID.signature == IncidentsHotKey.signature else {
        return OSStatus(eventNotHandledErr)
    }
    Task { @MainActor in
        IncidentsHotKey.fire()
    }
    return noErr
}

/// Atajo de teclado global con `RegisterEventHotKey` (Carbon): funciona con cualquier app delante y
/// no necesita permisos. Se instala en el dispatcher de eventos para que también responda con un
/// menú de la app abierto.
@MainActor
final class IncidentsHotKey {
    /// Firma de los atajos de Notchwatch («NWCH»): así reconocemos nuestros eventos.
    nonisolated static let signature: OSType = 0x4E57_4348
    static let debounceInterval: TimeInterval = 0.3

    private static weak var active: IncidentsHotKey?
    private static var lastFire: TimeInterval = 0

    var action: (@MainActor () -> Void)?

    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?

    init(action: (@MainActor () -> Void)? = nil) {
        self.action = action
    }

    /// Registra el atajo elegido (o lo quita con `.off`). Devuelve un mensaje si no se pudo.
    @discardableResult
    func apply(_ choice: HotKeyChoice) -> String? {
        unregister()
        guard let combo = choice.carbonCombo else { return nil }

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let installed = InstallEventHandler(
            GetEventDispatcherTarget(),
            handleIncidentsHotKeyEvent,
            1,
            &eventType,
            nil,
            &handlerRef
        )
        guard installed == noErr else {
            return String(
                format: L10n.app("incidents.hotKey.error.install", fallback: "The shortcut could not be enabled (error %d)."),
                Int(installed)
            )
        }

        let hotKeyID = EventHotKeyID(signature: IncidentsHotKey.signature, id: 1)
        let registered = RegisterEventHotKey(
            combo.keyCode,
            combo.modifiers,
            hotKeyID,
            GetEventDispatcherTarget(),
            0,
            &hotKeyRef
        )
        guard registered == noErr else {
            unregister()
            if registered == OSStatus(eventHotKeyExistsErr) {
                return String(
                    format: L10n.app("incidents.hotKey.error.taken", fallback: "Another app already uses %@. Choose a different shortcut."),
                    choice.shortcutSymbols
                )
            }
            return String(
                format: L10n.app("incidents.hotKey.error.register", fallback: "%@ could not be enabled (error %d)."),
                choice.shortcutSymbols,
                Int(registered)
            )
        }
        IncidentsHotKey.active = self
        return nil
    }

    func unregister() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }
        if let handlerRef {
            RemoveEventHandler(handlerRef)
            self.handlerRef = nil
        }
        if IncidentsHotKey.active === self {
            IncidentsHotKey.active = nil
        }
    }

    /// Evita que una pulsación mantenida (o doble) abra y cierre la isla de golpe.
    fileprivate static func fire() {
        let now = ProcessInfo.processInfo.systemUptime
        guard now - lastFire > debounceInterval else { return }
        lastFire = now
        active?.action?()
    }
}

extension HotKeyChoice {
    struct CarbonCombo {
        let keyCode: UInt32
        let modifiers: UInt32
    }

    /// Tecla y modificadores en formato Carbon; nil con el atajo desactivado.
    var carbonCombo: CarbonCombo? {
        let controlOptionCommand = UInt32(controlKey | optionKey | cmdKey)
        switch self {
        case .off:
            return nil
        case .controlOptionCommandI:
            return CarbonCombo(keyCode: UInt32(kVK_ANSI_I), modifiers: controlOptionCommand)
        case .controlOptionCommandN:
            return CarbonCombo(keyCode: UInt32(kVK_ANSI_N), modifiers: controlOptionCommand)
        case .optionCommandI:
            return CarbonCombo(keyCode: UInt32(kVK_ANSI_I), modifiers: UInt32(optionKey | cmdKey))
        }
    }

    /// Texto del atajo tal y como se enseña en Ajustes.
    var shortcutSymbols: String {
        switch self {
        case .off:
            return L10n.app("incidents.hotKey.off", fallback: "Off")
        case .controlOptionCommandI:
            return "⌃⌥⌘I"
        case .controlOptionCommandN:
            return "⌃⌥⌘N"
        case .optionCommandI:
            return "⌥⌘I"
        }
    }
}
