import Combine
import NotchwatchCore
import SwiftUI

struct IncidentsAppearanceSettingsView: View {
    @ObservedObject var viewModel: IncidentsViewModel
    @ObservedObject private var profileStore: IncidentsProfileStore

    init(viewModel: IncidentsViewModel) {
        self._viewModel = ObservedObject(wrappedValue: viewModel)
        self._profileStore = ObservedObject(wrappedValue: viewModel.profileStore)
    }

    var body: some View {
        SettingsPageScrollView {
            themeCard
            colorsCard
            typographyCard
            motionCard
            SettingsResetCard(targetName: IncidentsSettingsText.string("appearance.title", "Appearance")) {
                viewModel.profile.appearance = .default
                viewModel.profile.behavior.motion = BehaviorSettings.default.motion
            }
        }
        .accessibilityIdentifier("settings.incidents.appearance.root")
    }

    private var themeCard: some View {
        SettingsCard(title: IncidentsSettingsText.key("appearance.card.theme", "Theme")) {
            IncidentsSettingsPickerRow(
                title: IncidentsSettingsText.string("appearance.theme.title", "Island theme"),
                description: IncidentsSettingsText.string("appearance.theme.desc", "Automatic follows the system appearance."),
                options: ThemeMode.allCases,
                optionTitle: IncidentsSettingsText.themeName,
                selection: viewModel.settingsProfileBinding(\.appearance.theme)
            )
        }
    }

    private var colorsCard: some View {
        SettingsCard(title: IncidentsSettingsText.key("appearance.card.colors", "Priority colors")) {
            ForEach(Array(IncidentPriority.descending.enumerated()), id: \.element) { index, priority in
                if index > 0 {
                    IncidentsSettingsDivider(leadingPadding: 43)
                }
                colorRow(for: priority)
            }
        }
    }

    private func colorRow(for priority: IncidentPriority) -> some View {
        let hex = colorBinding(for: priority)
        return HStack(alignment: .center, spacing: 12) {
            SettingsIconBadge(
                systemImage: "circle.fill",
                tint: IncidentsHexColor.color(from: hex.wrappedValue),
                size: 30,
                iconSize: 14,
                cornerRadius: 9
            )
            VStack(alignment: .leading, spacing: 2) {
                SwiftUI.Text(verbatim: IncidentsSettingsText.priorityName(priority))
                SwiftUI.Text(verbatim: hex.wrappedValue.uppercased())
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }
            Spacer()
            ColorPicker(selection: IncidentsHexColor.binding(hex), supportsOpacity: false) {
                EmptyView()
            }
            .labelsHidden()
        }
        .accessibilityIdentifier("settings.incidents.appearance.color.\(priority.rawValue)")
    }

    private func colorBinding(for priority: IncidentPriority) -> Binding<String> {
        Binding(
            get: { viewModel.profile.appearance.color(for: priority) },
            set: { viewModel.profile.appearance.priorityColors[priority] = $0 }
        )
    }

    private var typographyCard: some View {
        SettingsCard(title: IncidentsSettingsText.key("appearance.card.typography", "Typography")) {
            IncidentsSettingsPickerRow(
                title: IncidentsSettingsText.string("appearance.font.title", "Font"),
                description: IncidentsSettingsText.string("appearance.font.desc", "Design used for titles and chips in the island."),
                options: FontDesignChoice.allCases,
                optionTitle: IncidentsSettingsText.fontDesignName,
                selection: viewModel.settingsProfileBinding(\.appearance.fontDesign)
            )

            IncidentsSettingsDivider()

            IncidentsSettingsPickerRow(
                title: IncidentsSettingsText.string("appearance.textScale.title", "Text size"),
                description: IncidentsSettingsText.string("appearance.textScale.desc", "Scales every text in the island."),
                options: TextScale.allCases,
                optionTitle: IncidentsSettingsText.textScaleName,
                selection: viewModel.settingsProfileBinding(\.appearance.textScale)
            )
        }
    }

    private var motionCard: some View {
        SettingsCard(title: IncidentsSettingsText.key("appearance.card.motion", "Motion")) {
            IncidentsSettingsPickerRow(
                title: IncidentsSettingsText.string("appearance.motion.title", "Ambient motion"),
                description: IncidentsSettingsText.string("appearance.motion.desc", "How often the island breathes, shimmers or unfolds while idle."),
                options: MotionIntensity.allCases,
                optionTitle: IncidentsSettingsText.motionName,
                selection: viewModel.settingsProfileBinding(\.behavior.motion)
            )
        }
    }
}
