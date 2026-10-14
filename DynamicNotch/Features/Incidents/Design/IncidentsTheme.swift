import AppKit
import NotchwatchCore
import SwiftUI

/// Tokens visuales de la isla de incidencias. El cuerpo del notch siempre es negro, así que los
/// tokens oscuros son la base; el tema claro solo aclara un poco textos y chips.
struct IncidentsTheme: Equatable {
    let appearance: AppearanceSettings
    let isDark: Bool

    init(appearance: AppearanceSettings, isDark: Bool) {
        self.appearance = appearance
        self.isDark = isDark
    }

    init(appearance: AppearanceSettings) {
        self.init(appearance: appearance, isDark: IncidentsTheme.resolveIsDark(appearance.theme))
    }

    static let `default` = IncidentsTheme(appearance: .default, isDark: true)

    // MARK: Texto

    var textPrimary: Color { isDark ? Color(hex: "#EDF2F6") : Color(hex: "#F7FAFC") }
    var textSecondary: Color { isDark ? Color(hex: "#A8B7C8") : Color(hex: "#BCC8D6") }
    var textTertiary: Color { isDark ? Color(hex: "#7E8DA1") : Color(hex: "#95A3B5") }
    var textOnAccent: Color { Color(hex: "#111720") }

    // MARK: Superficies

    var chipFill: Color { Color.white.opacity(isDark ? 0.045 : 0.075) }
    var chipStroke: Color { Color.white.opacity(isDark ? 0.10 : 0.14) }
    var controlFill: Color { Color.white.opacity(isDark ? 0.045 : 0.07) }
    var controlHoverFill: Color { Color.white.opacity(isDark ? 0.14 : 0.18) }
    var controlStroke: Color { Color.white.opacity(0.10) }
    var rowGradient: LinearGradient {
        LinearGradient(
            colors: [Color(hex: "#1D2530"), Color(hex: "#151B24")],
            startPoint: .leading,
            endPoint: .trailing
        )
    }
    var rowHoverFill: Color { Color(hex: "#222D39") }
    var rowStroke: Color { Color.white.opacity(0.095) }
    var rowHoverStroke: Color { Color(hex: "#75859A").opacity(0.56) }
    var criticalRowGradient: LinearGradient {
        LinearGradient(
            colors: [Color(hex: "#33252B"), Color(hex: "#1B1E26")],
            startPoint: .leading,
            endPoint: .trailing
        )
    }
    var criticalRowHoverFill: Color { Color(hex: "#30262C") }
    var criticalRowStroke: Color { priority(.urgente).opacity(0.26) }
    var separator: Color { Color.white.opacity(0.08) }
    var divider: Color { Color.white.opacity(0.06) }

    // MARK: Estado

    var success: Color { Color(hex: "#85BAA8") }
    var failure: Color { Color(hex: "#E78580") }
    var mine: Color { Color(hex: "#8DBBF2") }
    var snoozed: Color { textTertiary }
    var waveHighlight: Color { Color(hex: "#ADC1D4").opacity(0.22) }
    var orbFillOpacity: Double { 0.14 }
    var orbStrokeOpacity: Double { 0.32 }
    var glowOpacity: Double { 0.55 }

    // MARK: Colores por prioridad y colección

    func priority(_ priority: IncidentPriority) -> Color {
        Color(hex: appearance.color(for: priority))
    }

    func collection(_ style: CollectionStyle) -> Color {
        Color(hex: style.colorHex)
    }

    func symbol(for priority: IncidentPriority) -> String {
        switch priority {
        case .urgente: return "flame.fill"
        case .alta: return "exclamationmark.triangle.fill"
        case .media: return "exclamationmark.circle.fill"
        case .baja: return "info.circle.fill"
        case .ninguna: return "circle.dashed"
        }
    }

    // MARK: Tipografía

    func font(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size * appearance.textScale.factor, weight: weight, design: fontDesign)
    }

    func scaled(_ size: CGFloat) -> CGFloat {
        size * appearance.textScale.factor
    }

    private var fontDesign: Font.Design {
        switch appearance.fontDesign {
        case .system: return .default
        case .rounded: return .rounded
        case .monospaced: return .monospaced
        }
    }

    // MARK: Hex

    static func hex(from color: Color) -> String {
        guard let nsColor = NSColor(color).usingColorSpace(.sRGB) else { return "#A8B7C8" }
        let red = Int((nsColor.redComponent * 255).rounded())
        let green = Int((nsColor.greenComponent * 255).rounded())
        let blue = Int((nsColor.blueComponent * 255).rounded())
        return String(format: "#%02X%02X%02X", red, green, blue)
    }

    private static func resolveIsDark(_ mode: ThemeMode) -> Bool {
        switch mode {
        case .dark: return true
        case .light: return false
        case .automatic:
            let match = NSApp?.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua])
            return match != .aqua
        }
    }
}

extension Color {
    /// Acepta «#RRGGBB», «RRGGBB» y «#RRGGBBAA»; un valor inválido devuelve el gris de la paleta.
    init(hex: String) {
        var digits = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if digits.hasPrefix("#") { digits.removeFirst() }
        guard let value = UInt64(digits, radix: 16), digits.count == 6 || digits.count == 8 else {
            self = Color(red: 0xA8 / 255, green: 0xB7 / 255, blue: 0xC8 / 255)
            return
        }
        let hasAlpha = digits.count == 8
        let red = Double((value >> (hasAlpha ? 24 : 16)) & 0xFF) / 255
        let green = Double((value >> (hasAlpha ? 16 : 8)) & 0xFF) / 255
        let blue = Double((value >> (hasAlpha ? 8 : 0)) & 0xFF) / 255
        let alpha = hasAlpha ? Double(value & 0xFF) / 255 : 1
        self = Color(.sRGB, red: red, green: green, blue: blue, opacity: alpha)
    }

    var hexString: String {
        IncidentsTheme.hex(from: self)
    }
}

struct IncidentsThemeKey: EnvironmentKey {
    static let defaultValue = IncidentsTheme.default
}

extension EnvironmentValues {
    var incidentsTheme: IncidentsTheme {
        get { self[IncidentsThemeKey.self] }
        set { self[IncidentsThemeKey.self] = newValue }
    }
}
