import Foundation

/// Clasificacion del aparato por RAM fisica. Determina los limites de partida;
/// `MemoryGovernor` los ajusta despues con la memoria realmente disponible.
enum DeviceClass: String, Codable, CaseIterable {
    /// iPhone SE, iPad de entrada, dispositivos de 2-3 GB.
    case compact
    /// La mayoria de iPhone y iPad recientes, 4-6 GB.
    case standard
    /// iPad Pro / iPhone Pro con 8 GB o mas.
    case pro

    static var current: DeviceClass {
        let gigabytes = Double(MemoryReporter.physicalMemoryBytes) / 1_073_741_824.0
        if gigabytes < 3.5 { return .compact }
        if gigabytes < 7.0 { return .standard }
        return .pro
    }

    var displayName: String {
        switch self {
        case .compact: return "Compacto"
        case .standard: return "Estándar"
        case .pro: return "Pro"
        }
    }
}

/// Todos los topes que el resto de la app consulta antes de reservar memoria.
/// Ningun subsistema decide su propio tamano de buffer: lo pide aqui.
struct ResourceLimits: Codable, Equatable {

    /// Duracion maxima de una sesion. Mas alla se corta y se avisa.
    var maxSessionSeconds: TimeInterval
    /// Tope de audio en disco por sesion.
    var maxAudioBytes: UInt64
    /// Ventana que se manda de una vez al reconocedor de voz.
    var transcriptionWindowSeconds: TimeInterval
    /// Solapamiento entre ventanas para no cortar palabras.
    var transcriptionOverlapSeconds: TimeInterval
    /// Cuantas ventanas se reconocen a la vez.
    var maxConcurrentTranscriptions: Int
    /// Bytes de PCM que se leen del disco de golpe.
    var audioReadChunkBytes: Int
    /// Caracteres de transcripcion que se mantienen en memoria a la vez.
    var maxTranscriptCharsInMemory: Int
    /// Tamano de cada trozo que se manda al motor de analisis.
    var analysisChunkChars: Int
    /// Puntos maximos por serie en las graficas del PDF.
    var maxChartPoints: Int
    /// Filas maximas por tabla del PDF antes de resumir.
    var maxTableRows: Int
    /// Fraccion de la memoria disponible a partir de la cual frenamos.
    var pressureThreshold: Double

    static func baseline(for deviceClass: DeviceClass) -> ResourceLimits {
        switch deviceClass {
        case .compact:
            return ResourceLimits(
                maxSessionSeconds: 90 * 60,
                maxAudioBytes: 400 * 1_048_576,
                transcriptionWindowSeconds: 30,
                transcriptionOverlapSeconds: 1.0,
                maxConcurrentTranscriptions: 1,
                audioReadChunkBytes: 64 * 1024,
                maxTranscriptCharsInMemory: 180_000,
                analysisChunkChars: 12_000,
                maxChartPoints: 40,
                maxTableRows: 60,
                pressureThreshold: 0.70)
        case .standard:
            return ResourceLimits(
                maxSessionSeconds: 3 * 60 * 60,
                maxAudioBytes: 900 * 1_048_576,
                transcriptionWindowSeconds: 40,
                transcriptionOverlapSeconds: 1.0,
                maxConcurrentTranscriptions: 1,
                audioReadChunkBytes: 128 * 1024,
                maxTranscriptCharsInMemory: 450_000,
                analysisChunkChars: 20_000,
                maxChartPoints: 60,
                maxTableRows: 120,
                pressureThreshold: 0.75)
        case .pro:
            return ResourceLimits(
                maxSessionSeconds: 6 * 60 * 60,
                maxAudioBytes: 2_048 * 1_048_576,
                transcriptionWindowSeconds: 45,
                transcriptionOverlapSeconds: 1.5,
                maxConcurrentTranscriptions: 2,
                audioReadChunkBytes: 256 * 1024,
                maxTranscriptCharsInMemory: 1_200_000,
                analysisChunkChars: 28_000,
                maxChartPoints: 90,
                maxTableRows: 200,
                pressureThreshold: 0.80)
        }
    }

    /// Version degradada de los limites, para cuando el sistema avisa de
    /// presion de memoria. Todo se reduce a la mitad salvo lo que romperia la
    /// funcionalidad si bajara mas.
    func degraded() -> ResourceLimits {
        var limits = self
        limits.transcriptionWindowSeconds = max(20, transcriptionWindowSeconds / 2)
        limits.maxConcurrentTranscriptions = 1
        limits.audioReadChunkBytes = max(32 * 1024, audioReadChunkBytes / 2)
        limits.maxTranscriptCharsInMemory = max(60_000, maxTranscriptCharsInMemory / 2)
        limits.analysisChunkChars = max(6_000, analysisChunkChars / 2)
        limits.maxChartPoints = max(20, maxChartPoints / 2)
        limits.maxTableRows = max(30, maxTableRows / 2)
        return limits
    }
}
