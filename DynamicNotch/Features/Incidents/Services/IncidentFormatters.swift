import Foundation
import NotchwatchCore

/// Fechas y textos de las incidencias, en el idioma de la app.
enum IncidentFormatters {
    /// «ahora», «hace 3 min», «hace 2 h»…
    static func relative(_ date: Date, now: Date = Date()) -> String {
        if now.timeIntervalSince(date) < 45 {
            return L10n.app("incidents.time.now", fallback: "now")
        }
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = appLocale()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: now)
    }

    /// «17:30» si es hoy, «15 oct 09:00» si no.
    static func time(_ date: Date, calendar: Calendar = .current) -> String {
        let formatter = DateFormatter()
        formatter.locale = appLocale()
        formatter.dateFormat = calendar.isDateInToday(date) ? "HH:mm" : "d MMM HH:mm"
        return formatter.string(from: date)
    }

    /// Fecha en el formato de Asana («YYYY-MM-DD») según el calendario local.
    static func isoDay(_ date: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 1970, parts.month ?? 1, parts.day ?? 1)
    }

    static func parseDay(_ string: String, calendar: Calendar = .current) -> Date? {
        let parts = string.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
    }

    /// «Vence hoy», «Vence mañana», «Venció ayer», «Vence 21 oct»…; nil si la fecha no se entiende.
    static func dueText(_ dueOn: String, now: Date = Date(), calendar: Calendar = .current) -> String? {
        guard let date = parseDay(dueOn, calendar: calendar) else { return nil }
        let today = calendar.startOfDay(for: now)
        let days = calendar.dateComponents([.day], from: today, to: calendar.startOfDay(for: date)).day ?? 0
        switch days {
        case ..<(-1):
            return String(format: L10n.app("incidents.due.overdueDays", fallback: "Overdue by %d d"), -days)
        case -1:
            return L10n.app("incidents.due.yesterday", fallback: "Was due yesterday")
        case 0:
            return L10n.app("incidents.due.today", fallback: "Due today")
        case 1:
            return L10n.app("incidents.due.tomorrow", fallback: "Due tomorrow")
        case 2...6:
            return String(format: L10n.app("incidents.due.inDays", fallback: "Due in %d d"), days)
        default:
            let formatter = DateFormatter()
            formatter.locale = appLocale()
            formatter.dateFormat = "d MMM"
            return String(format: L10n.app("incidents.due.onDate", fallback: "Due %@"), formatter.string(from: date))
        }
    }

    /// true si la fecha de vencimiento ya pasó.
    static func isOverdue(_ dueOn: String?, now: Date = Date(), calendar: Calendar = .current) -> Bool {
        guard let dueOn, let date = parseDay(dueOn, calendar: calendar) else { return false }
        return calendar.startOfDay(for: date) < calendar.startOfDay(for: now)
    }

    static func priorityLabel(_ priority: IncidentPriority) -> String {
        switch priority {
        case .baja:
            return L10n.app("incidents.priority.low", fallback: "Low")
        case .media:
            return L10n.app("incidents.priority.medium", fallback: "Medium")
        case .alta:
            return L10n.app("incidents.priority.high", fallback: "High")
        case .urgente:
            return L10n.app("incidents.priority.urgent", fallback: "Urgent")
        case .ninguna:
            return L10n.app("incidents.priority.none", fallback: "No priority")
        }
    }

    /// Un texto singular/plural a partir de dos claves.
    static func count(_ value: Int, singularKey: String, pluralKey: String, singular: String, plural: String) -> String {
        let format = value == 1
            ? L10n.app(singularKey, fallback: singular)
            : L10n.app(pluralKey, fallback: plural)
        return String(format: format, value)
    }

    static func appLocale() -> Locale {
        DynamicNotchLanguage.resolved(
            UserDefaults.standard.string(forKey: GeneralSettingsStorage.Keys.appLanguage)
        ).locale
    }
}

/// Atajos de fecha de vencimiento del menú de cada incidencia.
enum DueDateOption: CaseIterable, Hashable {
    case today
    case tomorrow
    case inThreeDays
    case nextMonday
    case inOneWeek

    var title: String {
        switch self {
        case .today:
            return L10n.app("incidents.dueOption.today", fallback: "Today")
        case .tomorrow:
            return L10n.app("incidents.dueOption.tomorrow", fallback: "Tomorrow")
        case .inThreeDays:
            return L10n.app("incidents.dueOption.inThreeDays", fallback: "In 3 days")
        case .nextMonday:
            return L10n.app("incidents.dueOption.nextMonday", fallback: "Next Monday")
        case .inOneWeek:
            return L10n.app("incidents.dueOption.inOneWeek", fallback: "In a week")
        }
    }

    func date(from now: Date = Date(), calendar: Calendar = .current) -> Date {
        let today = calendar.startOfDay(for: now)
        switch self {
        case .today:
            return today
        case .tomorrow:
            return calendar.date(byAdding: .day, value: 1, to: today) ?? today
        case .inThreeDays:
            return calendar.date(byAdding: .day, value: 3, to: today) ?? today
        case .inOneWeek:
            return calendar.date(byAdding: .day, value: 7, to: today) ?? today
        case .nextMonday:
            return calendar.nextDate(
                after: today,
                matching: DateComponents(weekday: 2),
                matchingPolicy: .nextTime
            ) ?? today
        }
    }
}
