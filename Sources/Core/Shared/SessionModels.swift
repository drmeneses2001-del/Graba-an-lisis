import Foundation

/// De donde salio el audio de una sesion.
enum CaptureSource: String, Codable, CaseIterable {
    /// Extension de ReplayKit: audio de las apps + microfono, todo el sistema.
    case broadcast
    /// Microfono de la app en primer plano o en segundo plano.
    case microphone

    var displayName: String {
        switch self {
        case .broadcast: return "Difusión del sistema"
        case .microphone: return "Micrófono"
        }
    }
}

/// Las dos pistas que puede tener una sesion. Mantenerlas separadas es lo que
/// permite distinguir quien hablo por el altavoz (la otra parte de la llamada,
/// el video, el podcast) de quien hablo en la sala.
enum AudioTrack: String, Codable, CaseIterable, Identifiable {
    case device   // lo que salio por la salida de audio
    case local    // lo que entro por el microfono

    var id: String { rawValue }

    var fileName: String {
        switch self {
        case .device: return "audio_device.pcm"
        case .local: return "audio_local.pcm"
        }
    }

    var speakerLabel: String {
        switch self {
        case .device: return "Interlocutor remoto"
        case .local: return "Participante local"
        }
    }
}

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
struct RecordingSession: Codable, Identifiable, Hashable {
    var id: UUID
    var title: String
    var createdAt: Date
    var duration: TimeInterval
    var source: CaptureSource
    var sampleRate: Double
    var tracks: [AudioTrack]
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
         source: CaptureSource,
         sampleRate: Double = AudioFormatSpec.sampleRate,
         tracks: [AudioTrack] = [],
         stage: SessionStage = .recording,
         localeIdentifier: String = Locale.current.identifier,
         notes: String = "",
         audioBytes: UInt64 = 0,
         truncationReason: String? = nil) {
        self.id = id
        self.title = title
        self.createdAt = createdAt
        self.duration = duration
        self.source = source
        self.sampleRate = sampleRate
        self.tracks = tracks
        self.stage = stage
        self.localeIdentifier = localeIdentifier
        self.notes = notes
        self.audioBytes = audioBytes
        self.truncationReason = truncationReason
    }

    var directoryURL: URL { AppGroup.directory(for: id) }

    func trackURL(_ track: AudioTrack) -> URL {
        directoryURL.appendingPathComponent(track.fileName)
    }

    var transcriptURL: URL { directoryURL.appendingPathComponent("transcript.json") }
    var analysisURL: URL { directoryURL.appendingPathComponent("analysis.json") }
    var reportURL: URL { directoryURL.appendingPathComponent("informe.pdf") }
    var manifestURL: URL { directoryURL.appendingPathComponent("session.json") }
}
