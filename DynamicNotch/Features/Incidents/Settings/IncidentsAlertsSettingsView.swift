import Combine
import NotchwatchCore
import SwiftUI

struct IncidentsAlertsSettingsView: View {
    private enum ManualChoice: CaseIterable, Hashable {
        case off
        case thirtyMinutes
        case oneHour
        case untilTomorrow
        case indefinite

        var title: String {
            switch self {
            case .off: return IncidentsSettingsText.string("alerts.dnd.off", "Off")
            case .thirtyMinutes: return IncidentsSettingsText.string("alerts.dnd.30m", "For 30 minutes")
            case .oneHour: return IncidentsSettingsText.string("alerts.dnd.1h", "For 1 hour")
            case .untilTomorrow: return IncidentsSettingsText.string("alerts.dnd.tomorrow", "Until tomorrow")
            case .indefinite: return IncidentsSettingsText.string("alerts.dnd.indefinite", "Until I turn it off")
            }
        }

        func manual(now: Date, calendar: Calendar) -> DoNotDisturb.Manual {
            switch self {
            case .off: return .off
            case .thirtyMinutes: return .until(now.addingTimeInterval(30 * 60))
            case .oneHour: return .until(now.addingTimeInterval(60 * 60))
            case .untilTomorrow:
                let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) ?? now
                let morning = calendar.date(bySettingHour: 8, minute: 0, second: 0, of: tomorrow) ?? tomorrow
                return .until(morning)
            case .indefinite: return .indefinite
            }
        }
    }

    private static let pollIntervals: [TimeInterval] = [10, 20, 30, 60, 120, 300]

    @ObservedObject var viewModel: IncidentsViewModel
    @ObservedObject private var profileStore: IncidentsProfileStore

    init(viewModel: IncidentsViewModel) {
        self._viewModel = ObservedObject(wrappedValue: viewModel)
        self._profileStore = ObservedObject(wrappedValue: viewModel.profileStore)
    }

    private var sound: SoundSettings { viewModel.profile.sound }
    private var behavior: BehaviorSettings { viewModel.profile.behavior }

    var body: some View {
        SettingsPageScrollView {
            doNotDisturbCard
            scheduleCard
            alertCard
            notificationsCard
            readingCard
        }
        .accessibilityIdentifier("settings.incidents.alerts.root")
    }

    private var doNotDisturbCard: some View {
        SettingsCard(title: IncidentsSettingsText.key("alerts.card.dnd", "Do Not Disturb")) {
            HStack(alignment: .center, spacing: 12) {
                SettingsIconBadge(systemImage: "moon.fill", tint: Color.indigo, size: 30, iconSize: 14, cornerRadius: 9)
                VStack(alignment: .leading, spacing: 2) {
                    IncidentsSettingsText.label("alerts.dnd.title", "Manual Do Not Disturb")
                    SwiftUI.Text(verbatim: manualStatus)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                Menu {
                    ForEach(ManualChoice.allCases, id: \.self) { choice in
                        Button {
                            viewModel.setDoNotDisturb(choice.manual(now: Date(), calendar: .current))
                        } label: {
                            SwiftUI.Text(verbatim: choice.title)
                        }
                    }
                } label: {
                    SwiftUI.Text(verbatim: manualMenuTitle)
                        .lineLimit(1)
                }
                .fixedSize(horizontal: true, vertical: false)
            }
            .accessibilityIdentifier("settings.incidents.alerts.dnd.manual")

            IncidentsSettingsDivider(leadingPadding: 43)

            SettingsToggleRow(
                title: IncidentsSettingsText.key("alerts.urgentBreaksThrough.title", "Urgent incidents still sound"),
                description: IncidentsSettingsText.key("alerts.urgentBreaksThrough.desc", "With Do Not Disturb on, urgent incidents keep their sound and alert."),
                systemImage: "exclamationmark.triangle.fill",
                color: .red,
                isOn: viewModel.settingsProfileBinding(\.sound.doNotDisturb.urgentBreaksThrough),
                accessibilityIdentifier: "settings.incidents.alerts.urgentBreaksThrough"
            )
        }
    }

    private var scheduleCard: some View {
        SettingsCard(title: IncidentsSettingsText.key("alerts.card.schedule", "Quiet hours")) {
            SettingsToggleRow(
                title: IncidentsSettingsText.key("alerts.schedule.title", "Scheduled Do Not Disturb"),
                description: IncidentsSettingsText.key("alerts.schedule.desc", "Silence incidents every day during this time range."),
                systemImage: "clock.fill",
                color: .blue,
                isOn: viewModel.settingsProfileBinding(\.sound.doNotDisturb.schedule.enabled),
                accessibilityIdentifier: "settings.incidents.alerts.schedule"
            )

            IncidentsSettingsDivider(leadingPadding: 43)

            HStack(spacing: 16) {
                timeField(
                    title: IncidentsSettingsText.string("alerts.schedule.from", "From"),
                    minutes: viewModel.settingsProfileBinding(\.sound.doNotDisturb.schedule.startMinute)
                )
                timeField(
                    title: IncidentsSettingsText.string("alerts.schedule.to", "To"),
                    minutes: viewModel.settingsProfileBinding(\.sound.doNotDisturb.schedule.endMinute)
                )
                Spacer()
            }
            .disabled(!sound.doNotDisturb.schedule.enabled)
            .opacity(sound.doNotDisturb.schedule.enabled ? 1 : 0.5)
        }
    }

    private func timeField(title: String, minutes: Binding<Int>) -> some View {
        HStack(spacing: 8) {
            SwiftUI.Text(verbatim: title)
                .foregroundStyle(.secondary)
            DatePicker(
                selection: Binding(
                    get: { Self.date(fromMinutes: minutes.wrappedValue) },
                    set: { minutes.wrappedValue = Self.minutes(from: $0) }
                ),
                displayedComponents: .hourAndMinute
            ) {
                EmptyView()
            }
            .labelsHidden()
            .datePickerStyle(.field)
        }
    }

    private var alertCard: some View {
        SettingsCard(title: IncidentsSettingsText.key("alerts.card.alert", "Alert card")) {
            SettingsSliderRow(
                title: IncidentsSettingsText.key("alerts.duration.title", "Card duration"),
                description: IncidentsSettingsText.key("alerts.duration.desc", "Seconds the alert stays by itself. High and urgent wait until acknowledged."),
                range: 3...20,
                step: 1,
                fractionLength: 0,
                suffix: "s",
                accessibilityIdentifier: "settings.incidents.alerts.duration",
                value: Binding(
                    get: { behavior.alertDuration },
                    set: { viewModel.profile.behavior.alertDuration = $0.rounded() }
                )
            )
        }
    }

    private var notificationsCard: some View {
        SettingsCard(title: IncidentsSettingsText.key("alerts.card.notifications", "macOS notifications")) {
            SettingsToggleRow(
                title: IncidentsSettingsText.key("alerts.systemNotifications.title", "Notification Center"),
                description: IncidentsSettingsText.key("alerts.systemNotifications.desc", "Also post each new incident as a macOS notification with quick actions."),
                systemImage: "bell.badge.fill",
                color: .red,
                isOn: viewModel.settingsProfileBinding(\.behavior.systemNotifications),
                accessibilityIdentifier: "settings.incidents.alerts.systemNotifications"
            )

            IncidentsSettingsDivider(leadingPadding: 43)

            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    IncidentsSettingsText.label("alerts.permission.title", "Permission")
                    SwiftUI.Text(verbatim: String(
                        format: IncidentsSettingsText.string("alerts.permission.status", "Status: %@"),
                        permissionDescription
                    ))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    viewModel.requestNotificationPermission()
                } label: {
                    IncidentsSettingsText.label("alerts.permission.request", "Allow…")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(viewModel.notificationPermission != .notDetermined)
                Button {
                    viewModel.openNotificationSettings()
                } label: {
                    IncidentsSettingsText.label("alerts.permission.openSettings", "Open System Settings")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            .disabled(!behavior.systemNotifications)
            .opacity(behavior.systemNotifications ? 1 : 0.5)
            .accessibilityIdentifier("settings.incidents.alerts.permission")
        }
    }

    private var readingCard: some View {
        SettingsCard(title: IncidentsSettingsText.key("alerts.card.reading", "Reading")) {
            SettingsToggleRow(
                title: IncidentsSettingsText.key("alerts.showOnlyMine.title", "Show only mine by default"),
                description: IncidentsSettingsText.key("alerts.showOnlyMine.desc", "Open the panel filtered to incidents assigned to you."),
                systemImage: "person.fill.checkmark",
                color: .green,
                isOn: Binding(
                    get: { behavior.showOnlyMine },
                    set: { viewModel.setShowOnlyMine($0) }
                ),
                accessibilityIdentifier: "settings.incidents.alerts.showOnlyMine"
            )

            IncidentsSettingsDivider(leadingPadding: 43)

            IncidentsSettingsPickerRow(
                title: IncidentsSettingsText.string("alerts.pollInterval.title", "Check Asana every"),
                description: IncidentsSettingsText.string("alerts.pollInterval.desc", "Shorter intervals use more of the Asana rate limit."),
                options: Self.pollIntervals,
                optionTitle: IncidentsSettingsText.seconds,
                selection: Binding(
                    get: { Self.pollIntervals.contains(behavior.pollInterval) ? behavior.pollInterval : 20 },
                    set: { viewModel.profile.behavior.pollInterval = $0 }
                )
            )
        }
    }

    private var manualStatus: String {
        switch sound.doNotDisturb.manual {
        case .off:
            return IncidentsSettingsText.string("alerts.dnd.status.off", "Alerts and sounds arrive normally.")
        case .indefinite:
            return IncidentsSettingsText.string("alerts.dnd.status.indefinite", "Silenced until you turn it off.")
        case .until(let end):
            guard end > Date() else {
                return IncidentsSettingsText.string("alerts.dnd.status.off", "Alerts and sounds arrive normally.")
            }
            let time = end.formatted(date: .omitted, time: .shortened)
            return String(format: IncidentsSettingsText.string("alerts.dnd.status.until", "Silenced until %@."), time)
        }
    }

    private var manualMenuTitle: String {
        switch sound.doNotDisturb.manual {
        case .off:
            return ManualChoice.off.title
        case .indefinite:
            return ManualChoice.indefinite.title
        case .until(let end):
            guard end > Date() else { return ManualChoice.off.title }
            return end.formatted(date: .omitted, time: .shortened)
        }
    }

    private var permissionDescription: String {
        switch viewModel.notificationPermission {
        case .unavailable: return IncidentsSettingsText.string("alerts.permission.unavailable", "Unavailable in this build")
        case .notDetermined: return IncidentsSettingsText.string("alerts.permission.notDetermined", "Not requested yet")
        case .allowed: return IncidentsSettingsText.string("alerts.permission.allowed", "Allowed")
        case .denied: return IncidentsSettingsText.string("alerts.permission.denied", "Denied in System Settings")
        }
    }

    private static func date(fromMinutes minutes: Int) -> Date {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: Date())
        return calendar.date(byAdding: .minute, value: minutes, to: start) ?? start
    }

    private static func minutes(from date: Date) -> Int {
        let components = Calendar.current.dateComponents([.hour, .minute], from: date)
        return (components.hour ?? 0) * 60 + (components.minute ?? 0)
    }
}
