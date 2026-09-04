import Foundation

/// Una intervencion continua de una de las dos pistas.
struct Utterance: Codable, Identifiable, Hashable {
    var id: UUID = UUID()
    var track: AudioTrack
    var start: TimeInterval
    var end: TimeInterval
    var text: String
    var confidence: Float

    var speaker: String { track.speakerLabel }
    var duration: TimeInterval { max(0, end - start) }

    var wordCount: Int {
        text.split(whereSeparator: { $0 == " " || $0 == "\n" }).count
    }
}

struct Transcript: Codable {
    var sessionID: UUID
    var localeIdentifier: String
    var generatedAt: Date
    var engine: String
    var utterances: [Utterance]
    /// Fraccion de la grabacion en la que se reconocio habla.
    var coverage: Double

    var wordCount: Int {
        utterances.reduce(0) { $0 + $1.wordCount }
    }

    var duration: TimeInterval {
        utterances.map(\.end).max() ?? 0
    }

    var isEmpty: Bool { utterances.isEmpty }

    /// Texto plano con marcas de tiempo y hablante, que es lo que consume el
    /// motor de analisis.
    var annotatedText: String {
        utterances
            .sorted { $0.start < $1.start }
            .map { utterance in
                "[\(Self.timestamp(utterance.start))] \(utterance.speaker): \(utterance.text)"
            }
            .joined(separator: "\n")
    }

    var plainText: String {
        utterances.sorted { $0.start < $1.start }.map(\.text).joined(separator: " ")
    }

    func utterances(for track: AudioTrack) -> [Utterance] {
        utterances.filter { $0.track == track }.sorted { $0.start < $1.start }
    }

    /// Trocea la transcripcion anotada respetando los limites del aparato y sin
    /// partir intervenciones por la mitad.
    func chunks(maxChars: Int) -> [String] {
        var result: [String] = []
        var current = ""
        for utterance in utterances.sorted(by: { $0.start < $1.start }) {
            let line = "[\(Self.timestamp(utterance.start))] \(utterance.speaker): \(utterance.text)\n"
            if current.count + line.count > maxChars && !current.isEmpty {
                result.append(current)
                current = ""
            }
            current += line
        }
        if !current.isEmpty { result.append(current) }
        return result
    }

    static func timestamp(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded())
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let secs = total % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        }
        return String(format: "%02d:%02d", minutes, secs)
    }
}
