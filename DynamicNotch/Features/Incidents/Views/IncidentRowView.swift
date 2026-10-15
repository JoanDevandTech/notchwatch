internal import AppKit
import NotchwatchCore
import SwiftUI

/// Fila del panel: barra de prioridad, icono de colección, título, chips y hora relativa; al pasar
/// el ratón aparecen Abrir, En curso, Posponer, Resolver y «…», y los chips dejan sitio a la prioridad.
struct IncidentRowView: View {
    @ObservedObject private var viewModel: IncidentsViewModel
    @Environment(\.incidentsTheme) private var theme
    @State private var isHovering = false

    let incident: Incident

    init(viewModel: IncidentsViewModel, incident: Incident) {
        _viewModel = ObservedObject(wrappedValue: viewModel)
        self.incident = incident
    }

    private var priorityColor: Color {
        theme.priority(incident.priority)
    }

    private var collectionStyle: CollectionStyle {
        viewModel.style(for: incident.collectionID)
    }

    private var isCritical: Bool {
        incident.priority == .urgente
    }

    private var isSnoozed: Bool {
        viewModel.isSnoozed(incident)
    }

    private var activity: IncidentRowActivity? {
        viewModel.activity[incident.id]
    }

    private var showsActions: Bool {
        isHovering && activity == nil
    }

