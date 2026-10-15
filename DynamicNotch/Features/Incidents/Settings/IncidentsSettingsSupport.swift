import Foundation
import NotchwatchCore
import SwiftUI
internal import AppKit

/// Textos de la sección de ajustes: siempre `L10n.app` con fallback para que las claves queden explícitas.
enum IncidentsSettingsText {
    static func string(_ key: String, _ fallback: String) -> String {
        L10n.app("incidents.settings.\(key)", fallback: fallback)
    }

    static func key(_ key: String, _ fallback: String) -> LocalizedStringKey {
        LocalizedStringKey(string(key, fallback))
    }

    static func label(_ key: String, _ fallback: String) -> SwiftUI.Text {
        SwiftUI.Text(verbatim: string(key, fallback))
    }

    static func priorityName(_ priority: IncidentPriority) -> String {
        switch priority {
        case .urgente: return string("priority.urgent", "Urgent")
        case .alta: return string("priority.high", "High")
        case .media: return string("priority.medium", "Medium")
        case .baja: return string("priority.low", "Low")
        case .ninguna: return string("priority.none", "No priority")
        }
    }

    static func motifName(_ motif: SoundMotif) -> String {
        switch motif {
        case .chime: return string("motif.chime", "Chime")
        case .drop: return string("motif.drop", "Drop")
        case .triad: return string("motif.triad", "Triad")
        case .alarm: return string("motif.alarm", "Alarm")
        case .tick: return string("motif.tick", "Tick")
        case .glass: return string("motif.glass", "Glass")
        }
    }

    static func hotKeyName(_ choice: HotKeyChoice) -> String {
        switch choice {
        case .off: return string("hotkey.off", "Off")
        case .controlOptionCommandI: return "⌃⌥⌘I"
        case .controlOptionCommandN: return "⌃⌥⌘N"
        case .optionCommandI: return "⌥⌘I"
        }
    }

    static func themeName(_ theme: ThemeMode) -> String {
        switch theme {
        case .automatic: return string("theme.automatic", "Automatic")
        case .dark: return string("theme.dark", "Dark")
        case .light: return string("theme.light", "Light")
        }
    }

    static func fontDesignName(_ design: FontDesignChoice) -> String {
        switch design {
        case .system: return string("font.system", "System")
        case .rounded: return string("font.rounded", "Rounded")
        case .monospaced: return string("font.monospaced", "Monospaced")
        }
    }

    static func textScaleName(_ scale: TextScale) -> String {
        switch scale {
        case .small: return string("textScale.small", "Small")
        case .regular: return string("textScale.regular", "Regular")
        case .large: return string("textScale.large", "Large")
        }
    }

    static func motionName(_ motion: MotionIntensity) -> String {
        switch motion {
        case .off: return string("motion.off", "Off")
        case .subtle: return string("motion.subtle", "Subtle")
        case .normal: return string("motion.normal", "Normal")
        case .lively: return string("motion.lively", "Lively")
        }
    }

    static func seconds(_ value: TimeInterval) -> String {
        let seconds = Int(value.rounded())
        if seconds >= 60, seconds % 60 == 0 {
            return String(format: string("format.minutes", "%d min"), seconds / 60)
        }
        return String(format: string("format.seconds", "%d s"), seconds)
    }
}

/// Mensaje legible del fallo que devuelve el view model al guardar una fuente.
enum IncidentsFailureText {
    static func describe(_ error: any Error) -> String {
        if let failure = error as? IncidentsFailure {
            return failure.message
        }
        return error.localizedDescription
    }
}

/// Conversión entre los colores hexadecimales del perfil («#RRGGBB») y `Color` para el `ColorPicker`.
enum IncidentsHexColor {
    static func color(from hex: String) -> Color {
        var value = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.hasPrefix("#") {
            value.removeFirst()
        }
        guard value.count == 6, let number = UInt32(value, radix: 16) else {
            return Color.gray
        }
        let red = Double((number >> 16) & 0xFF) / 255
        let green = Double((number >> 8) & 0xFF) / 255
        let blue = Double(number & 0xFF) / 255
        return Color(.sRGB, red: red, green: green, blue: blue, opacity: 1)
    }

    static func hex(from color: Color) -> String {
        guard let converted = NSColor(color).usingColorSpace(.sRGB) else {
            return "#A8B7C8"
        }
        let red = Int((converted.redComponent * 255).rounded())
        let green = Int((converted.greenComponent * 255).rounded())
        let blue = Int((converted.blueComponent * 255).rounded())
        return String(format: "#%02X%02X%02X", red, green, blue)
    }

    static func binding(_ hex: Binding<String>) -> Binding<Color> {
        Binding(
            get: { color(from: hex.wrappedValue) },
            set: { hex.wrappedValue = IncidentsHexColor.hex(from: $0) }
        )
    }
}

extension IncidentsViewModel {
    /// Binding sobre una parte del perfil; escribe el struct completo para que el store lo guarde.
    func settingsProfileBinding<Value>(_ keyPath: WritableKeyPath<NotchwatchProfile, Value>) -> Binding<Value> {
        Binding(
            get: { self.profile[keyPath: keyPath] },
            set: { self.profile[keyPath: keyPath] = $0 }
        )
    }

    var settingsAsanaConfig: AsanaSourceConfig? {
        for source in profile.sources {
            if case .asana(let config) = source {
                return config
            }
        }
        return nil
    }

    func settingsReplaceAsanaSource(_ config: AsanaSourceConfig) {
        var sources = profile.sources
        if let index = sources.firstIndex(where: { $0.id == config.id }) {
            sources[index] = .asana(config)
        } else {
            sources.append(.asana(config))
        }
        profile.sources = sources
    }
}

/// Fila con etiqueta y menú de selección que admite títulos ya localizados (texto plano).
struct IncidentsSettingsPickerRow<Option: Hashable>: View {
    let title: String
    let description: String?
    let options: [Option]
    let optionTitle: @MainActor (Option) -> String
    @Binding var selection: Option

    init(
        title: String,
        description: String? = nil,
        options: [Option],
        optionTitle: @escaping @MainActor (Option) -> String,
        selection: Binding<Option>
    ) {
        self.title = title
        self.description = description
        self.options = options
        self.optionTitle = optionTitle
        self._selection = selection
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                SwiftUI.Text(verbatim: title)
                if let description {
                    SwiftUI.Text(verbatim: description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: 12)

            Menu {
                ForEach(options, id: \.self) { option in
                    Button {
                        selection = option
                    } label: {
                        HStack {
                            SwiftUI.Text(verbatim: optionTitle(option))
                            if option == selection {
                                Spacer()
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                SwiftUI.Text(verbatim: optionTitle(selection))
                    .lineLimit(1)
            }
            .fixedSize(horizontal: true, vertical: false)
        }
    }
}

struct IncidentsSettingsDivider: View {
    var leadingPadding: CGFloat = 0

    var body: some View {
        Divider()
            .opacity(0.6)
            .padding(.leading, leadingPadding)
            .frame(maxWidth: .infinity, alignment: .trailing)
    }
}

/// Texto de estado con punto de color, para cabeceras de tarjeta.
struct IncidentsStatusLine: View {
    let text: String
    let tint: Color

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(tint)
                .frame(width: 8, height: 8)
            SwiftUI.Text(verbatim: text)
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
    }
}
