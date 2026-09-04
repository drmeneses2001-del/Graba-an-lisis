import Foundation
import AVFoundation

/// Formato canonico de todo el audio que guarda la app.
///
/// 16 kHz mono en enteros de 16 bits: es lo que pide el reconocedor de voz, y
/// es el formato mas pequeno que no pierde inteligibilidad. Un minuto ocupa
/// 1,83 MB por pista, asi que una reunion de dos horas con dos pistas cabe en
/// unos 440 MB de disco y en cero memoria, porque nunca se carga entera.
enum AudioFormatSpec {

    static let sampleRate: Double = 16_000
    static let channels: AVAudioChannelCount = 1
    static let bytesPerFrame = 2

    static var bytesPerSecondPerTrack: Double {
        sampleRate * Double(bytesPerFrame)
    }

    /// Formato de destino para el conversor y para leer del disco.
    static var processingFormat: AVAudioFormat {
        AVAudioFormat(commonFormat: .pcmFormatInt16,
                      sampleRate: sampleRate,
                      channels: channels,
                      interleaved: true)!
    }

    /// Formato en coma flotante, que es lo que quiere `SFSpeechRecognizer`.
    static var recognitionFormat: AVAudioFormat {
        AVAudioFormat(commonFormat: .pcmFormatFloat32,
                      sampleRate: sampleRate,
                      channels: channels,
                      interleaved: false)!
    }

    static func seconds(fromBytes bytes: UInt64) -> TimeInterval {
        Double(bytes) / bytesPerSecondPerTrack
    }

    static func bytes(forSeconds seconds: TimeInterval) -> UInt64 {
        UInt64(max(0, seconds) * bytesPerSecondPerTrack)
    }
}
