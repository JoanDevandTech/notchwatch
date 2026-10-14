import Foundation
import NotchwatchCore

/// Incidencias de ejemplo para las simulaciones de Ajustes y las previsualizaciones.
enum IncidentDemoData {
    static let sourceID = "demo"
    static let idPrefix = "demo-"

    struct Template {
        let collectionKey: String
        let collectionName: String
        let title: String
        let priority: IncidentPriority
        let reporter: String
        let module: String
        let consoleErrors: Int?
        let dueInDays: Int?
    }

    static let templates: [Template] = [
        Template(collectionKey: "finanzas", collectionName: "Finanzas", title: "La remesa SEPA de esta semana sale duplicada", priority: .urgente, reporter: "Ana", module: "sepa", consoleErrors: 5, dueInDays: 0),
        Template(collectionKey: "operaciones", collectionName: "Operaciones", title: "Traslado del jueves sin driver asignado", priority: .alta, reporter: "Javier Castelao", module: "transfers", consoleErrors: 1, dueInDays: 1),
        Template(collectionKey: "ventas", collectionName: "Ventas", title: "El presupuesto no suma la noche extra en Roncesvalles", priority: .media, reporter: "Maricanto", module: "budgets", consoleErrors: 3, dueInDays: nil),
        Template(collectionKey: "mailing", collectionName: "Mailing", title: "La plantilla de bienvenida no carga las imágenes", priority: .baja, reporter: "Nuria", module: "plantillas", consoleErrors: 2, dueInDays: 4),
        Template(collectionKey: "traslados", collectionName: "Traslados", title: "El conductor no recibe el aviso de cambio de horario", priority: .alta, reporter: "Filipe", module: "drivers", consoleErrors: nil, dueInDays: nil),
        Template(collectionKey: "mitbc", collectionName: "Mi TBC", title: "No puedo fichar la salida desde el portátil", priority: .baja, reporter: "Olalla", module: "jornada", consoleErrors: nil, dueInDays: nil),
        Template(collectionKey: "ventas", collectionName: "Ventas", title: "Lead duplicado al importar desde RRSS", priority: .media, reporter: "Mila", module: "leads", consoleErrors: 1, dueInDays: 2),
        Template(collectionKey: "general", collectionName: "TBC", title: "Error 500 al abrir la reserva 145679", priority: .urgente, reporter: "Isolino", module: "reservations", consoleErrors: 4, dueInDays: nil),
    ]

    /// true si la incidencia es una simulación local (no existe en ninguna fuente).
    static func isDemo(_ incident: Incident) -> Bool {
        incident.id.hasPrefix(idPrefix)
    }

    static func incident(from template: Template, createdAt: Date, calendar: Calendar = .current) -> Incident {
        let due = template.dueInDays.flatMap { days in
            calendar.date(byAdding: .day, value: days, to: calendar.startOfDay(for: createdAt))
        }
        return Incident(
            id: "\(idPrefix)\(UUID().uuidString)",
            collectionID: WatchedCollection.makeID(sourceID: sourceID, key: template.collectionKey),
            collectionName: template.collectionName,
            name: template.title,
            priority: template.priority,
            reporter: template.reporter,
            module: template.module,
            consoleErrors: template.consoleErrors,
            createdAt: createdAt,
            dueOn: due.map { IncidentFormatters.isoDay($0, calendar: calendar) }
        )
    }

    /// Las cuatro primeras plantillas, creadas hace pocos minutos.
    static func initialIncidents(now: Date = Date()) -> [Incident] {
        templates.prefix(4).enumerated().map { offset, template in
            incident(from: template, createdAt: now.addingTimeInterval(-Double(offset + 1) * 140))
        }
    }

    /// Incidencia de prueba con la prioridad pedida (botón «Simular» de Ajustes).
    static func makeIncident(priority: IncidentPriority, now: Date = Date()) -> Incident {
        let base = templates.first { $0.priority == priority } ?? templates[0]
        var result = incident(from: base, createdAt: now)
        result.name = "\(L10n.app("incidents.demo.prefix", fallback: "[Test]")) \(base.title)"
        result.priority = priority
        return result
    }

    /// Una por prioridad, para previsualizaciones.
    static func sample(_ priority: IncidentPriority, now: Date = Date()) -> Incident {
        let base = templates.first { $0.priority == priority } ?? templates[0]
        return incident(from: base, createdAt: now.addingTimeInterval(-50))
    }
}
