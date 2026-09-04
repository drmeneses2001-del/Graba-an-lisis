import Foundation
import ReplayKit
import CoreMedia
import os

/// Captura del audio que suena en el dispositivo.
///
/// iOS no deja que una app lea la salida de audio de otras apps. La unica via
/// soportada es una extension de difusion de ReplayKit: cuando el usuario
/// arranca la difusion desde el selector del sistema, iOS entrega aqui el audio
/// de las apps (`.audioApp`) y el del microfono (`.audioMic`).
///
/// El proceso vive con un limite de memoria de unos 50 MB. Todo lo que hay aqui
/// esta escrito para no acumular: se convierte cada bloque, se escribe a disco
/// y se descarta. Si la huella se acerca al techo, la difusion se cierra sola
/// con un mensaje claro en vez de dejar que el sistema mate el proceso.
final class SampleHandler: RPBroadcastSampleHandler {

    /// Techo propio, por debajo del limite real de iOS para tener margen.
    private static let memoryBudgetBytes: UInt64 = 38 * 1_048_576
    private static let handoffInterval: TimeInterval = 1.0

    private let log = Logger(subsystem: "com.grabaanalisis.broadcast", category: "captura")

    private var session: RecordingSession?
    private var deviceWriter: PCMFileWriter?
    private var localWriter: PCMFileWriter?
    private let deviceConverter = SampleBufferConverter()
    private let localConverter = SampleBufferConverter()

    private var startedAt = Date()
    private var lastHandoffAt = Date.distantPast
    private var stopReason: String?
    private var maxSessionSeconds: TimeInterval = 3 * 60 * 60
    private var didFinish = false

    // MARK: - Ciclo de vida

    override func broadcastStarted(withSetupInfo setupInfo: [String: NSObject]?) {
        AppGroup.prepareDirectories()

        let limits = ResourceLimits.baseline(for: DeviceClass.current)
        maxSessionSeconds = limits.maxSessionSeconds

        // El tope de disco se reparte entre las dos pistas.
        var perTrackCap = limits.maxAudioBytes / 2
        let freeDisk = MemoryReporter.freeDiskBytes()
        if freeDisk > 0 {
            perTrackCap = min(perTrackCap, freeDisk / 6)
        }

        let title = Self.defaultTitle(from: setupInfo)
        var session = RecordingSession(title: title,
                                       source: .broadcast,
                                       tracks: [.device, .local],
                                       stage: .recording)
        startedAt = Date()
        session.createdAt = startedAt

        do {
            try FileManager.default.createDirectory(at: session.directoryURL,
                                                    withIntermediateDirectories: true)
            deviceWriter = try PCMFileWriter(url: session.trackURL(.device), maxBytes: perTrackCap)
            localWriter = try PCMFileWriter(url: session.trackURL(.local), maxBytes: perTrackCap)
        } catch {
            log.error("No se pudo abrir el almacenamiento: \(error.localizedDescription, privacy: .public)")
            finish(withMessage: "No se pudo preparar el almacenamiento de la grabación.")
            return
        }

        self.session = session
        writeManifest()
        publishHandoff(force: true)
    }

    override func broadcastPaused() {
        publishHandoff(force: true)
    }

    override func broadcastResumed() {
        publishHandoff(force: true)
    }

    override func broadcastFinished() {
        stopReason = stopReason ?? "Difusión finalizada por el usuario."
        closeWriters()
        publishHandoff(force: true, finished: true)
    }

    // MARK: - Muestras

    override func processSampleBuffer(_ sampleBuffer: CMSampleBuffer,
                                      with sampleBufferType: RPSampleBufferType) {
        guard !didFinish else { return }

        switch sampleBufferType {
        case .audioApp:
            write(sampleBuffer, using: deviceConverter, to: deviceWriter)
        case .audioMic:
            write(sampleBuffer, using: localConverter, to: localWriter)
        case .video:
            // El video no se guarda: multiplicaria por cien el disco y la
            // memoria y no aporta nada al analisis.
            return
        @unknown default:
            return
        }

        enforceBudgets()
        publishHandoff(force: false)
    }

    private func write(_ sampleBuffer: CMSampleBuffer,
                       using converter: SampleBufferConverter,
                       to writer: PCMFileWriter?) {
        guard let writer, !writer.isCapped else { return }
        converter.convert(sampleBuffer) { bytes in
            _ = writer.append(bytes)
        }
    }

    // MARK: - Limites

    private func enforceBudgets() {
        let footprint = MemoryReporter.footprintBytes()
        if footprint > Self.memoryBudgetBytes {
            finish(withMessage: "Se alcanzó el límite de memoria de la extensión. La grabación se guardó hasta este punto.")
            return
        }

        let elapsed = Date().timeIntervalSince(startedAt)
        if elapsed >= maxSessionSeconds {
            finish(withMessage: "Se alcanzó la duración máxima para este dispositivo. La grabación se guardó completa hasta este punto.")
            return
        }

        if deviceWriter?.isCapped == true && localWriter?.isCapped == true {
            finish(withMessage: "Se alcanzó el límite de espacio reservado para esta sesión.")
        }
    }

    private func finish(withMessage message: String) {
        guard !didFinish else { return }
        didFinish = true
        stopReason = message
        closeWriters()
        publishHandoff(force: true, finished: true)

        let error = NSError(domain: "com.grabaanalisis.broadcast",
                            code: 1,
                            userInfo: [NSLocalizedDescriptionKey: message])
        finishBroadcastWithError(error)
    }

    private func closeWriters() {
        deviceWriter?.close()
        localWriter?.close()
        writeManifest(finished: true)
    }

    // MARK: - Traspaso a la app

    private func writeManifest(finished: Bool = false) {
        guard var session else { return }
        session.duration = Date().timeIntervalSince(startedAt)
        session.audioBytes = (deviceWriter?.bytesWritten ?? 0) + (localWriter?.bytesWritten ?? 0)
        session.stage = finished ? .captured : .recording
        session.truncationReason = stopReason
        guard let data = try? JSONEncoder.grabaAnalisis.encode(session) else { return }
        try? data.write(to: session.manifestURL, options: .atomic)
        self.session = session
    }

    private func publishHandoff(force: Bool, finished: Bool = false) {
        let now = Date()
        guard force || now.timeIntervalSince(lastHandoffAt) >= Self.handoffInterval else { return }
        lastHandoffAt = now
        guard let session else { return }

        if finished { writeManifest(finished: true) }

        let handoff = CaptureHandoff(
            sessionID: session.id,
            startedAt: startedAt,
            updatedAt: now,
            seconds: now.timeIntervalSince(startedAt),
            bytesDevice: deviceWriter?.bytesWritten ?? 0,
            bytesLocal: localWriter?.bytesWritten ?? 0,
            isFinished: finished,
            footprintBytes: MemoryReporter.footprintBytes(),
            stopReason: stopReason)
        handoff.save()
    }

    private static func defaultTitle(from setupInfo: [String: NSObject]?) -> String {
        if let title = setupInfo?["titulo"] as? String, !title.isEmpty { return title }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "es_ES")
        formatter.dateFormat = "d 'de' MMMM, HH:mm"
        return "Sesión del \(formatter.string(from: Date()))"
    }
}
