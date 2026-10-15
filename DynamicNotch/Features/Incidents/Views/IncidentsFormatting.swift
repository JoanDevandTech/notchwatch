import Foundation
import NotchwatchCore

/// Textos derivados de fechas y contadores que comparten la tarjeta de aviso y el panel.
enum IncidentsFormatting {
    static var locale: Locale {
        DynamicNotchLanguage.resolved(
            UserDefaults.standard.string(forKey: GeneralSettingsStorage.Keys.appLanguage)
        ).locale
    }

    static func relativeAge(of date: Date, now: Date = Date()) -> String {
        let seconds = max(0, now.timeIntervalSince(date))
        if seconds < 60 {
            return L10n.app("incidents.island.time.now", fallback: "now")
        }
        let minutes = Int(seconds / 60)
        if minutes < 60 {
            return format("incidents.island.time.minutesAgo", fallback: "%d min ago", minutes)
        }
        let hours = minutes / 60
        if hours < 24 {
            return format("incidents.island.time.hoursAgo", fallback: "%d h ago", hours)
        }
        return format("incidents.island.time.daysAgo", fallback: "%d d ago", hours / 24)
    }

    static func lastUpdated(_ date: Date?, now: Date = Date()) -> String {
        guard let date else {
            return L10n.app("incidents.island.footer.neverUpdated", fallback: "Not updated yet")
        }
        let seconds = max(0, now.timeIntervalSince(date))
        if seconds < 60 {
            return L10n.app("incidents.island.footer.updatedNow", fallback: "Updated just now")
        }
        let minutes = Int(seconds / 60)
        if minutes < 60 {
            return format("incidents.island.footer.updatedMinutesAgo", fallback: "Updated %d min ago", minutes)
        }
        return format("incidents.island.footer.updatedHoursAgo", fallback: "Updated %d h ago", minutes / 60)
    }

    static func due(_ dueOn: String?, now: Date = Date(), calendar: Calendar = .current) -> String {
        guard let dueOn, let date = parseDay(dueOn, calendar: calendar) else {
            return L10n.app("incidents.island.due.none", fallback: "No due date")
        }
        let today = calendar.startOfDay(for: now)
        let days = calendar.dateComponents([.day], from: today, to: calendar.startOfDay(for: date)).day ?? 0
        switch days {
        case ..<0:
            return format("incidents.island.due.overdue", fallback: "Overdue %d d", -days)
        case 0:
            return L10n.app("incidents.island.due.today", fallback: "Due today")
        case 1:
            return L10n.app("incidents.island.due.tomorrow", fallback: "Due tomorrow")
        default:
            return format("incidents.island.due.inDays", fallback: "Due in %d d", days)
        }
    }

    static func isOverdue(_ dueOn: String?, now: Date = Date(), calendar: Calendar = .current) -> Bool {
        guard let dueOn, let date = parseDay(dueOn, calendar: calendar) else { return false }
        return calendar.startOfDay(for: date) < calendar.startOfDay(for: now)
    }

    static func consoleErrors(_ count: Int) -> String {
        if count == 1 {
            return L10n.app("incidents.island.errors.one", fallback: "1 error")
        }
        return format("incidents.island.errors.many", fallback: "%d errors", count)
    }

    static func more(_ count: Int) -> String {
        format("incidents.island.alert.more", fallback: "+%d more", count)
    }

    static func priorityName(_ priority: IncidentPriority) -> String {
        switch priority {
        case .urgente: return L10n.app("incidents.island.priority.urgente", fallback: "Urgent")
        case .alta: return L10n.app("incidents.island.priority.alta", fallback: "High")
        case .media: return L10n.app("incidents.island.priority.media", fallback: "Medium")
        case .baja: return L10n.app("incidents.island.priority.baja", fallback: "Low")
        case .ninguna: return L10n.app("incidents.island.priority.ninguna", fallback: "None")
        }
    }

    static func snoozedUntil(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return format("incidents.island.snoozedUntil", fallback: "Snoozed until %@", formatter.string(from: date))
    }

    static func initials(of name: String) -> String {
        let parts = name.split(separator: " ").prefix(2)
        let letters = parts.compactMap { $0.first.map(String.init) }
        return letters.joined().uppercased()
    }

    private static func parseDay(_ value: String, calendar: Calendar) -> Date? {
        let pieces = value.split(separator: "-").compactMap { Int($0) }
        guard pieces.count == 3 else { return nil }
        var components = DateComponents()
        components.year = pieces[0]
        components.month = pieces[1]
        components.day = pieces[2]
        return calendar.date(from: components)
    }

    private static func format(_ key: String, fallback: String, _ arguments: CVarArg...) -> String {
        String(format: L10n.app(key, fallback: fallback), locale: locale, arguments: arguments)
    }
}
