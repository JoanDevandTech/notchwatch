internal import AppKit
import NotchwatchCore
import SwiftUI

/// Panel desplegado: cabecera con contador y selector Todas/Mías, lista de filas con scroll, aviso de
/// conexión y pie con usuario y última lectura. El alto lo calcula `IncidentsLayout.panelSize`.
struct IncidentsPanelView: View {
    @ObservedObject private var viewModel: IncidentsViewModel
    @ObservedObject private var notchViewModel: NotchViewModel
    @Environment(\.isNotchlessScreen) private var isNotchlessScreen

    init(viewModel: IncidentsViewModel, notchViewModel: NotchViewModel) {
        _viewModel = ObservedObject(wrappedValue: viewModel)
        _notchViewModel = ObservedObject(wrappedValue: notchViewModel)
    }

    private var theme: IncidentsTheme {
        IncidentsTheme(appearance: viewModel.profile.appearance)
    }

    private var incidents: [Incident] {
        viewModel.listedIncidents
    }

    private var hasBanner: Bool {
        viewModel.connectionIssue != nil
    }

    private var showOnlyMine: Bool {
        viewModel.showsOnlyMine
    }

    private var headerTint: Color {
        if let priority = viewModel.topPendingPriority {
            return theme.priority(priority)
        }
        return theme.success
    }

