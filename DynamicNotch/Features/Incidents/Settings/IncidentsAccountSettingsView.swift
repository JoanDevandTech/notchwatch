import Combine
import NotchwatchCore
import SwiftUI

struct IncidentsAccountSettingsView: View {
    private enum Outcome: Equatable {
        case success(String)
        case failure(String)
    }

    @ObservedObject var viewModel: IncidentsViewModel
    @ObservedObject private var profileStore: IncidentsProfileStore

    @State private var token = ""
    @State private var isWorking = false
    @State private var outcome: Outcome?
    @State private var isShowingSetup = false
    @State private var isConfirmingRemoval = false

    init(viewModel: IncidentsViewModel) {
        self._viewModel = ObservedObject(wrappedValue: viewModel)
        self._profileStore = ObservedObject(wrappedValue: viewModel.profileStore)
    }

    var body: some View {
        SettingsPageScrollView {
            statusCard
            tokenCard
            if let config = viewModel.settingsAsanaConfig {
                projectsCard(for: config)
            }
        }
        .accessibilityIdentifier("settings.incidents.account.root")
        .sheet(isPresented: $isShowingSetup) {
            IncidentsAsanaSetupView(viewModel: viewModel, initialToken: token)
        }
        .alert(
            IncidentsSettingsText.string("account.remove.confirm.title", "Remove the Asana account?"),
            isPresented: $isConfirmingRemoval
        ) {
            Button(role: .destructive) {
                removeSource()
            } label: {
                IncidentsSettingsText.label("account.remove", "Remove")
            }
            Button(role: .cancel) {} label: {
                SwiftUI.Text(verbatim: L10n.app("common.cancel", fallback: "Cancel"))
            }
        } message: {
            IncidentsSettingsText.label("account.remove.confirm.message", "The token is deleted from the Keychain and the watched projects are forgotten.")
        }
    }

