import NotchwatchCore
import SwiftUI

/// Live activity de incidencias: píldora compacta con el contador y panel desplegable con la lista.
struct IncidentsNotchContent: NotchContentProtocol, DynamicIslandCustomizable {
    let id = NotchContentRegistry.Incidents.pending.id

    let incidentsViewModel: IncidentsViewModel
    let notchViewModel: NotchViewModel

    var priority: Int { NotchContentRegistry.Incidents.pending.priority }
    var isExpandable: Bool { true }

    var windowLink: (@MainActor () -> Void)? {
        { [notchViewModel] in
            notchViewModel.expandActiveLiveActivity()
        }
    }

    var strokeColor: Color {
        IncidentsStrokePalette.color(for: incidentsViewModel.presence, appearance: incidentsViewModel.profile.appearance)
    }

    private var rows: Int {
        min(incidentsViewModel.listedIncidents.count, IncidentsLayout.maxVisibleRows)
    }

    private var hasBanner: Bool {
        incidentsViewModel.connectionIssue != nil
    }

    func size(baseWidth: CGFloat, baseHeight: CGFloat) -> CGSize {
        .init(width: baseWidth + IncidentsLayout.compactExtraWidth(isNotchless: false), height: baseHeight)
    }

    func dynamicIslandSize(baseWidth: CGFloat, baseHeight: CGFloat) -> CGSize {
        .init(width: baseWidth + IncidentsLayout.compactExtraWidth(isNotchless: true), height: baseHeight)
    }

    func expandedSize(baseWidth: CGFloat, baseHeight: CGFloat) -> CGSize {
        IncidentsLayout.panelSize(
            baseWidth: baseWidth,
            baseHeight: baseHeight,
            rows: rows,
            hasBanner: hasBanner,
            isNotchless: false
        )
    }

    func expandedDynamicIslandSize(baseWidth: CGFloat, baseHeight: CGFloat) -> CGSize {
        IncidentsLayout.panelSize(
            baseWidth: baseWidth,
            baseHeight: baseHeight,
            rows: rows,
            hasBanner: hasBanner,
            isNotchless: true
        )
    }

    func expandedCornerRadius(baseRadius: CGFloat) -> (top: CGFloat, bottom: CGFloat) {
        IncidentsLayout.panelCornerRadius
    }

    func dynamicIslandCornerRadius(baseHeight: CGFloat) -> CGFloat {
        baseHeight * 0.5
    }

    func expandedDynamicIslandCornerRadius(baseHeight: CGFloat) -> CGFloat {
        min(baseHeight * 0.2, IncidentsLayout.panelCornerRadius.bottom)
    }

    @MainActor
    func makeView() -> AnyView {
        AnyView(IncidentsCompactView(viewModel: incidentsViewModel))
    }

    @MainActor
    func makeExpandedView() -> AnyView {
        AnyView(IncidentsPanelView(viewModel: incidentsViewModel, notchViewModel: notchViewModel))
    }
}

/// Color del borde del notch según la presencia: el de la prioridad más alta, atenuado.
enum IncidentsStrokePalette {
    static let idleOpacity = 0.2
    static let pendingOpacity = 0.3
    static let attentionOpacity = 0.5

    static func color(for presence: IncidentsPresence, appearance: AppearanceSettings) -> Color {
        switch presence {
        case .idle:
            return .white.opacity(idleOpacity)
        case .pending(let priority):
            return color(hex: appearance.color(for: priority)).opacity(pendingOpacity)
        case .attention(let priority):
            return color(hex: appearance.color(for: priority)).opacity(attentionOpacity)
        }
    }

    /// «#RRGGBB» → Color; blanco si el texto no es un color válido.
    static func color(hex: String) -> Color {
        var digits = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if digits.hasPrefix("#") {
            digits.removeFirst()
        }
        guard digits.count == 6, let value = UInt32(digits, radix: 16) else { return .white }
        return Color(
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255
        )
    }
}