    var body: some View {
        VStack(spacing: 0) {
            header
                .frame(height: IncidentsLayout.headerHeight)
            Spacer().frame(height: IncidentsLayout.headerSpacing)
            if let issue = viewModel.connectionIssue {
                banner(issue)
                    .frame(height: IncidentsLayout.bannerHeight)
                Spacer().frame(height: IncidentsLayout.bannerSpacing)
            }
            list
                .frame(height: IncidentsLayout.listHeight(rows: incidents.count, hasBanner: hasBanner))
            Spacer().frame(height: IncidentsLayout.footerSpacing)
            footer
                .frame(height: IncidentsLayout.footerHeight)
        }
        .padding(.top, topPadding)
        .padding(.bottom, IncidentsLayout.panelBottomPadding)
        .padding(.horizontal, isNotchlessScreen ? IncidentsLayout.panelHorizontalPadding.notchless : IncidentsLayout.panelHorizontalPadding.notch)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: isNotchlessScreen ? .center : .top)
        .environment(\.incidentsTheme, theme)
        .incidentsMenuLock()
        .onAppear {
            viewModel.acknowledgeAll()
        }
        .onDisappear {
            notchViewModel.isHoveringScrollableContent = false
        }
    }

    private var topPadding: CGFloat {
        (isNotchlessScreen ? IncidentsLayout.panelNotchlessTopInset : notchViewModel.notchModel.baseHeight) + IncidentsLayout.panelTopPadding
    }

    // MARK: Cabecera

    private var header: some View {
        HStack(spacing: 8.5) {
            IncidentIconTile(
                symbol: viewModel.topPendingPriority.map(theme.symbol(for:)) ?? "checkmark.circle.fill",
                color: headerTint,
                size: IncidentsLayout.headerHeight - 8
            )
            SwiftUI.Text(L10n.app("incidents.island.title", fallback: "Incidents"))
                .font(theme.font(15, weight: .bold))
                .foregroundStyle(theme.textPrimary)
                .lineLimit(1)
            countBadge
            Spacer(minLength: 6.5)
            if viewModel.isConfigured {
                IncidentsScopeSwitch(showOnlyMine: showOnlyMine, mineCount: viewModel.mineCount) { onlyMine in
                    viewModel.setShowOnlyMine(onlyMine)
                }
            }
            tools
        }
    }

    private var countBadge: some View {
        SwiftUI.Text("\(viewModel.visibleCount)")
            .font(theme.font(10, weight: .heavy))
            .monospacedDigit()
            .contentTransition(.numericText())
            .foregroundStyle(headerTint)
            .padding(.horizontal, 7.5)
            .padding(.vertical, 3.5)
            .background(
                RoundedRectangle(cornerRadius: IncidentsLayout.chipCornerRadius + 1, style: .continuous)
                    .fill(headerTint.opacity(theme.orbFillOpacity))
            )
            .overlay(
                RoundedRectangle(cornerRadius: IncidentsLayout.chipCornerRadius + 1, style: .continuous)
                    .strokeBorder(headerTint.opacity(theme.orbStrokeOpacity), lineWidth: 1)
            )
            .animation(.spring(response: IncidentsLayout.hoverAnimationResponse, dampingFraction: IncidentsLayout.hoverAnimationDamping), value: viewModel.visibleCount)
    }

    private var tools: some View {
        HStack(spacing: 4.5) {
            IncidentIconButton(symbol: "arrow.clockwise", help: L10n.app("incidents.island.header.refresh", fallback: "Refresh")) {
                viewModel.refreshNow()
            }
            IncidentIconButton(
                symbol: viewModel.isDoNotDisturb ? "moon.fill" : "moon",
                help: L10n.app("incidents.island.header.doNotDisturb", fallback: "Do not disturb"),
                isActive: viewModel.isDoNotDisturb
            ) {
                viewModel.setDoNotDisturb(viewModel.isDoNotDisturb ? .off : .indefinite)
            }
            IncidentIconButton(
                symbol: viewModel.isMuted ? "speaker.slash.fill" : "speaker.wave.2",
                help: L10n.app("incidents.island.header.mute", fallback: "Mute sounds"),
                isActive: viewModel.isMuted
            ) {
                viewModel.toggleMuted()
            }
            IncidentIconButton(symbol: "gearshape", help: L10n.app("incidents.island.header.settings", fallback: "Settings")) {
                openSettings()
            }
            IncidentIconButton(symbol: "minus", help: L10n.app("incidents.island.header.collapse", fallback: "Collapse")) {
                notchViewModel.handleOutsideClick()
            }
        }
    }

    // MARK: Aviso

    private func banner(_ issue: String) -> some View {
        HStack(spacing: 6.5) {
            Image(systemName: "wifi.exclamationmark")
                .font(.system(size: theme.scaled(10), weight: .bold))
            SwiftUI.Text(issue)
                .font(theme.font(10, weight: .semibold))
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .foregroundStyle(theme.failure)
        .padding(.horizontal, 9.5)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: IncidentsLayout.controlCornerRadius, style: .continuous)
                .fill(theme.failure.opacity(theme.orbFillOpacity))
        )
        .overlay(
            RoundedRectangle(cornerRadius: IncidentsLayout.controlCornerRadius, style: .continuous)
                .strokeBorder(theme.failure.opacity(theme.orbStrokeOpacity), lineWidth: 1)
        )
    }

    // MARK: Lista

    @ViewBuilder
    private var list: some View {
        if !viewModel.isConfigured {
            emptyState(
                symbol: "link.badge.plus",
                title: L10n.app("incidents.island.empty.notConfigured.title", fallback: "No source connected"),
                subtitle: L10n.app("incidents.island.empty.notConfigured.subtitle", fallback: "Connect Asana to start watching incidents"),
                actionTitle: L10n.app("incidents.island.empty.notConfigured.action", fallback: "Set up")
            ) {
                openSettings()
            }
        } else if incidents.isEmpty, showOnlyMine, viewModel.pending.isEmpty == false {
            emptyState(
                symbol: "person.crop.circle.badge.checkmark",
                title: L10n.app("incidents.island.empty.mine.title", fallback: "Nothing assigned to you"),
                subtitle: L10n.app("incidents.island.empty.mine.subtitle", fallback: "Switch to All to see the rest"),
                actionTitle: L10n.app("incidents.island.scope.all", fallback: "All")
            ) {
                viewModel.setShowOnlyMine(false)
            }
        } else if incidents.isEmpty {
            emptyState(
                symbol: "checkmark.seal.fill",
                title: L10n.app("incidents.island.empty.allClear.title", fallback: "All clear"),
                subtitle: L10n.app("incidents.island.empty.allClear.subtitle", fallback: "No open incidents right now"),
                tint: theme.success
            )
        } else {
            rows
        }
    }

    private var rows: some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVStack(spacing: IncidentsLayout.rowSpacing) {
                ForEach(incidents) { incident in
                    IncidentRowView(viewModel: viewModel, incident: incident)
                        .transition(.blurAndFade.combined(with: .opacity))
                }
            }
            .padding(.vertical, 1)
            .animation(.spring(response: IncidentsLayout.hoverAnimationResponse, dampingFraction: IncidentsLayout.hoverAnimationDamping), value: incidents.map(\.id))
        }
        .mask {
            ScrollFadeMask(cornerRadius: IncidentsLayout.rowCornerRadius, maskType: .verticalFade)
        }
        .onHover { hovering in
            notchViewModel.isHoveringScrollableContent = hovering
        }
    }

    private func emptyState(
        symbol: String,
        title: String,
        subtitle: String,
        tint: Color? = nil,
        actionTitle: String? = nil,
        action: (() -> Void)? = nil
    ) -> some View {
        HStack(spacing: 12.5) {
            IncidentIconTile(symbol: symbol, color: tint ?? theme.textSecondary, size: IncidentsLayout.alertOrbSize - 8)
            VStack(alignment: .leading, spacing: 3.5) {
                SwiftUI.Text(title)
                    .font(theme.font(12.5, weight: .bold))
                    .foregroundStyle(theme.textPrimary)
                SwiftUI.Text(subtitle)
                    .font(theme.font(10, weight: .medium))
                    .foregroundStyle(theme.textTertiary)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if let actionTitle, let action {
                IncidentTextButton(title: actionTitle, action: action)
            }
        }
        .padding(.horizontal, 12.5)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: IncidentsLayout.rowCornerRadius, style: .continuous)
                .fill(theme.rowGradient)
        )
        .overlay(
            RoundedRectangle(cornerRadius: IncidentsLayout.rowCornerRadius, style: .continuous)
                .strokeBorder(theme.rowStroke, lineWidth: 1)
        )
    }

    // MARK: Pie

    private var footer: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            HStack(spacing: 6.5) {
                if let identity = viewModel.identity {
                    SwiftUI.Text(IncidentsFormatting.initials(of: identity.name))
                        .font(theme.font(8, weight: .heavy))
                        .foregroundStyle(theme.textPrimary)
                        .frame(width: IncidentsLayout.footerHeight - 2, height: IncidentsLayout.footerHeight - 2)
                        .background(Circle().fill(theme.controlHoverFill))
                    SwiftUI.Text(identity.name)
                        .font(theme.font(10, weight: .medium))
                        .foregroundStyle(theme.textSecondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 6.5)
                Circle()
                    .fill(hasBanner ? theme.failure : theme.success)
                    .frame(width: IncidentsLayout.compactDotSize, height: IncidentsLayout.compactDotSize)
                SwiftUI.Text(IncidentsFormatting.lastUpdated(viewModel.lastPoll, now: context.date))
                    .font(theme.font(10, weight: .medium))
                    .foregroundStyle(theme.textTertiary)
                    .lineLimit(1)
            }
        }
    }

    private func openSettings() {
        SettingsWindowController.shared.showWindow(selecting: .incidents)
    }
}
