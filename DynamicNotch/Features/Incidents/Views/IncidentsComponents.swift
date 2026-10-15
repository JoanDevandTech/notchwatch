import NotchwatchCore
import SwiftUI

/// Chip de texto pequeño (colección, reportada por, módulo, vencimiento).
struct IncidentChip: View {
    @Environment(\.incidentsTheme) private var theme
    let text: String
    var systemImage: String? = nil
    var tint: Color? = nil
    var isFilled = true

    var body: some View {
        HStack(spacing: 3.5) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: theme.scaled(8), weight: .semibold))
            }
            SwiftUI.Text(text)
                .font(theme.font(9.5, weight: isFilled ? .semibold : .medium))
                .lineLimit(1)
                .fixedSize()
        }
        .foregroundStyle(tint ?? (isFilled ? theme.textSecondary : theme.textTertiary))
        .padding(.horizontal, isFilled ? 6.5 : 0)
        .padding(.vertical, isFilled ? 2.5 : 0)
        .background {
            if isFilled {
                RoundedRectangle(cornerRadius: IncidentsLayout.chipCornerRadius, style: .continuous)
                    .fill(theme.chipFill)
            }
        }
    }
}

/// Chip de prioridad en mayúsculas con el color de la prioridad.
struct IncidentPriorityChip: View {
    @Environment(\.incidentsTheme) private var theme
    let priority: IncidentPriority

    var body: some View {
        let color = theme.priority(priority)
        SwiftUI.Text(IncidentsFormatting.priorityName(priority).uppercased())
            .font(theme.font(8.5, weight: .heavy))
            .kerning(0.4)
            .lineLimit(1)
            .fixedSize()
            .foregroundStyle(color)
            .padding(.horizontal, 6.5)
            .padding(.vertical, 2.5)
            .background(
                RoundedRectangle(cornerRadius: IncidentsLayout.chipCornerRadius, style: .continuous)
                    .fill(color.opacity(theme.orbFillOpacity))
            )
            .overlay(
                RoundedRectangle(cornerRadius: IncidentsLayout.chipCornerRadius, style: .continuous)
                    .strokeBorder(color.opacity(theme.orbStrokeOpacity), lineWidth: 1)
            )
    }
}

/// Cuadrado redondeado con el icono de una colección o prioridad sobre su color atenuado.
struct IncidentIconTile: View {
    @Environment(\.incidentsTheme) private var theme
    let symbol: String
    let color: Color
    let size: CGFloat
    var hasHalo = false

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.32, style: .continuous)
                .fill(color.opacity(theme.orbFillOpacity))
            RoundedRectangle(cornerRadius: size * 0.32, style: .continuous)
                .strokeBorder(color.opacity(theme.orbStrokeOpacity), lineWidth: 1)
            Image(systemName: symbol)
                .font(.system(size: size * 0.42, weight: .bold))
                .foregroundStyle(color)
        }
        .frame(width: size, height: size)
        .shadow(color: color.opacity(hasHalo ? theme.glowOpacity : 0), radius: hasHalo ? 10 : 0)
    }
}

/// Botón cuadrado de icono con borde fino y resaltado al pasar el ratón.
struct IncidentIconButton: View {
    @Environment(\.incidentsTheme) private var theme
    let symbol: String
    let help: String
    var size: CGFloat = IncidentsLayout.rowActionSize
    var isActive = false
    var activeTint: Color? = nil
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            IncidentIconButtonLabel(symbol: symbol, size: size, isActive: isActive, activeTint: activeTint, isHovering: isHovering)
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(help)
        .onHover { isHovering = $0 }
        .animation(.spring(response: IncidentsLayout.hoverAnimationResponse, dampingFraction: IncidentsLayout.hoverAnimationDamping), value: isHovering)
    }
}

/// Etiqueta del botón de icono; también sirve de etiqueta para los `Menu` de las filas.
struct IncidentIconButtonLabel: View {
    @Environment(\.incidentsTheme) private var theme
    let symbol: String
    var size: CGFloat = IncidentsLayout.rowActionSize
    var isActive = false
    var activeTint: Color? = nil
    var isHovering = false

    var body: some View {
        let tint = activeTint ?? theme.priority(.urgente)
        Image(systemName: symbol)
            .font(.system(size: size * 0.46, weight: .semibold))
            .foregroundStyle(isActive ? tint : (isHovering ? theme.textPrimary : theme.textSecondary))
            .frame(width: size, height: size)
            .background(
                RoundedRectangle(cornerRadius: IncidentsLayout.controlCornerRadius, style: .continuous)
                    .fill(isActive ? tint.opacity(theme.orbFillOpacity) : (isHovering ? theme.controlHoverFill : theme.controlFill))
            )
            .overlay(
                RoundedRectangle(cornerRadius: IncidentsLayout.controlCornerRadius, style: .continuous)
                    .strokeBorder(isActive ? tint.opacity(theme.orbStrokeOpacity) : theme.controlStroke, lineWidth: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: IncidentsLayout.controlCornerRadius, style: .continuous))
    }
}

