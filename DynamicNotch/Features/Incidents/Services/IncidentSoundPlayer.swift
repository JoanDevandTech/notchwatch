import AVFoundation
import Foundation
import NotchwatchCore
import os

/// Motivos sonoros sintetizados al vuelo (sin ficheros de audio), uno por `SoundMotif`.
@MainActor
final class IncidentSoundPlayer {
    private struct Note {
        let frequency: Double
        let start: Double
        let duration: Double
        let decay: Double
        let gain: Double
    }

    /// Partitura de un motivo: notas y cuánto brillan sus armónicos (0 = campana suave, 1 = timbre áspero).
    private struct Score {
        let notes: [Note]
        let brightness: Double
    }

    private static let sampleRate: Double = 44_100

    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private let format = AVAudioFormat(standardFormatWithSampleRate: IncidentSoundPlayer.sampleRate, channels: 1)
    private var buffers: [SoundMotif: AVAudioPCMBuffer] = [:]
    private var isConfigured = false
    private let log = Logger(subsystem: "com.joandev.notchwatch", category: "sound")

    func play(_ motif: SoundMotif, volume: Double) {
        guard volume > 0, let buffer = buffer(for: motif) else { return }
        do {
            try configureIfNeeded()
            if !engine.isRunning {
                try engine.start()
            }
            engine.mainMixerNode.outputVolume = Float(min(max(volume, 0), 1))
            player.stop()
            player.scheduleBuffer(buffer, at: nil, options: [], completionHandler: nil)
            player.play()
        } catch {
            log.error("No se pudo reproducir el sonido: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Genera los seis motivos sin reproducirlos. Devuelve false si alguno no se pudo sintetizar.
    @discardableResult
    func prepare() -> Bool {
        SoundMotif.allCases.allSatisfy { buffer(for: $0) != nil }
    }

    private func configureIfNeeded() throws {
        guard !isConfigured, let format else { return }
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: format)
        engine.prepare()
        isConfigured = true
    }

    private static func score(for motif: SoundMotif) -> Score {
        switch motif {
        case .chime:
            return Score(
                notes: [
                    Note(frequency: 1_046.50, start: 0.00, duration: 0.90, decay: 5.0, gain: 0.30),
                    Note(frequency: 1_567.98, start: 0.14, duration: 1.05, decay: 4.2, gain: 0.26),
                ],
                brightness: 0.35
            )
        case .drop:
            return Score(
                notes: [
                    Note(frequency: 659.26, start: 0.00, duration: 1.50, decay: 2.6, gain: 0.34),
                ],
                brightness: 0.25
            )
        case .triad:
            return Score(
                notes: [
                    Note(frequency: 880.00, start: 0.00, duration: 0.40, decay: 8.0, gain: 0.34),
                    Note(frequency: 1_174.66, start: 0.13, duration: 0.40, decay: 8.0, gain: 0.34),
                    Note(frequency: 1_760.00, start: 0.26, duration: 0.75, decay: 5.5, gain: 0.32),
                ],
                brightness: 0.45
            )
        case .alarm:
            return Score(
                notes: [
                    Note(frequency: 220.00, start: 0.00, duration: 0.16, decay: 10.0, gain: 0.42),
                    Note(frequency: 293.66, start: 0.18, duration: 0.16, decay: 10.0, gain: 0.42),
                    Note(frequency: 220.00, start: 0.42, duration: 0.16, decay: 10.0, gain: 0.42),
                    Note(frequency: 293.66, start: 0.60, duration: 0.30, decay: 7.0, gain: 0.40),
                ],
                brightness: 1.0
            )
        case .tick:
            return Score(
                notes: [
                    Note(frequency: 2_093.00, start: 0.00, duration: 0.09, decay: 30.0, gain: 0.30),
                ],
                brightness: 0.2
            )
        case .glass:
            return Score(
                notes: [
                    Note(frequency: 1_318.51, start: 0.00, duration: 1.10, decay: 3.4, gain: 0.24),
                    Note(frequency: 987.77, start: 0.10, duration: 1.10, decay: 3.2, gain: 0.24),
                    Note(frequency: 783.99, start: 0.20, duration: 1.30, decay: 3.0, gain: 0.26),
                ],
                brightness: 0.3
            )
        }
    }

    private func buffer(for motif: SoundMotif) -> AVAudioPCMBuffer? {
        if let cached = buffers[motif] { return cached }
        guard let format else { return nil }

        let score = IncidentSoundPlayer.score(for: motif)
        let sampleRate = format.sampleRate
        let total = (score.notes.map { $0.start + $0.duration }.max() ?? 1) + 0.05
        let frameCount = AVAudioFrameCount(total * sampleRate)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount),
              let channel = buffer.floatChannelData?[0]
        else { return nil }
        buffer.frameLength = frameCount
        let frames = Int(frameCount)
        for index in 0..<frames {
            channel[index] = 0
        }

        for note in score.notes {
            IncidentSoundPlayer.render(note, brightness: score.brightness, into: channel, frames: frames, sampleRate: sampleRate)
        }
        IncidentSoundPlayer.normalize(channel, frames: frames)

        buffers[motif] = buffer
        return buffer
    }

    private static func render(
        _ note: Note,
        brightness: Double,
        into channel: UnsafeMutablePointer<Float>,
        frames: Int,
        sampleRate: Double
    ) {
        let startFrame = Int(note.start * sampleRate)
        let length = Int(note.duration * sampleRate)
        let release = min(0.02, note.duration * 0.2)
        for offset in 0..<length {
            let index = startFrame + offset
            if index >= frames { break }
            let time = Double(offset) / sampleRate
            let attack = min(1, time / 0.006)
            let tail = min(1, (note.duration - time) / release)
            let envelope = attack * tail * exp(-time * note.decay)
            let phase = 2 * Double.pi * note.frequency * time
            // Fundamental más armónicos que se apagan antes: campana con más o menos brillo.
            var sample = sin(phase)
            sample += (0.25 + 0.35 * brightness) * sin(phase * 2) * exp(-time * note.decay * 1.6)
            sample += (0.08 + 0.22 * brightness) * sin(phase * 3.01) * exp(-time * note.decay * 2.4)
            sample += 0.18 * brightness * sin(phase * 4.02) * exp(-time * note.decay * 3.0)
            channel[index] += Float(sample * envelope * note.gain)
        }
    }

    private static func normalize(_ channel: UnsafeMutablePointer<Float>, frames: Int) {
        var peak: Float = 0
        for index in 0..<frames {
            peak = max(peak, abs(channel[index]))
        }
        guard peak > 0.95 else { return }
        let scale = 0.95 / peak
        for index in 0..<frames {
            channel[index] *= scale
        }
    }
}
