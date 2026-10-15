internal import AppKit
import NotchwatchCore
import SwiftUI

/// Tarjeta de aviso de una incidencia recién llegada: orbe de la prioridad, chips, título, meta y
/// botones En curso / Abrir / Expandir. Sin `Menu`: el gesto del notch es simultáneo (informe §9.4).
struct IncidentAlertView: View {
    @ObservedObject private var viewModel: IncidentsViewModel
    @Environment(\.isNotchlessScreen) private var isNotchlessScreen
    @State private var haloScale: CGFloat = 1

    let incident: Incident
    let extra: Int
    let onExpand: (() -> Void)?

    init(viewModel: IncidentsViewModel, incident: Incident, extra: Int, onExpand: (() -> Void)? = nil) {
        _viewModel = ObservedObject(wrappedValue: viewModel)
        self.incident = incident
        self.extra = extra
        self.onExpand = onExpand
    }

    private var theme: IncidentsTheme {
        IncidentsTheme(appearance: viewModel.profile.appearance)
    }

    private var priorityColor: Color {
        theme.priority(incident.priority)
    }

    private var collectionStyle: CollectionStyle {
        viewModel.style(for: incident.collectionID)
    }

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)
            content
                .frame(height: IncidentsLayout.alertExtraHeight - bottomPadding)
        }
        .padding(.leading, leadingPadding)
        .padding(.trailing, trailingPadding)
        .padding(.bottom, bottomPadding)
        .environment(\.incidentsTheme, theme)
    }

    private var content: some View {
        HStack(alignment: .center, spacing: 11.5) {
            orb
            VStack(alignment: .leading, spacing: 5.5) {
                chips
                SwiftUI.Text(incident.name)
                    .font(theme.font(13, weight: .bold))
                    .foregroundStyle(theme.textPrimary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                SwiftUI.Text(meta)
                    .font(theme.font(10, weight: .medium))
                    .foregroundStyle(theme.textSecondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            buttons
        }
    }

    private var orb: some View {
        IncidentIconTile(
            symbol: theme.symbol(for: incident.priority),
            color: priorityColor,
            size: IncidentsLayout.alertOrbSize,
            hasHalo: true
        )
        .scaleEffect(haloScale)
        .onAppear {
            guard incident.priority.isLoud, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { return }
            withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                haloScale = 1.06
            }
        }
    }

    private var chips: some View {
        HStack(spacing: 6.5) {
            ViewThatFits(in: .horizontal) {
                chipRow(showsCollection: true, showsExtra: extra > 0)
                chipRow(showsCollection: true, showsExtra: false)
                chipRow(showsCollection: false, showsExtra: false)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            SwiftUI.Text(IncidentsFormatting.relativeAge(of: incident.createdAt))
                .font(theme.font(9.5))
                .foregroundStyle(theme.textTertiary)
        }
    }

    private func chipRow(showsCollection: Bool, showsExtra: Bool) -> some View {
        HStack(spacing: 6.5) {
            IncidentPriorityChip(priority: incident.priority)
            if showsCollection {
                IncidentChip(
                    text: incident.collectionName,
                    systemImage: collectionStyle.symbol,
                    tint: theme.collection(collectionStyle)
                )
            }
            if showsExtra {
                IncidentChip(text: IncidentsFormatting.more(extra), isFilled: false)
            }
        }
    }

    private var meta: String {
        var parts: [String] = []
        if let reporter = NotchwatchCore.Text.nonEmpty(incident.reporter) {
            parts.append(reporter)
        }
        if let module = NotchwatchCore.Text.nonEmpty(incident.module) {
            parts.append(module)
        }
        if let errors = incident.consoleErrors, errors > 0 {
            parts.append(IncidentsFormatting.consoleErrors(errors))
        }
        parts.append(IncidentsFormatting.due(incident.dueOn))
        return parts.joined(separator: " · ")
    }

    private var buttons: some View {
        HStack(spacing: 5.5) {
            if viewModel.can(.startProgress, on: incident) {
                IncidentIconButton(
                    symbol: "play.circle",
                    help: L10n.app("incidents.island.action.startProgress.help", fallback: "Mark as in progress (assigns it to you if it has no assignee)"),
                    size: IncidentsLayout.alertButtonSize
                ) {
                    viewModel.startProgress(incident)
                }
            }
            navigationButtons
        }
    }

    private var navigationButtons: some View {
        VStack(spacing: 5.5) {
            IncidentIconButton(
                symbol: "arrow.up.right",
                help: L10n.app("incidents.island.action.open", fallback: "Open"),
                size: IncidentsLayout.alertButtonSize
            ) {
                viewModel.open(incident)
            }
            if let onExpand {
                IncidentIconButton(
                    symbol: "chevron.down",
                    help: L10n.app("incidents.island.action.expand", fallback: "Expand"),
                    size: IncidentsLayout.alertButtonSize
                ) {
                    onExpand()
                }
            }
        }
    }

    private var leadingPadding: CGFloat {
        isNotchlessScreen ? IncidentsLayout.alertNotchlessPadding.leading : IncidentsLayout.alertPadding.leading
    }

    private var trailingPadding: CGFloat {
        isNotchlessScreen ? IncidentsLayout.alertNotchlessPadding.trailing : IncidentsLayout.alertPadding.trailing
    }

    private var bottomPadding: CGFloat {
        isNotchlessScreen ? IncidentsLayout.alertNotchlessPadding.bottom : IncidentsLayout.alertPadding.bottom
    }
}