/// Botón con texto («Resolver», «Abrir», «Configurar»).
struct IncidentTextButton: View {
    @Environment(\.incidentsTheme) private var theme
    let title: String
    var systemImage: String? = nil
    var isProminent = false
    var height: CGFloat = IncidentsLayout.rowActionSize
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4.5) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: theme.scaled(9.5), weight: .bold))
                }
                SwiftUI.Text(title)
                    .font(theme.font(10.5, weight: .bold))
                    .lineLimit(1)
            }
            .foregroundStyle(isProminent ? theme.textOnAccent : (isHovering ? theme.textPrimary : theme.textSecondary))
            .padding(.horizontal, 9.5)
            .frame(height: height)
            .background(
                RoundedRectangle(cornerRadius: IncidentsLayout.controlCornerRadius, style: .continuous)
                    .fill(isProminent ? theme.textPrimary.opacity(isHovering ? 1 : 0.9) : (isHovering ? theme.controlHoverFill : theme.controlFill))
            )
            .overlay(
                RoundedRectangle(cornerRadius: IncidentsLayout.controlCornerRadius, style: .continuous)
                    .strokeBorder(isProminent ? .clear : theme.controlStroke, lineWidth: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: IncidentsLayout.controlCornerRadius, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .animation(.spring(response: IncidentsLayout.hoverAnimationResponse, dampingFraction: IncidentsLayout.hoverAnimationDamping), value: isHovering)
    }
}

/// Selector Todas / Mías.
struct IncidentsScopeSwitch: View {
    @Environment(\.incidentsTheme) private var theme
    let showOnlyMine: Bool
    let mineCount: Int
    let onSelect: (Bool) -> Void

    var body: some View {
        HStack(spacing: 2) {
            segment(L10n.app("incidents.island.scope.all", fallback: "All"), isSelected: !showOnlyMine) {
                onSelect(false)
            }
            segment(
                L10n.app("incidents.island.scope.mine", fallback: "Mine") + (mineCount > 0 ? " \(mineCount)" : ""),
                isSelected: showOnlyMine
            ) {
                onSelect(true)
            }
        }
        .padding(2)
        .background(
            RoundedRectangle(cornerRadius: IncidentsLayout.controlCornerRadius, style: .continuous)
                .fill(theme.controlFill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: IncidentsLayout.controlCornerRadius, style: .continuous)
                .strokeBorder(theme.controlStroke, lineWidth: 1)
        )
    }

    private func segment(_ title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            SwiftUI.Text(title)
                .font(theme.font(10, weight: .semibold))
                .foregroundStyle(isSelected ? theme.textPrimary : theme.textTertiary)
                .padding(.horizontal, 8.5)
                .frame(height: IncidentsLayout.rowActionSize - 4)
                .background(
                    RoundedRectangle(cornerRadius: IncidentsLayout.controlCornerRadius - 2, style: .continuous)
                        .fill(isSelected ? theme.controlHoverFill : .clear)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .animation(.spring(response: IncidentsLayout.hoverAnimationResponse, dampingFraction: IncidentsLayout.hoverAnimationDamping), value: isSelected)
    }
}

/// Indicador de la acción en curso o terminada en una fila.
struct IncidentActivityBadge: View {
    @Environment(\.incidentsTheme) private var theme
    let activity: IncidentRowActivity

    var body: some View {
        switch activity {
        case .working:
            ProgressView()
                .controlSize(.small)
                .frame(width: IncidentsLayout.rowActionSize, height: IncidentsLayout.rowActionSize)
        case .done(let message):
            label(message, symbol: "checkmark.circle.fill", color: theme.success)
        case .failed(let message):
            label(message, symbol: "xmark.octagon.fill", color: theme.failure)
        }
    }

    private func label(_ message: String, symbol: String, color: Color) -> some View {
        HStack(spacing: 4.5) {
            Image(systemName: symbol)
                .foregroundStyle(color)
            SwiftUI.Text(message)
                .foregroundStyle(theme.textSecondary)
                .lineLimit(1)
        }
        .font(theme.font(10, weight: .semibold))
        .help(message)
        .transition(.opacity.combined(with: .scale(scale: 0.9)))
    }
}
