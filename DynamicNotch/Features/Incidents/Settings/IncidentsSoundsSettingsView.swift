import Combine
import NotchwatchCore
import SwiftUI

struct IncidentsSoundsSettingsView: View {
    private static let repeatIntervals: [TimeInterval] = [15, 30, 60, 120, 300]

    @ObservedObject var viewModel: IncidentsViewModel
    @ObservedObject private var profileStore: IncidentsProfileStore

    init(viewModel: IncidentsViewModel) {
        self._viewModel = ObservedObject(wrappedValue: viewModel)
        self._profileStore = ObservedObject(wrappedValue: viewModel.profileStore)
    }

    private var sound: SoundSettings {
        viewModel.profile.sound
    }

    var body: some View {
        SettingsPageScrollView {
            generalCard
            motifsCard
            repeatsCard
            SettingsResetCard(targetName: IncidentsSettingsText.string("sounds.title", "Sounds")) {
                viewModel.profile.sound = SoundSettings(doNotDisturb: viewModel.profile.sound.doNotDisturb)
            }
        }
        .accessibilityIdentifier("settings.incidents.sounds.root")
    }

    private var generalCard: some View {
        SettingsCard(title: IncidentsSettingsText.key("sounds.card.general", "Sound")) {
            SettingsToggleRow(
                title: IncidentsSettingsText.key("sounds.muted.title", "Mute"),
                description: IncidentsSettingsText.key("sounds.muted.desc", "Incidents arrive silently; the island still updates."),
                systemImage: "speaker.slash.fill",
                color: .gray,
                isOn: viewModel.settingsProfileBinding(\.sound.muted),
                accessibilityIdentifier: "settings.incidents.sounds.muted"
            )

            IncidentsSettingsDivider()

            SettingsSliderRow(
                title: IncidentsSettingsText.key("sounds.volume.title", "Volume"),
                description: IncidentsSettingsText.key("sounds.volume.desc", "Relative to the system output volume."),
                range: 0...100,
                step: 5,
                fractionLength: 0,
                suffix: "%",
                accessibilityIdentifier: "settings.incidents.sounds.volume",
                value: Binding(
                    get: { (viewModel.profile.sound.volume * 100).rounded() },
                    set: { viewModel.profile.sound.volume = min(max($0 / 100, 0), 1) }
                )
            )
            .disabled(sound.muted)
            .opacity(sound.muted ? 0.5 : 1)
        }
    }

    private var motifsCard: some View {
        SettingsCard(title: IncidentsSettingsText.key("sounds.card.motifs", "Sound per priority")) {
            ForEach(Array(IncidentPriority.descending.enumerated()), id: \.element) { index, priority in
                if index > 0 {
                    IncidentsSettingsDivider()
                }
                motifRow(for: priority)
            }
        }
        .disabled(sound.muted)
        .opacity(sound.muted ? 0.5 : 1)
    }

    private func motifRow(for priority: IncidentPriority) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Circle()
                .fill(IncidentsHexColor.color(from: viewModel.profile.appearance.color(for: priority)))
                .frame(width: 10, height: 10)
            SwiftUI.Text(verbatim: IncidentsSettingsText.priorityName(priority))
            Spacer()
            Button {
                viewModel.previewSound(sound.motif(for: priority))
            } label: {
                Image(systemName: "play.fill")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .help(IncidentsSettingsText.string("sounds.preview", "Preview"))
            .accessibilityLabel(IncidentsSettingsText.label("sounds.preview", "Preview"))

            Menu {
                ForEach(SoundMotif.allCases, id: \.self) { motif in
                    Button {
                        viewModel.profile.sound.motifs[priority] = motif
                    } label: {
                        HStack {
                            SwiftUI.Text(verbatim: IncidentsSettingsText.motifName(motif))
                            if motif == sound.motif(for: priority) {
                                Spacer()
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                SwiftUI.Text(verbatim: IncidentsSettingsText.motifName(sound.motif(for: priority)))
                    .lineLimit(1)
            }
            .fixedSize(horizontal: true, vertical: false)
        }
        .accessibilityIdentifier("settings.incidents.sounds.motif.\(priority.rawValue)")
    }

    private var repeatsCard: some View {
        SettingsCard(title: IncidentsSettingsText.key("sounds.card.repeats", "Repeats")) {
            SettingsToggleRow(
                title: IncidentsSettingsText.key("sounds.repeats.title", "Repeat high and urgent"),
                description: IncidentsSettingsText.key("sounds.repeats.desc", "Keep sounding until the incident is acknowledged."),
                systemImage: "repeat",
                color: .orange,
                isOn: viewModel.settingsProfileBinding(\.sound.repeatsLoud),
                accessibilityIdentifier: "settings.incidents.sounds.repeats"
            )

            IncidentsSettingsDivider()

            IncidentsSettingsPickerRow(
                title: IncidentsSettingsText.string("sounds.repeatInterval.title", "Repeat every"),
                description: IncidentsSettingsText.string("sounds.repeatInterval.desc", "Pause between repeats while unattended."),
                options: Self.repeatIntervals,
                optionTitle: { IncidentsSettingsText.seconds($0) },
                selection: Binding(
                    get: { Self.repeatIntervals.contains(sound.loudRepeatInterval) ? sound.loudRepeatInterval : 30 },
                    set: { viewModel.profile.sound.loudRepeatInterval = $0 }
                )
            )
            .disabled(!sound.repeatsLoud || sound.muted)
            .opacity(!sound.repeatsLoud || sound.muted ? 0.5 : 1)
        }
    }
}