    private var statusCard: some View {
        SettingsCard(title: IncidentsSettingsText.key("card.status", "Connection")) {
            IncidentsStatusLine(text: statusText, tint: statusTint)
            if let issue = viewModel.connectionIssue, viewModel.isConfigured {
                SwiftUI.Text(verbatim: issue)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let config = viewModel.settingsAsanaConfig {
                SwiftUI.Text(verbatim: String(
                    format: IncidentsSettingsText.string("account.workspace", "Workspace: %@"),
                    config.workspaceName
                ))
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
    }

    private var tokenCard: some View {
        SettingsCard(title: IncidentsSettingsText.key("account.token.card", "Personal access token")) {
            SwiftUI.Text(verbatim: IncidentsSettingsText.string(
                "account.token.help",
                "Create a personal access token in Asana (My settings → Apps → Developer apps) and paste it here. It is stored in the Keychain only."
            ))
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)

            SecureField(
                IncidentsSettingsText.string("account.token.placeholder", "Paste your Asana token"),
                text: $token
            )
            .textFieldStyle(.roundedBorder)
            .disabled(isWorking)
            .accessibilityIdentifier("settings.incidents.account.token")

            HStack(spacing: 8) {
                if let config = viewModel.settingsAsanaConfig {
                    Button {
                        saveAndTest(config)
                    } label: {
                        IncidentsSettingsText.label("account.token.save", "Save & test")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(trimmedToken == nil || isWorking)

                    Button {
                        isShowingSetup = true
                    } label: {
                        IncidentsSettingsText.label("account.setup.reconfigure", "Change projects…")
                    }
                    .buttonStyle(.bordered)
                    .disabled(isWorking)

                    Button(role: .destructive) {
                        isConfirmingRemoval = true
                    } label: {
                        IncidentsSettingsText.label("account.remove", "Remove")
                    }
                    .buttonStyle(.bordered)
                    .disabled(isWorking)
                } else {
                    Button {
                        applyPreset()
                    } label: {
                        IncidentsSettingsText.label("account.preset.tubuencamino", "Use Tubuencamino preset")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(trimmedToken == nil || isWorking)

                    Button {
                        isShowingSetup = true
                    } label: {
                        IncidentsSettingsText.label("account.setup.start", "Set up with assistant…")
                    }
                    .buttonStyle(.bordered)
                    .disabled(isWorking)
                }

                Spacer()

                if isWorking {
                    ProgressView()
                        .controlSize(.small)
                }
            }

            if let outcome {
                outcomeView(outcome)
            }
        }
    }

    private func projectsCard(for config: AsanaSourceConfig) -> some View {
        SettingsCard(title: IncidentsSettingsText.key("account.projects.card", "Watched projects")) {
            ForEach(Array(config.projects.enumerated()), id: \.element.id) { index, project in
                if index > 0 {
                    IncidentsSettingsDivider(leadingPadding: 43)
                }
                projectRow(project, index: index, config: config)
            }
        }
    }

    private func projectRow(_ project: AsanaProjectConfig, index: Int, config: AsanaSourceConfig) -> some View {
        let collection = collectionBinding(index: index, config: config)
        return HStack(alignment: .center, spacing: 12) {
            SettingsIconBadge(
                systemImage: symbolOrFallback(project.collection.style.symbol),
                tint: IncidentsHexColor.color(from: project.collection.style.colorHex),
                size: 30,
                iconSize: 14,
                cornerRadius: 9
            )

            VStack(alignment: .leading, spacing: 4) {
                TextField(
                    IncidentsSettingsText.string("account.projects.name", "Short name"),
                    text: collection.name
                )
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 180)
                SwiftUI.Text(verbatim: project.projectName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            TextField(
                IncidentsSettingsText.string("account.projects.symbol", "SF Symbol"),
                text: collection.style.symbol
            )
            .textFieldStyle(.roundedBorder)
            .frame(width: 150)

            ColorPicker(
                selection: IncidentsHexColor.binding(collection.style.colorHex),
                supportsOpacity: false
            ) {
                EmptyView()
            }
            .labelsHidden()

            Toggle(isOn: collection.enabled) {
                EmptyView()
            }
            .toggleStyle(CustomToggleStyle())
            .labelsHidden()
        }
        .accessibilityIdentifier("settings.incidents.account.project.\(project.collection.id)")
    }

    private func collectionBinding(index: Int, config: AsanaSourceConfig) -> Binding<WatchedCollection> {
        Binding(
            get: {
                guard let current = viewModel.settingsAsanaConfig, current.projects.indices.contains(index) else {
                    return config.projects[index].collection
                }
                return current.projects[index].collection
            },
            set: { newValue in
                guard var current = viewModel.settingsAsanaConfig, current.projects.indices.contains(index) else { return }
                current.projects[index].collection = newValue
                viewModel.settingsReplaceAsanaSource(current)
            }
        )
    }

    private func outcomeView(_ outcome: Outcome) -> some View {
        HStack(spacing: 6) {
            switch outcome {
            case .success(let text):
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                SwiftUI.Text(verbatim: text)
            case .failure(let text):
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                SwiftUI.Text(verbatim: text)
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
    }

    private var trimmedToken: String? {
        NotchwatchCore.Text.nonEmpty(token)
    }

    private var statusText: String {
        guard viewModel.isConfigured else {
            return IncidentsSettingsText.string("status.notConfigured", "No account connected")
        }
        if let identity = viewModel.identity {
            return String(format: IncidentsSettingsText.string("status.connectedAs", "Connected as %@"), identity.name)
        }
        return IncidentsSettingsText.string("status.connecting", "Connecting…")
    }

    private var statusTint: Color {
        guard viewModel.isConfigured else { return .gray }
        return viewModel.connectionIssue == nil ? .green : .orange
    }

    private func symbolOrFallback(_ symbol: String) -> String {
        NotchwatchCore.Text.nonEmpty(symbol) ?? CollectionStyle.default.symbol
    }

    private func saveAndTest(_ config: AsanaSourceConfig) {
        guard let value = trimmedToken else { return }
        run {
            await viewModel.saveAsanaSource(config, token: value)
        }
    }

    private func applyPreset() {
        guard let value = trimmedToken else { return }
        run {
            await viewModel.applyTubuencaminoPreset(token: value)
        }
    }

    private func run<Failure: Error>(_ operation: @escaping () async -> Result<SourceIdentity, Failure>) {
        isWorking = true
        outcome = nil
        Task {
            let result = await operation()
            isWorking = false
            switch result {
            case .success(let identity):
                token = ""
                outcome = .success(String(
                    format: IncidentsSettingsText.string("status.connectedAs", "Connected as %@"),
                    identity.name
                ))
            case .failure(let error):
                outcome = .failure(IncidentsFailureText.describe(error))
            }
        }
    }

    private func removeSource() {
        guard let config = viewModel.settingsAsanaConfig else { return }
        viewModel.removeSource(id: config.id)
        outcome = .success(IncidentsSettingsText.string("account.remove.done", "Account removed."))
    }
}
