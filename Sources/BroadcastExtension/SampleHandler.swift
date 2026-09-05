import Foundation
import ReplayKit
import CoreMedia
import os

/// Captura del audio que suena por la salida del dispositivo.
///
/// iOS no deja que una app lea la salida de audio de otras apps. La unica via
/// soportada es una extension de difusion de ReplayKit: cuando el usuario
/// arranca la difusion desde el selector del sistema, iOS entrega aqui el
/// audio de las apps (`.audioApp`). El picker no ofrece la opcion de mezclar
/// el microfono, asi que solo se recibe ese tipo de muestra.
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
    private var writer: PCMFileWriter?
    private let converter = SampleBufferConverter()

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

        var audioCap = limits.maxAudioBytes
        let freeDisk = MemoryReporter.freeDiskBytes()
        if freeDisk > 0 {
            audioCap = min(audioCap, freeDisk / 3)
        }

        let title = Self.defaultTitle(from: setupInfo)
        var session = RecordingSession(title: title, stage: .recording)
        startedAt = Date()
        session.createdAt = startedAt

        do {
            try FileManager.default.createDirectory(at: session.directoryURL,
                                                    withIntermediateDirectories: true)
            writer = try PCMFileWriter(url: session.audioURL, maxBytes: audioCap)
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
        closeWriter()
        publishHandoff(force: true, finished: true)
    }

    // MARK: - Muestras

    override func processSampleBuffer(_ sampleBuffer: CMSampleBuffer,
                                      with sampleBufferType: RPSampleBufferType) {
        guard !didFinish else { return }

        switch sampleBufferType {
        case .audioApp:
            guard let writer, !writer.isCapped else { break }
            converter.convert(sampleBuffer) { bytes in
                _ = writer.append(bytes)
            }
        case .audioMic, .video:
            // Sin micrófono ni vídeo: el picker no lo ofrece y no aportan
            // nada al análisis, solo memoria y disco.
            return
        @unknown default:
            return
        }

        enforceBudgets()
        publishHandoff(force: false)
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

        if writer?.isCapped == true {
            finish(withMessage: "Se alcanzó el límite de espacio reservado para esta sesión.")
        }
    }

    private func finish(withMessage message: String) {
        guard !didFinish else { return }
        didFinish = true
        stopReason = message
        closeWriter()
        publishHandoff(force: true, finished: true)

        let error = NSError(domain: "com.grabaanalisis.broadcast",
                            code: 1,
                            userInfo: [NSLocalizedDescriptionKey: message])
        finishBroadcastWithError(error)
    }

    private func closeWriter() {
        writer?.close()
        writeManifest(finished: true)
    }

    // MARK: - Traspaso a la app

    private func writeManifest(finished: Bool = false) {
        guard var session else { return }
        session.duration = Date().timeIntervalSince(startedAt)
        session.audioBytes = writer?.bytesWritten ?? 0
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
            bytes: writer?.bytesWritten ?? 0,
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
