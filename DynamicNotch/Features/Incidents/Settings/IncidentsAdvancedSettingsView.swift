import Combine
import NotchwatchCore
import SwiftUI
import UniformTypeIdentifiers
internal import AppKit

struct IncidentsAdvancedSettingsView: View {
    @ObservedObject var settings: IncidentsSettingsStore
    @ObservedObject var viewModel: IncidentsViewModel
    @ObservedObject private var profileStore: IncidentsProfileStore

    @State private var transferError: String?
    @State private var isShowingTransferError = false
    @State private var transferMessage: String?
    @State private var isConfirmingReset = false

    init(settings: IncidentsSettingsStore, viewModel: IncidentsViewModel) {
        self._settings = ObservedObject(wrappedValue: settings)
        self._viewModel = ObservedObject(wrappedValue: viewModel)
        self._profileStore = ObservedObject(wrappedValue: viewModel.profileStore)
    }

    var body: some View {
        SettingsPageScrollView {
            hotKeyCard
            profileCard
            resetCard
        }
        .accessibilityIdentifier("settings.incidents.advanced.root")
        .alert(
            IncidentsSettingsText.string("advanced.transfer.failed", "The profile could not be transferred"),
            isPresented: $isShowingTransferError
        ) {
            Button {
                transferError = nil
            } label: {
                SwiftUI.Text(verbatim: L10n.app("common.ok", fallback: "OK"))
            }
        } message: {
            SwiftUI.Text(verbatim: transferError ?? "")
        }
        .alert(
            IncidentsSettingsText.string("advanced.reset.confirm.title", "Reset every incidents setting?"),
            isPresented: $isConfirmingReset
        ) {
            Button(role: .destructive) {
                resetEverything()
            } label: {
                SwiftUI.Text(verbatim: L10n.app("settings.reset.action", fallback: "Reset"))
            }
            Button(role: .cancel) {} label: {
                SwiftUI.Text(verbatim: L10n.app("common.cancel", fallback: "Cancel"))
            }
        } message: {
            IncidentsSettingsText.label("advanced.reset.confirm.message", "Appearance, sounds, alerts and the shortcut go back to defaults. The Asana account and projects are kept.")
        }
    }

    private var hotKeyCard: some View {
        SettingsCard(title: IncidentsSettingsText.key("advanced.card.hotkey", "Global shortcut")) {
            IncidentsSettingsPickerRow(
                title: IncidentsSettingsText.string("advanced.hotkey.title", "Expand or collapse the island"),
                description: IncidentsSettingsText.string("advanced.hotkey.desc", "Works from any app and needs no permission."),
                options: HotKeyChoice.allCases,
                optionTitle: IncidentsSettingsText.hotKeyName,
                selection: viewModel.settingsProfileBinding(\.behavior.hotKey)
            )
            if let error = viewModel.hotKeyError {
                SwiftUI.Text(verbatim: error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var profileCard: some View {
        SettingsCard(title: IncidentsSettingsText.key("advanced.card.profile", "Profile")) {
            SettingsButtonRow(
                title: IncidentsSettingsText.key("advanced.export.title", "Export profile"),
                description: IncidentsSettingsText.key("advanced.export.desc", "Saves sources, appearance, sounds and behavior as JSON. Tokens are never included."),
                systemImage: "square.and.arrow.up",
                color: .blue,
                buttonTitle: IncidentsSettingsText.key("advanced.export.action", "Export…"),
                accessibilityIdentifier: "settings.incidents.advanced.export",
                action: exportProfile
            )

            IncidentsSettingsDivider(leadingPadding: 43)

            SettingsButtonRow(
                title: IncidentsSettingsText.key("advanced.import.title", "Import profile"),
                description: IncidentsSettingsText.key("advanced.import.desc", "Replaces the current profile with the chosen JSON file. Add the token afterwards."),
                systemImage: "square.and.arrow.down",
                color: .green,
                buttonTitle: IncidentsSettingsText.key("advanced.import.action", "Import…"),
                accessibilityIdentifier: "settings.incidents.advanced.import",
                action: importProfile
            )

            if let transferMessage {
                SwiftUI.Text(verbatim: transferMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            IncidentsSettingsDivider(leadingPadding: 43)

            SettingsCopyRowView(
                title: IncidentsSettingsText.key("advanced.path.title", "Profile location"),
                description: LocalizedStringKey(profileURL.path),
                systemImage: "doc.text.fill",
                color: .gray,
                accessibilityIdentifier: "settings.incidents.advanced.path",
                position: .single,
                textToCopy: profileURL.path
            )
        }
    }

    private var resetCard: some View {
        SettingsCard(title: IncidentsSettingsText.key("advanced.card.reset", "Reset")) {
            SettingsButtonRow(
                title: IncidentsSettingsText.key("advanced.reset.title", "Reset all incidents settings"),
                description: IncidentsSettingsText.key("advanced.reset.desc", "Keeps the Asana account and watched projects."),
                systemImage: "arrow.counterclockwise",
                color: .red,
                buttonTitle: IncidentsSettingsText.key("advanced.reset.action", "Reset…"),
                accessibilityIdentifier: "settings.incidents.advanced.reset"
            ) {
                isConfirmingReset = true
            }
        }
    }

    private var profileURL: URL {
        viewModel.profileStore.profileURL
    }

    private func exportProfile() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "notchwatch-profile.json"
        panel.canCreateDirectories = true
        panel.title = IncidentsSettingsText.string("advanced.export.title", "Export profile")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let data = try viewModel.profileStore.export()
            try data.write(to: url, options: .atomic)
            transferMessage = String(
                format: IncidentsSettingsText.string("advanced.export.done", "Profile exported to %@"),
                url.lastPathComponent
            )
        } catch {
            reportTransferError(error)
        }
    }

    private func importProfile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.title = IncidentsSettingsText.string("advanced.import.title", "Import profile")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let data = try Data(contentsOf: url)
            try viewModel.profileStore.importProfile(data)
            transferMessage = String(
                format: IncidentsSettingsText.string("advanced.import.done", "Profile imported from %@"),
                url.lastPathComponent
            )
        } catch {
            reportTransferError(error)
        }
    }

    private func reportTransferError(_ error: Error) {
        transferError = error.localizedDescription
        isShowingTransferError = true
    }

    private func resetEverything() {
        viewModel.profile.appearance = .default
        viewModel.profile.sound = .default
        viewModel.profile.behavior = .default
        settings.resetIncidents()
        transferMessage = nil
    }
}
