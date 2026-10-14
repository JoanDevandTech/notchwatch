import Foundation
import NotchwatchCore

/// Lo que el view model comunica al coordinator del notch.
enum IncidentsEvent: Equatable {
    /// Incidencias nuevas de una lectura; `asBatch` en la primera lectura de la sesión.
    case arrived([Incident], asBatch: Bool)
    /// Cambió el número visible, la presencia o el filtro: hay que re-enviar el live activity.
    case pendingChanged(Int)
    case connection(String?)
}

/// Estado de una acción de fila mientras se ejecuta.
enum IncidentRowActivity: Equatable {
    case working
    case done(String)
    case failed(String)
}

/// Modo que la isla transmite en reposo.
enum IncidentsPresence: Equatable {
    case idle
    case pending(IncidentPriority)
    /// Hay altas o urgentes sin atender.
    case attention(IncidentPriority)
}

/// Fallo de una operación de alta o prueba de una fuente, con texto ya localizado.
/// `nonisolated`: `Error` exige testigos accesibles fuera del actor principal.
nonisolated struct IncidentsFailure: LocalizedError, Equatable {
    let message: String

    init(_ message: String) {
        self.message = message
    }

    var errorDescription: String? { message }
}
