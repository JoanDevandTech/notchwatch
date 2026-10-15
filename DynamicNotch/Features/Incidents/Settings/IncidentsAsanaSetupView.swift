import Combine
import NotchwatchCore
import SwiftUI

/// Asistente de alta de Asana: token → workspace → proyectos → propuesta por proyecto → guardar.
struct IncidentsAsanaSetupView: View {
    private enum Step: Int, CaseIterable {
        case token
        case workspace
        case projects
        case review
    }

    @Environment(\.dismiss) private var dismiss
    @ObservedObject var viewModel: IncidentsViewModel

    @State private var step: Step = .token
    @State private var token: String
    @State private var client: AsanaClient?
    @State private var identity: SourceIdentity?
    @State private var workspaces: [AsanaWorkspace] = []
    @State private var selectedWorkspace: AsanaWorkspace?
    @State private var projects: [AsanaProject] = []
    @State private var selectedProjectGIDs: Set<String> = []
    @State private var projectSearch = ""
    @State private var layouts: [String: AsanaProjectLayout] = [:]
    @State private var proposals: [AsanaProjectConfig] = []
    @State private var isLoading = false
    @State private var errorMessage: String?

    init(viewModel: IncidentsViewModel, initialToken: String = "") {
        self._viewModel = ObservedObject(wrappedValue: viewModel)
        self._token = State(initialValue: initialToken)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(0.6)
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    stepContent
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            Divider().opacity(0.6)
            footer
        }
        .frame(width: 620, height: 560)
        .accessibilityIdentifier("settings.incidents.setup")
    }

    private var header: some View {
        HStack(spacing: 12) {
            SettingsIconBadge(systemImage: "flame.fill", tint: Color.orange, size: 30, iconSize: 14, cornerRadius: 9)
            VStack(alignment: .leading, spacing: 2) {
                IncidentsSettingsText.label("setup.title", "Connect Asana")
                    .font(.headline)
                SwiftUI.Text(verbatim: stepTitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            SwiftUI.Text(verbatim: String(
                format: IncidentsSettingsText.string("setup.step", "Step %d of %d"),
                step.rawValue + 1,
                Step.allCases.count
            ))
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(16)
    }

    @ViewBuilder
    private var stepContent: some View {
        switch step {
        case .token:
            tokenStep
        case .workspace:
            workspaceStep
        case .projects:
            projectsStep
        case .review:
            reviewStep
        }
        if let errorMessage {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                SwiftUI.Text(verbatim: errorMessage)
            }
            .font(.caption)
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var tokenStep: some View {
        VStack(alignment: .leading, spacing: 10) {
            SwiftUI.Text(verbatim: IncidentsSettingsText.string(
                "account.token.help",
                "Create a personal access token in Asana (My settings → Apps → Developer apps) and paste it here. It is stored in the Keychain only."
            ))
            .font(.callout)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)

            SecureField(IncidentsSettingsText.string("account.token.placeholder", "Paste your Asana token"), text: $token)
                .textFieldStyle(.roundedBorder)
                .disabled(isLoading)
                .onSubmit(loadWorkspaces)

            Button {
                applyPreset()
            } label: {
                IncidentsSettingsText.label("account.preset.tubuencamino", "Use Tubuencamino preset")
            }
            .buttonStyle(.bordered)
            .disabled(trimmedToken == nil || isLoading)

            IncidentsSettingsText.label("setup.preset.help", "The preset connects the seven Tubuencamino incident projects without further questions.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var workspaceStep: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let identity {
                IncidentsStatusLine(
                    text: String(format: IncidentsSettingsText.string("status.connectedAs", "Connected as %@"), identity.name),
                    tint: .green
                )
            }
            IncidentsSettingsText.label("setup.workspace.help", "Choose the workspace that holds the incident projects.")
                .font(.callout)
                .foregroundStyle(.secondary)
            SettingsCard(spacing: 0, padding: 0) {
                ForEach(Array(workspaces.enumerated()), id: \.element.id) { index, workspace in
                    if index > 0 {
                        IncidentsSettingsDivider(leadingPadding: 16)
                    }
                    Button {
                        selectedWorkspace = workspace
                    } label: {
                        HStack {
                            SwiftUI.Text(verbatim: workspace.name)
                            Spacer()
                            if selectedWorkspace?.gid == workspace.gid {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(Color.accentColor)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var projectsStep: some View {
        VStack(alignment: .leading, spacing: 10) {
            IncidentsSettingsText.label("setup.projects.help", "Pick the projects to watch. Each one becomes a collection in the notch.")
                .font(.callout)
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField(IncidentsSettingsText.string("setup.projects.search", "Search projects"), text: $projectSearch)
                    .textFieldStyle(.plain)
                if !projectSearch.isEmpty {
                    Button {
                        projectSearch = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.primary.opacity(0.06))
            }

            SettingsCard(spacing: 0, padding: 0) {
                if filteredProjects.isEmpty {
                    IncidentsSettingsText.label("setup.projects.empty", "No projects match.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .padding(16)
                } else {
                    ForEach(Array(filteredProjects.enumerated()), id: \.element.id) { index, project in
                        if index > 0 {
                            IncidentsSettingsDivider(leadingPadding: 16)
                        }
                        projectSelectionRow(project)
                    }
                }
            }

            SwiftUI.Text(verbatim: String(
                format: IncidentsSettingsText.string("setup.projects.selected", "%d selected"),
                selectedProjectGIDs.count
            ))
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    private func projectSelectionRow(_ project: AsanaProject) -> some View {
        let isSelected = selectedProjectGIDs.contains(project.gid)
        return Button {
            if isSelected {
                selectedProjectGIDs.remove(project.gid)
            } else {
                selectedProjectGIDs.insert(project.gid)
            }
        } label: {
            HStack {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                SwiftUI.Text(verbatim: project.name)
                if project.archived {
                    IncidentsSettingsText.label("setup.projects.archived", "Archived")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var reviewStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            IncidentsSettingsText.label("setup.review.help", "Check the detected sections and fields for each project. You can change them later.")
                .font(.callout)
                .foregroundStyle(.secondary)
            ForEach(proposals.indices, id: \.self) { index in
                IncidentsProjectProposalEditor(
                    proposal: $proposals[index],
                    layout: layouts[proposals[index].projectGid]
                )
            }
        }
    }

    private var footer: some View {
        HStack {
            Button {
                dismiss()
            } label: {
                SwiftUI.Text(verbatim: L10n.app("common.cancel", fallback: "Cancel"))
            }
            .keyboardShortcut(.cancelAction)

            Spacer()

            if isLoading {
                ProgressView().controlSize(.small)
            }

            if step != .token {
                Button {
                    goBack()
                } label: {
                    IncidentsSettingsText.label("setup.back", "Back")
                }
                .disabled(isLoading)
            }

            Button {
                advance()
            } label: {
                SwiftUI.Text(verbatim: step == .review
                    ? IncidentsSettingsText.string("setup.save", "Save")
                    : IncidentsSettingsText.string("setup.next", "Next"))
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)
            .disabled(!canAdvance || isLoading)
        }
        .padding(16)
    }

    private var stepTitle: String {
        switch step {
        case .token: return IncidentsSettingsText.string("setup.step.token", "Personal access token")
        case .workspace: return IncidentsSettingsText.string("setup.step.workspace", "Workspace")
        case .projects: return IncidentsSettingsText.string("setup.step.projects", "Projects")
        case .review: return IncidentsSettingsText.string("setup.step.review", "Review")
        }
    }

    private var trimmedToken: String? {
        NotchwatchCore.Text.nonEmpty(token)
    }

    private var filteredProjects: [AsanaProject] {
        let query = projectSearch.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return projects }
        return projects.filter { $0.name.localizedCaseInsensitiveContains(query) }
    }

    private var canAdvance: Bool {
        switch step {
        case .token: return trimmedToken != nil
        case .workspace: return selectedWorkspace != nil
        case .projects: return !selectedProjectGIDs.isEmpty
        case .review: return proposals.allSatisfy { !$0.detectedSectionGid.isEmpty && !$0.collection.name.isEmpty }
        }
    }

    private func goBack() {
        errorMessage = nil
        switch step {
        case .token: break
        case .workspace: step = .token
        case .projects: step = .workspace
        case .review: step = .projects
        }
    }

    private func advance() {
        switch step {
        case .token: loadWorkspaces()
        case .workspace: loadProjects()
        case .projects: loadLayouts()
        case .review: save()
        }
    }

    private func loadWorkspaces() {
        guard let value = trimmedToken else { return }
        let discovery = viewModel.makeDiscoveryClient(token: value)
        client = discovery
        perform {
            let me = try await discovery.me()
            let found = try await discovery.workspaces()
            identity = me
            workspaces = found
            selectedWorkspace = found.count == 1 ? found.first : selectedWorkspace
            step = .workspace
        }
    }

    private func loadProjects() {
        guard let client, let workspace = selectedWorkspace else { return }
        perform {
            let found = try await client.projects(inWorkspace: workspace.gid)
            projects = found.filter { !$0.archived } + found.filter(\.archived)
            selectedProjectGIDs = selectedProjectGIDs.intersection(found.map(\.gid))
            step = .projects
        }
    }

    private func loadLayouts() {
        guard let client, let workspace = selectedWorkspace else { return }
        let chosen = projects.filter { selectedProjectGIDs.contains($0.gid) }
        let sourceID = sourceIdentifier(for: workspace)
        perform {
            var loaded: [String: AsanaProjectLayout] = [:]
            var suggested: [AsanaProjectConfig] = []
            for project in chosen {
                let layout = try await client.layout(of: project)
                loaded[project.gid] = layout
                suggested.append(existingProposal(for: project.gid) ?? AsanaConfigurator.suggest(for: layout, sourceID: sourceID))
            }
            layouts = loaded
            proposals = suggested
            step = .review
        }
    }

    private func save() {
        guard let value = trimmedToken, let workspace = selectedWorkspace else { return }
        let config = AsanaSourceConfig(
            id: sourceIdentifier(for: workspace),
            displayName: workspace.name,
            workspaceGid: workspace.gid,
            workspaceName: workspace.name,
            projects: proposals
        )
        isLoading = true
        errorMessage = nil
        Task {
            let result = await viewModel.saveAsanaSource(config, token: value)
            isLoading = false
            switch result {
            case .success:
                dismiss()
            case .failure(let error):
                errorMessage = IncidentsFailureText.describe(error)
            }
        }
    }

    private func applyPreset() {
        guard let value = trimmedToken else { return }
        isLoading = true
        errorMessage = nil
        Task {
            let result = await viewModel.applyTubuencaminoPreset(token: value)
            isLoading = false
            switch result {
            case .success:
                dismiss()
            case .failure(let error):
                errorMessage = IncidentsFailureText.describe(error)
            }
        }
    }

    private func perform(_ work: @escaping () async throws -> Void) {
        isLoading = true
        errorMessage = nil
        Task {
            do {
                try await work()
            } catch {
                errorMessage = IncidentsAsanaErrorText.describe(error)
            }
            isLoading = false
        }
    }

    /// Reutiliza la configuración existente del mismo proyecto para no perder ajustes manuales.
    private func existingProposal(for projectGid: String) -> AsanaProjectConfig? {
        guard let workspace = selectedWorkspace, let current = viewModel.settingsAsanaConfig,
              current.id == sourceIdentifier(for: workspace) else { return nil }
        return current.projects.first { $0.projectGid == projectGid }
    }

    private func sourceIdentifier(for workspace: AsanaWorkspace) -> String {
        if let current = viewModel.settingsAsanaConfig, current.workspaceGid == workspace.gid {
            return current.id
        }
        let slug = AsanaConfigurator.slug(workspace.name)
        return slug.isEmpty ? "asana-\(workspace.gid)" : "asana-\(slug)"
    }
}

/// Texto legible para los errores de descubrimiento.
enum IncidentsAsanaErrorText {
    static func describe(_ error: Error) -> String {
        guard let sourceError = error as? SourceError else {
            return error.localizedDescription
        }
        switch sourceError {
        case .unauthorized:
            return IncidentsSettingsText.string("error.unauthorized", "Asana rejected the token. Check that it is valid and has not expired.")
        case .rateLimited:
            return IncidentsSettingsText.string("error.rateLimited", "Asana is rate limiting requests. Try again in a minute.")
        case .network(let detail):
            return String(format: IncidentsSettingsText.string("error.network", "Network error: %@"), detail)
        case .http(let status, let detail):
            return String(format: IncidentsSettingsText.string("error.http", "Asana answered %d: %@"), status, detail)
        case .decoding(let detail):
            return String(format: IncidentsSettingsText.string("error.decoding", "Unexpected answer from Asana: %@"), detail)
        case .invalidConfiguration(let detail):
            return String(format: IncidentsSettingsText.string("error.invalidConfiguration", "Invalid configuration: %@"), detail)
        }
    }
}

/// Editor de la propuesta de un proyecto: secciones, campo de prioridad, nombre, icono y color.
struct IncidentsProjectProposalEditor: View {
    @Binding var proposal: AsanaProjectConfig
    let layout: AsanaProjectLayout?

    private static let noSelection = ""

    var body: some View {
        SettingsCard(verbatimTitle: proposal.projectName) {
            HStack(spacing: 12) {
                SettingsIconBadge(
                    systemImage: NotchwatchCore.Text.nonEmpty(proposal.collection.style.symbol) ?? CollectionStyle.default.symbol,
                    tint: IncidentsHexColor.color(from: proposal.collection.style.colorHex),
                    size: 30,
                    iconSize: 14,
                    cornerRadius: 9
                )
                TextField(IncidentsSettingsText.string("account.projects.name", "Short name"), text: $proposal.collection.name)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 180)
                TextField(IncidentsSettingsText.string("account.projects.symbol", "SF Symbol"), text: $proposal.collection.style.symbol)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 170)
                ColorPicker(selection: IncidentsHexColor.binding($proposal.collection.style.colorHex), supportsOpacity: false) {
                    EmptyView()
                }
                .labelsHidden()
            }

            IncidentsSettingsDivider()

            sectionPicker(
                title: IncidentsSettingsText.string("setup.review.detected", "Detected section"),
                description: IncidentsSettingsText.string("setup.review.detected.desc", "Open tasks here are pending incidents."),
                selection: $proposal.detectedSectionGid,
                allowsNone: false
            )

            IncidentsSettingsDivider()

            sectionPicker(
                title: IncidentsSettingsText.string("setup.review.resolved", "Resolution section"),
                description: IncidentsSettingsText.string("setup.review.resolved.desc", "Resolving moves the task here. Without it, resolving is disabled."),
                selection: Binding(
                    get: { proposal.resolvedSectionGid ?? Self.noSelection },
                    set: { proposal.resolvedSectionGid = $0 == Self.noSelection ? nil : $0 }
                ),
                allowsNone: true
            )

            IncidentsSettingsDivider()

            IncidentsSettingsPickerRow(
                title: IncidentsSettingsText.string("setup.review.priority", "Priority field"),
                description: IncidentsSettingsText.string("setup.review.priority.desc", "Enum field whose options map to urgent, high, medium and low."),
                options: [Self.noSelection] + enumFields.map(\.gid),
                optionTitle: { gid in
                    enumFields.first { $0.gid == gid }?.name ?? IncidentsSettingsText.string("setup.review.none", "None")
                },
                selection: Binding(
                    get: { proposal.priorityField?.fieldGid ?? Self.noSelection },
                    set: { proposal.priorityField = priorityField(forFieldGid: $0) }
                )
            )
        }
    }

    private var sections: [AsanaSection] {
        layout?.sections ?? []
    }

    private var enumFields: [AsanaCustomField] {
        (layout?.fields ?? []).filter { $0.type == "enum" }
    }

    private func sectionPicker(title: String, description: String, selection: Binding<String>, allowsNone: Bool) -> some View {
        let options = (allowsNone ? [Self.noSelection] : []) + sections.map(\.gid)
        return IncidentsSettingsPickerRow(
            title: title,
            description: description,
            options: options,
            optionTitle: { gid in
                sections.first { $0.gid == gid }?.name ?? IncidentsSettingsText.string("setup.review.none", "None")
            },
            selection: selection
        )
    }

    private func priorityField(forFieldGid gid: String) -> PriorityField? {
        guard let field = enumFields.first(where: { $0.gid == gid }) else { return nil }
        var options: [IncidentPriority: String] = [:]
        for option in field.options {
            guard let priority = IncidentsPriorityOptionMatcher.priority(forOptionName: option.name), options[priority] == nil else { continue }
            options[priority] = option.gid
        }
        return PriorityField(fieldGid: field.gid, options: options)
    }
}

/// Asocia nombres de opciones de Asana a prioridades (misma heurística que `AsanaConfigurator`, que es interna al paquete).
enum IncidentsPriorityOptionMatcher {
    static func priority(forOptionName name: String) -> IncidentPriority? {
        let folded = name.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil).lowercased()
        if matches(folded, ["urgente", "critic", "incidencia"]) { return .urgente }
        if matches(folded, ["alta", "high"]) { return .alta }
        if matches(folded, ["media", "medium", "normal"]) { return .media }
        if matches(folded, ["baja", "low"]) { return .baja }
        return nil
    }

    private static func matches(_ text: String, _ hints: [String]) -> Bool {
        hints.contains { text.contains($0) }
    }
}