    var body: some View {
        HStack(spacing: 9.5) {
            IncidentIconTile(
                symbol: collectionStyle.symbol,
                color: theme.collection(collectionStyle),
                size: IncidentsLayout.rowIconSize
            )
            VStack(alignment: .leading, spacing: 3.5) {
                titleLine
                metaLine
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .opacity(isSnoozed ? 0.6 : 1)
            trailing
        }
        .padding(.leading, 10.5)
        .padding(.trailing, 7.5)
        .frame(height: IncidentsLayout.rowHeight)
        .background(rowBackground)
        .overlay(alignment: .leading) { priorityBar }
        .clipShape(RoundedRectangle(cornerRadius: IncidentsLayout.rowCornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: IncidentsLayout.rowCornerRadius, style: .continuous)
                .strokeBorder(strokeColor, lineWidth: 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: IncidentsLayout.rowCornerRadius, style: .continuous))
        .onHover { hovering in
            isHovering = hovering
            if hovering, viewModel.unattendedLoud.contains(incident.id) {
                viewModel.acknowledge(incident)
            }
        }
        .onTapGesture(count: 2) {
            viewModel.open(incident)
        }
        .animation(.spring(response: IncidentsLayout.hoverAnimationResponse, dampingFraction: IncidentsLayout.hoverAnimationDamping), value: isHovering)
        .animation(.spring(response: IncidentsLayout.hoverAnimationResponse, dampingFraction: IncidentsLayout.hoverAnimationDamping), value: activity)
        .contextMenu { contextMenuItems }
    }

    // MARK: Texto

    private var titleLine: some View {
        HStack(spacing: 5.5) {
            SwiftUI.Text(incident.name)
                .font(theme.font(11.5, weight: .bold))
                .foregroundStyle(theme.textPrimary)
                .lineLimit(1)
            if viewModel.isMine(incident) {
                Image(systemName: "person.crop.circle.badge.checkmark")
                    .font(.system(size: theme.scaled(9), weight: .bold))
                    .foregroundStyle(theme.mine)
                    .help(L10n.app("incidents.island.row.assignedToYou", fallback: "Assigned to you"))
            } else if let assignee = NotchwatchCore.Text.nonEmpty(incident.assigneeName) {
                Image(systemName: "person.crop.circle")
                    .font(.system(size: theme.scaled(9), weight: .semibold))
                    .foregroundStyle(theme.textTertiary)
                    .help(assignee)
            }
            if isSnoozed {
                Image(systemName: "moon.zzz.fill")
                    .font(.system(size: theme.scaled(8.5), weight: .bold))
                    .foregroundStyle(theme.snoozed)
                    .help(snoozedHelp)
            }
            if viewModel.unattendedLoud.contains(incident.id) {
                Circle()
                    .fill(priorityColor)
                    .frame(width: IncidentsLayout.compactDotSize, height: IncidentsLayout.compactDotSize)
                    .shadow(color: priorityColor.opacity(theme.glowOpacity), radius: 3)
            }
        }
    }

    @ViewBuilder
    private var metaLine: some View {
        if showsActions {
            IncidentPriorityChip(priority: incident.priority)
                .transition(.opacity)
        } else {
            let chips = metaChips
            ViewThatFits(in: .horizontal) {
                ForEach(Array((1...chips.count).reversed()), id: \.self) { count in
                    HStack(spacing: 6.5) {
                        ForEach(chips.prefix(count)) { chip in
                            IncidentChip(text: chip.text, systemImage: chip.systemImage, tint: chip.tint, isFilled: chip.isFilled)
                        }
                    }
                }
            }
            .transition(.opacity)
        }
    }

    /// Chips de la fila por orden de importancia: si no caben todos se descartan desde el final.
    private var metaChips: [IncidentMetaChip] {
        var chips = [
            IncidentMetaChip(id: "collection", text: incident.collectionName, tint: theme.textSecondary),
            IncidentMetaChip(
                id: "due",
                text: IncidentsFormatting.due(incident.dueOn),
                systemImage: "clock",
                tint: IncidentsFormatting.isOverdue(incident.dueOn) ? theme.failure : nil,
                isFilled: false
            ),
        ]
        if let errors = incident.consoleErrors, errors > 0 {
            chips.append(IncidentMetaChip(
                id: "errors",
                text: IncidentsFormatting.consoleErrors(errors),
                systemImage: "exclamationmark.square",
                tint: priorityColor.opacity(0.9),
                isFilled: false
            ))
        }
        if let reporter = NotchwatchCore.Text.nonEmpty(incident.reporter) {
            chips.append(IncidentMetaChip(id: "reporter", text: reporter, systemImage: "person", isFilled: false))
        }
        if let module = NotchwatchCore.Text.nonEmpty(incident.module) {
            chips.append(IncidentMetaChip(id: "module", text: module, systemImage: "square.on.square", isFilled: false))
        }
        return chips
    }

    private var snoozedHelp: String {
        guard let until = viewModel.snoozedUntil[incident.id] else {
            return L10n.app("incidents.island.row.snoozed", fallback: "Snoozed")
        }
        return IncidentsFormatting.snoozedUntil(until)
    }

    // MARK: Zona derecha

    @ViewBuilder
    private var trailing: some View {
        if let activity {
            IncidentActivityBadge(activity: activity)
        } else if showsActions {
            actions
                .transition(.opacity.combined(with: .move(edge: .trailing)))
        } else {
            SwiftUI.Text(IncidentsFormatting.relativeAge(of: incident.createdAt))
                .font(theme.font(9.5, weight: .medium))
                .foregroundStyle(theme.textTertiary)
                .lineLimit(1)
                .transition(.opacity)
        }
    }

    private var actions: some View {
        HStack(spacing: 4.5) {
            IncidentIconButton(symbol: "arrow.up.right", help: L10n.app("incidents.island.action.open", fallback: "Open")) {
                viewModel.open(incident)
            }
            if viewModel.can(.startProgress, on: incident) {
                IncidentIconButton(
                    symbol: "play.circle",
                    help: L10n.app("incidents.island.action.startProgress.help", fallback: "Mark as in progress (assigns it to you if it has no assignee)")
                ) {
                    viewModel.startProgress(incident)
                }
            }
            rowMenu(symbol: "clock", help: L10n.app("incidents.island.action.snooze", fallback: "Snooze")) {
                snoozeItems
            }
            if viewModel.can(.resolve, on: incident) {
                IncidentTextButton(
                    title: L10n.app("incidents.island.action.resolve", fallback: "Resolve"),
                    systemImage: "checkmark",
                    isProminent: true
                ) {
                    viewModel.resolve(incident)
                }
            }
            rowMenu(symbol: "ellipsis", help: L10n.app("incidents.island.action.more", fallback: "More")) {
                moreItems
            }
        }
    }

    private func rowMenu<Items: View>(symbol: String, help: String, @ViewBuilder items: () -> Items) -> some View {
        Menu {
            items()
        } label: {
            IncidentIconButtonLabel(symbol: symbol)
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .help(help)
    }

    // MARK: Menús

    @ViewBuilder
    private var snoozeItems: some View {
        Button(L10n.app("incidents.island.snooze.15m", fallback: "15 minutes")) { viewModel.snooze(incident, minutes: 15) }
        Button(L10n.app("incidents.island.snooze.1h", fallback: "1 hour")) { viewModel.snooze(incident, minutes: 60) }
        Button(L10n.app("incidents.island.snooze.4h", fallback: "4 hours")) { viewModel.snooze(incident, minutes: 240) }
        Button(L10n.app("incidents.island.snooze.tomorrow", fallback: "Until tomorrow")) { viewModel.snoozeUntilTomorrow(incident) }
    }

    @ViewBuilder
    private var moreItems: some View {
        if viewModel.can(.assignToMe, on: incident), !viewModel.isMine(incident) {
            Button(L10n.app("incidents.island.action.assignToMe", fallback: "Assign to me")) { viewModel.assignToMe(incident) }
        }
        if viewModel.can(.setDueDate(nil), on: incident) {
            Menu(L10n.app("incidents.island.more.dueDate", fallback: "Due date")) { dueDateItems }
        }
        if viewModel.can(.setPriority(incident.priority), on: incident) {
            Menu(L10n.app("incidents.island.more.priority", fallback: "Priority")) { priorityItems }
        }
        Divider()
        Button(L10n.app("incidents.island.more.markSeen", fallback: "Mark as seen")) { viewModel.markSeen(incident) }
    }

    @ViewBuilder
    private var dueDateItems: some View {
        ForEach(DueDateOption.allCases, id: \.self) { option in
            Button(option.title) { viewModel.setDueDate(incident, to: option.date()) }
        }
        Divider()
        Button(L10n.app("incidents.island.due.option.none", fallback: "No due date")) { viewModel.setDueDate(incident, to: nil) }
    }

    @ViewBuilder
    private var priorityItems: some View {
        ForEach(IncidentPriority.descending, id: \.self) { priority in
            Button {
                viewModel.setPriority(incident, to: priority)
            } label: {
                Label(IncidentsFormatting.priorityName(priority), systemImage: theme.symbol(for: priority))
            }
            .disabled(priority == incident.priority)
        }
    }

    @ViewBuilder
    private var contextMenuItems: some View {
        Button(L10n.app("incidents.island.action.open", fallback: "Open")) { viewModel.open(incident) }
        if viewModel.can(.startProgress, on: incident) {
            Button(L10n.app("incidents.island.action.startProgress", fallback: "In progress")) { viewModel.startProgress(incident) }
        }
        if viewModel.can(.resolve, on: incident) {
            Button(L10n.app("incidents.island.action.resolve", fallback: "Resolve")) { viewModel.resolve(incident) }
        }
        Menu(L10n.app("incidents.island.action.snooze", fallback: "Snooze")) { snoozeItems }
        moreItems
    }

    // MARK: Fondo

    @ViewBuilder
    private var rowBackground: some View {
        if isCritical {
            if isHovering {
                theme.criticalRowHoverFill
            } else {
                theme.criticalRowGradient
            }
        } else if isHovering {
            theme.rowHoverFill
        } else {
            theme.rowGradient
        }
    }

    private var strokeColor: Color {
        if isCritical {
            return isHovering ? priorityColor.opacity(0.6) : theme.criticalRowStroke
        }
        return isHovering ? theme.rowHoverStroke : theme.rowStroke
    }

    private var priorityBar: some View {
        UnevenRoundedRectangle(
            cornerRadii: .init(topLeading: 0, bottomLeading: 0, bottomTrailing: 3, topTrailing: 3),
            style: .continuous
        )
        .fill(priorityColor)
        .frame(width: IncidentsLayout.rowBarWidth)
        .padding(.vertical, 11.5)
    }
}

private struct IncidentMetaChip: Identifiable {
    let id: String
    let text: String
    var systemImage: String? = nil
    var tint: Color? = nil
    var isFilled = true
}
