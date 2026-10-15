import NotchwatchCore
import SwiftUI

/// Píldora en reposo: símbolo de la prioridad más alta a la izquierda y contador con punto de
/// estado a la derecha. En pantallas con notch el contenido se reparte a ambos lados del hueco.
struct IncidentsCompactView: View {
    @ObservedObject private var viewModel: IncidentsViewModel
    @Environment(\.notchScale) private var notchScale
    @Environment(\.isNotchlessScreen) private var isNotchlessScreen
    @State private var ambient = IncidentsAmbientState()

    init(viewModel: IncidentsViewModel) {
        _viewModel = ObservedObject(wrappedValue: viewModel)
    }

    private var theme: IncidentsTheme {
        IncidentsTheme(appearance: viewModel.profile.appearance)
    }

    private var presence: IncidentsPresence {
        viewModel.presence
    }

    private var tint: Color {
        switch presence {
        case .idle: return theme.success
        case .pending(let priority), .attention(let priority): return theme.priority(priority)
        }
    }

    private var symbol: String {
        switch presence {
        case .idle: return "checkmark.circle.fill"
        case .pending(let priority), .attention(let priority): return theme.symbol(for: priority)
        }
    }

    private var isAttention: Bool {
        if case .attention = presence { return true }
        return false
    }

    private var peekLabel: String {
        if viewModel.connectionIssue != nil {
            return L10n.app("incidents.island.compact.offline", fallback: "offline")
        }
        if viewModel.badgeCount == 0 {
            return L10n.app("incidents.island.compact.allClear", fallback: "all clear")
        }
        return L10n.app("incidents.island.compact.pending", fallback: "pending")
    }

    var body: some View {
        HStack(spacing: 0) {
            statusSymbol
            counter
                .frame(maxWidth: counterMaxWidth, alignment: .trailing)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.leading, leadingPadding)
        .padding(.trailing, trailingPadding)
        .incidentsAmbient(
            state: $ambient,
            motion: viewModel.profile.behavior.motion,
            presence: presence,
            theme: theme
        )
        .environment(\.incidentsTheme, theme)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText)
    }

    private var statusSymbol: some View {
        Image(systemName: symbol)
            .font(.system(size: IncidentsLayout.compactSymbolSize, weight: .semibold))
            .foregroundStyle(tint)
            .shadow(color: tint.opacity(isAttention ? theme.glowOpacity : 0), radius: isAttention ? 7 : 0)
            .scaleEffect(ambient.breathScale)
            .contentTransition(.symbolEffect(.replace))
            .animation(.spring(response: 0.4, dampingFraction: 0.8), value: symbol)
    }

    private var counter: some View {
        HStack(spacing: 0) {
            if ambient.isPeeking {
                ViewThatFits(in: .horizontal) {
                    SwiftUI.Text(peekLabel)
                        .font(theme.font(IncidentsLayout.compactLabelSize, weight: .semibold))
                        .foregroundStyle(theme.textSecondary)
                        .lineLimit(1)
                        .fixedSize()
                        .padding(.trailing, 6)
                    Color.clear.frame(width: 0, height: 0)
                }
                .transition(.move(edge: .trailing).combined(with: .opacity))
            }
            HStack(spacing: 6) {
                if viewModel.connectionIssue != nil {
                    Image(systemName: "wifi.exclamationmark")
                        .font(.system(size: IncidentsLayout.compactCountSize - 2, weight: .semibold))
                        .foregroundStyle(theme.textTertiary)
                } else {
                    AnimatedLevelText(
                        level: viewModel.badgeCount,
                        fontSize: IncidentsLayout.compactCountSize,
                        color: theme.textPrimary
                    )
                    .fontWeight(.bold)
                    .fixedSize()
                }
                statusDot
            }
        }
    }

    private var statusDot: some View {
        Circle()
            .fill(tint)
            .frame(width: IncidentsLayout.compactDotSize, height: IncidentsLayout.compactDotSize)
            .shadow(color: tint.opacity(theme.glowOpacity), radius: 4)
            .opacity(ambient.isBlinkOn ? 1 : 0.15)
            .scaleEffect(ambient.breathScale)
            .animation(.spring(response: 0.4, dampingFraction: 0.8), value: tint)
    }

    /// Con notch, el contador no puede invadir el hueco físico: se limita a su lado de la píldora.
    private var counterMaxWidth: CGFloat {
        guard !isNotchlessScreen else { return .infinity }
        return max(0, IncidentsLayout.compactExtraWidth(isNotchless: false) / 2 - trailingPadding)
    }

    private var leadingPadding: CGFloat {
        let padding = isNotchlessScreen
            ? IncidentsLayout.compactLeadingPadding.notchless
            : IncidentsLayout.compactLeadingPadding.notch
        return padding.scaled(by: notchScale)
    }

    private var trailingPadding: CGFloat {
        let padding = isNotchlessScreen
            ? IncidentsLayout.compactTrailingPadding.notchless
            : IncidentsLayout.compactTrailingPadding.notch
        return padding.scaled(by: notchScale)
    }

    private var accessibilityText: String {
        let count = viewModel.badgeCount
        let format = L10n.app("incidents.island.compact.accessibility", fallback: "%d pending incidents")
        return String(format: format, locale: .current, count)
    }
}
