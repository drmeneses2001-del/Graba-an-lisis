import Foundation

enum SessionStage: String, Codable {
    case recording
    case captured
    case transcribed
    case analyzed
    case reported
    case failed

    var displayName: String {
        switch self {
        case .recording: return "Grabando"
        case .captured: return "Audio listo"
        case .transcribed: return "Transcrita"
        case .analyzed: return "Analizada"
        case .reported: return "Informe listo"
        case .failed: return "Con errores"
        }
    }
}

/// Manifiesto de una sesion. Deliberadamente pequeno: los datos pesados viven
/// en ficheros aparte dentro de la misma carpeta y se leen por trozos.
///
/// Cada sesion tiene un unico fichero de audio: lo que sono por la salida de
/// audio del dispositivo mientras la difusion del sistema estuvo activa. No
/// hay pistas separadas ni distincion de origen que mantener.
struct RecordingSession: Codable, Identifiable, Hashable {
    var id: UUID
    var title: String
    var createdAt: Date
    var duration: TimeInterval
    var sampleRate: Double
    var stage: SessionStage
    var localeIdentifier: String
    var notes: String
    /// Bytes de audio en disco, para poder avisar antes de quedarnos sin sitio.
    var audioBytes: UInt64
    /// Motivo por el que la captura termino antes de tiempo, si aplica.
    var truncationReason: String?

    init(id: UUID = UUID(),
         title: String,
         createdAt: Date = Date(),
         duration: TimeInterval = 0,
         sampleRate: Double = AudioFormatSpec.sampleRate,
         stage: SessionStage = .recording,
         localeIdentifier: String = Locale.current.identifier,
         notes: String = "",
         audioBytes: UInt64 = 0,
         truncationReason: String? = nil) {
        self.id = id
        self.title = title
        self.createdAt = createdAt
        self.duration = duration
        self.sampleRate = sampleRate
        self.stage = stage
        self.localeIdentifier = localeIdentifier
        self.notes = notes
        self.audioBytes = audioBytes
        self.truncationReason = truncationReason
    }

    var directoryURL: URL { AppGroup.directory(for: id) }
    var audioURL: URL { directoryURL.appendingPathComponent("audio.pcm") }
    var transcriptURL: URL { directoryURL.appendingPathComponent("transcript.json") }
    var analysisURL: URL { directoryURL.appendingPathComponent("analysis.json") }
    var reportURL: URL { directoryURL.appendingPathComponent("informe.pdf") }
    var manifestURL: URL { directoryURL.appendingPathComponent("session.json") }
}
