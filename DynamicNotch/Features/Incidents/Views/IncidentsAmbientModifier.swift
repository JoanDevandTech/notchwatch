import AppKit
import NotchwatchCore
import SwiftUI

/// Estado que la coreografía ambiental deja leer a la píldora: cuánto respira, si asoma la
/// etiqueta y si el punto está encendido en el parpadeo de atención.
struct IncidentsAmbientState: Equatable {
    var breathScale: CGFloat = 1
    var isPeeking = false
    var isBlinkOn = true
    var isWaving = false
}

/// Vida propia de la píldora: cada `ambientInterval` segundos alterna pulso, ola y despliegue,
/// nunca con el ratón encima ni con movimiento reducido. En `attention` parpadea el punto.
/// Solo anima durante los 2–3 s de cada coreografía; en reposo no hay timeline activa.
struct IncidentsAmbientModifier: ViewModifier {
    @Binding var state: IncidentsAmbientState
    let motion: MotionIntensity
    let presence: IncidentsPresence
    let theme: IncidentsTheme

    @State private var isHovering = false
    @State private var waveProgress: CGFloat = 0

    private enum Choreography: CaseIterable {
        case breathe, wave, peek
    }

    func body(content: Content) -> some View {
        content
            .overlay { waveOverlay }
            .onHover { hovering in
                isHovering = hovering
            }
            .task(id: loopID) {
                await runAmbientLoop()
            }
            .onChange(of: isAttention, initial: true) { _, attention in
                updateBlink(attention)
            }
    }

    private var isAttention: Bool {
        if case .attention = presence { return true }
        return false
    }

    /// La tarea captura `self` al arrancar: se reinicia cuando cambia lo que lee el bucle.
    private var loopID: LoopID {
        LoopID(motion: motion, isIdle: presence == .idle)
    }

    private struct LoopID: Equatable {
        let motion: MotionIntensity
        let isIdle: Bool
    }

    private var reducesMotion: Bool {
        motion == .off || NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    @ViewBuilder
    private var waveOverlay: some View {
        if state.isWaving {
            GeometryReader { proxy in
                let width = proxy.size.width
                LinearGradient(
                    colors: [.clear, theme.waveHighlight, .clear],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .frame(width: width * 0.45)
                .blur(radius: 6)
                .offset(x: -width * 0.5 + (width * 1.5) * waveProgress)
            }
            .allowsHitTesting(false)
            .transition(.opacity)
        }
    }

    // MARK: Bucle

    private func runAmbientLoop() async {
        guard motion != .off else { return }
        var index = 0
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(motion.ambientInterval))
            guard !Task.isCancelled, !isHovering, !reducesMotion else { continue }
            let choreography = presence == .idle ? .breathe : Choreography.allCases[index % Choreography.allCases.count]
            index += 1
            await perform(choreography)
        }
    }

    private func perform(_ choreography: Choreography) async {
        switch choreography {
        case .breathe: await breathe()
        case .wave: await wave()
        case .peek: await peek()
        }
    }

    private func breathe() async {
        let slow = presence == .idle
        let duration = slow ? 1.1 : 0.7
        for _ in 0..<2 {
            withAnimation(.easeInOut(duration: duration)) { state.breathScale = slow ? 1.06 : 1.12 }
            try? await Task.sleep(for: .seconds(duration))
            withAnimation(.easeInOut(duration: duration)) { state.breathScale = 1 }
            try? await Task.sleep(for: .seconds(duration))
        }
    }

    private func wave() async {
        waveProgress = 0
        withAnimation(.easeOut(duration: 0.2)) { state.isWaving = true }
        withAnimation(.easeInOut(duration: 2.2)) { waveProgress = 1 }
        try? await Task.sleep(for: .seconds(2.2))
        withAnimation(.easeIn(duration: 0.2)) { state.isWaving = false }
        try? await Task.sleep(for: .seconds(0.25))
        waveProgress = 0
    }

    private func peek() async {
        withAnimation(.spring(response: 0.45, dampingFraction: 0.8)) { state.isPeeking = true }
        try? await Task.sleep(for: .seconds(2))
        withAnimation(.spring(response: 0.4, dampingFraction: 0.9)) { state.isPeeking = false }
        try? await Task.sleep(for: .seconds(0.45))
    }

    private func updateBlink(_ attention: Bool) {
        guard attention, !reducesMotion else {
            withAnimation(.easeOut(duration: 0.2)) { state.isBlinkOn = true }
            return
        }
        withAnimation(.easeInOut(duration: 0.55).repeatForever(autoreverses: true)) {
            state.isBlinkOn = false
        }
    }
}

extension View {
    func incidentsAmbient(
        state: Binding<IncidentsAmbientState>,
        motion: MotionIntensity,
        presence: IncidentsPresence,
        theme: IncidentsTheme
    ) -> some View {
        modifier(IncidentsAmbientModifier(state: state, motion: motion, presence: presence, theme: theme))
    }
}
