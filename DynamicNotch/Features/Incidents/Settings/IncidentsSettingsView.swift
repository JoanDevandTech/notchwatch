import Combine
import NotchwatchCore
import SwiftUI

struct IncidentsSettingsView: View {
    @ObservedObject var settings: IncidentsSettingsStore
    @ObservedObject var viewModel: IncidentsViewModel
    @ObservedObject private var profileStore: IncidentsProfileStore

    init(settings: IncidentsSettingsStore, viewModel: IncidentsViewModel) {
        self._settings = ObservedObject(wrappedValue: settings)
        self._viewModel = ObservedObject(wrappedValue: viewModel)
        self._profileStore = ObservedObject(wrappedValue: viewModel.profileStore)
    }

    var body: some View {
        SettingsPageScrollView {
            activityCard
            statusCard
            pagesCard
        }
        .accessibilityIdentifier("settings.incidents.root")
    }

    private var activityCard: some View {
        SettingsCard(title: IncidentsSettingsText.key("card.activity", "Activity")) {
            SettingsToggleRow(
                title: IncidentsSettingsText.key("enabled.title", "Incidents in the notch"),
                description: IncidentsSettingsText.key("enabled.desc", "Watch Asana incidents and show them as a live activity."),
                systemImage: "flame.fill",
                color: .orange,
                isOn: $settings.isIncidentsEnabled,
                accessibilityIdentifier: "settings.incidents.enabled"
            )
        }
    }

    private var statusCard: some View {
        SettingsCard(title: IncidentsSettingsText.key("card.status", "Connection")) {
            HStack(alignment: .center, spacing: 12) {
                SettingsIconBadge(
                    systemImage: statusSymbol,
                    tint: statusTint,
                    size: 30,
                    iconSize: 14,
                    cornerRadius: 9
                )
                VStack(alignment: .leading, spacing: 2) {
                    SwiftUI.Text(verbatim: statusTitle)
                    SwiftUI.Text(verbatim: statusDetail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                if viewModel.isConfigured {
                    Button {
                        viewModel.refreshNow()
                    } label: {
                        IncidentsSettingsText.label("status.refresh", "Refresh")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.regular)
                    .disabled(!settings.isIncidentsEnabled)
                }
            }
        }
    }

    private var pagesCard: some View {
        SettingsCard(spacing: 0, padding: 0) {
            SettingsNavigationRowView(
                title: IncidentsSettingsText.key("account.title", "Account & Projects"),
                description: IncidentsSettingsText.key("account.subtitle", "Asana token, connection status and watched projects."),
                systemImage: "person.crop.circle.fill",
                color: .blue,
                accessibilityIdentifier: "settings.incidents.account",
                position: .first,
                showBadge: !viewModel.isConfigured,
                value: SettingsSubPage.incidentsAccount
            )

            SettingsNavigationRowView(
                title: IncidentsSettingsText.key("appearance.title", "Appearance"),
                description: IncidentsSettingsText.key("appearance.subtitle", "Theme, priority colors, typography and motion."),
                systemImage: "paintpalette.fill",
                color: .pink,
                accessibilityIdentifier: "settings.incidents.appearance",
                position: .middle,
                value: SettingsSubPage.incidentsAppearance
            )

            SettingsNavigationRowView(
                title: IncidentsSettingsText.key("sounds.title", "Sounds"),
                description: IncidentsSettingsText.key("sounds.subtitle", "Volume, sound per priority and repeats."),
                systemImage: "speaker.wave.2.fill",
                color: .red,
                accessibilityIdentifier: "settings.incidents.sounds",
                position: .middle,
                value: SettingsSubPage.incidentsSounds
            )

            SettingsNavigationRowView(
                title: IncidentsSettingsText.key("alerts.title", "Alerts"),
                description: IncidentsSettingsText.key("alerts.subtitle", "Do Not Disturb, alert card, macOS notifications and polling."),
                systemImage: "bell.badge.fill",
                color: .indigo,
                accessibilityIdentifier: "settings.incidents.alerts",
                position: .middle,
                value: SettingsSubPage.incidentsAlerts
            )

            SettingsNavigationRowView(
                title: IncidentsSettingsText.key("advanced.title", "Shortcut & Advanced"),
                description: IncidentsSettingsText.key("advanced.subtitle", "Global shortcut, profile export/import and reset."),
                systemImage: "keyboard.fill",
                color: .gray,
                accessibilityIdentifier: "settings.incidents.advanced",
                position: .last,
                value: SettingsSubPage.incidentsAdvanced
            )
        }
    }

    private var statusSymbol: String {
        if !viewModel.isConfigured { return "link.badge.plus" }
        if viewModel.connectionIssue != nil { return "exclamationmark.triangle.fill" }
        return "checkmark.circle.fill"
    }

    private var statusTint: Color {
        if !viewModel.isConfigured { return .gray }
        if viewModel.connectionIssue != nil { return .orange }
        return .green
    }

    private var statusTitle: String {
        if !viewModel.isConfigured {
            return IncidentsSettingsText.string("status.notConfigured", "No account connected")
        }
        if let identity = viewModel.identity {
            return String(format: IncidentsSettingsText.string("status.connectedAs", "Connected as %@"), identity.name)
        }
        return IncidentsSettingsText.string("status.connecting", "Connecting…")
    }

    private var statusDetail: String {
        if !viewModel.isConfigured {
            return IncidentsSettingsText.string("status.notConfigured.desc", "Add your Asana token in Account & Projects to start watching incidents.")
        }
        if let issue = viewModel.connectionIssue {
            return issue
        }
        let projects = profileStore.profile.collections.filter(\.enabled).count
        let projectsText = String(format: IncidentsSettingsText.string("status.projects", "%d watched projects"), projects)
        guard let lastPoll = viewModel.lastPoll else {
            return projectsText
        }
        let relative = RelativeDateTimeFormatter().localizedString(for: lastPoll, relativeTo: Date())
        return projectsText + " · " + String(format: IncidentsSettingsText.string("status.updated", "Updated %@"), relative)
    }
}
