import Foundation
import AVFoundation
import Combine
import os

/// Grabacion por microfono dentro de la app.
///
/// Es la via universal: funciona sin difusion del sistema y captura tanto la voz
/// de la sala como lo que sale por el altavoz. La difusion de ReplayKit da mejor
/// calidad para el audio de las apps, pero exige que el usuario la arranque
/// desde el selector del sistema; esta ruta no.
@MainActor
final class MicrophoneCaptureController: NSObject, ObservableObject {

    enum CaptureError: LocalizedError {
        case permissionDenied
        case engineFailure(String)

        var errorDescription: String? {
            switch self {
            case .permissionDenied:
                return "Sin permiso de micrófono. Actívalo en Ajustes › Privacidad › Micrófono."
            case .engineFailure(let detail):
                return "No se pudo iniciar la captura de audio: \(detail)"
            }
        }
    }

    @Published private(set) var isRecording = false
    @Published private(set) var elapsed: TimeInterval = 0
    @Published private(set) var level: Float = 0
    @Published private(set) var truncationReason: String?

    private let engine = AVAudioEngine()
    private var converter: AVAudioConverter?
    private var writer: PCMFileWriter?
    private var outputBuffer: AVAudioPCMBuffer?
    private var session: RecordingSession?
    private var startedAt = Date()
    private var timer: Timer?
    private var maxSeconds: TimeInterval = 3 * 60 * 60
    private let log = Logger(subsystem: "com.grabaanalisis.app", category: "microfono")

    // MARK: - Permisos

    static func requestPermission() async -> Bool {
        await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }
    }

    // MARK: - Control

    func start(title: String, limits: ResourceLimits, maxSeconds: TimeInterval) async throws -> RecordingSession {
        guard !isRecording else { throw CaptureError.engineFailure("Ya hay una grabación en curso.") }
        guard await Self.requestPermission() else { throw CaptureError.permissionDenied }

        self.maxSeconds = maxSeconds
        truncationReason = nil

        let audioSession = AVAudioSession.sharedInstance()
        do {
            // `mixWithOthers` deja que siga sonando lo que estemos analizando;
            // `defaultToSpeaker` evita que el audio se desvie al auricular.
            try audioSession.setCategory(.playAndRecord,
                                         mode: .spokenAudio,
                                         options: [.mixWithOthers, .defaultToSpeaker, .allowBluetooth])
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            throw CaptureError.engineFailure(error.localizedDescription)
        }

        var session = RecordingSession(title: title,
                                       source: .microphone,
                                       tracks: [.local],
                                       stage: .recording)
        startedAt = Date()
        session.createdAt = startedAt

        do {
            try FileManager.default.createDirectory(at: session.directoryURL, withIntermediateDirectories: true)
            writer = try PCMFileWriter(url: session.trackURL(.local), maxBytes: limits.maxAudioBytes)
        } catch {
            throw CaptureError.engineFailure(error.localizedDescription)
        }

        let input = engine.inputNode
        let inputFormat = input.outputFormat(forBus: 0)
        guard inputFormat.sampleRate > 0 else {
            throw CaptureError.engineFailure("El dispositivo no expone una entrada de audio válida.")
        }
        let outputFormat = AudioFormatSpec.processingFormat
        converter = AVAudioConverter(from: inputFormat, to: outputFormat)
        converter?.sampleRateConverterQuality = AVAudioQuality.medium.rawValue

        // El tamano del tap se toma de los limites: en aparatos justos se pide
        // menos audio por callback para que la cola nunca crezca.
        let tapFrames = AVAudioFrameCount(max(1024, limits.audioReadChunkBytes / 4))
        input.installTap(onBus: 0, bufferSize: tapFrames, format: inputFormat) { [weak self] buffer, _ in
            self?.handle(buffer)
        }

        do {
            engine.prepare()
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            throw CaptureError.engineFailure(error.localizedDescription)
        }

        self.session = session
        isRecording = true
        elapsed = 0
        startTicking()
        return session
    }

    @discardableResult
    func stop() -> RecordingSession? {
        guard isRecording else { return session }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        writer?.close()
        timer?.invalidate()
        timer = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)

        guard var session else { return nil }
        session.duration = Date().timeIntervalSince(startedAt)
        session.audioBytes = writer?.bytesWritten ?? 0
        session.stage = .captured
        session.truncationReason = truncationReason
        isRecording = false
        self.session = session
        writer = nil
        converter = nil
        outputBuffer = nil
        return session
    }

    // MARK: - Interno

    private nonisolated func handle(_ buffer: AVAudioPCMBuffer) {
        // El tap llega en un hilo de audio en tiempo real: aqui no se puede
        // reservar memoria ni tocar la interfaz. Se convierte, se escribe y se
        // publica el nivel de forma asincrona.
        Task { @MainActor [weak self] in
            self?.convertAndWrite(buffer)
        }
    }

    private func convertAndWrite(_ buffer: AVAudioPCMBuffer) {
        guard isRecording, let converter, let writer, !writer.isCapped else { return }
        autoreleasepool {
            let outputFormat = AudioFormatSpec.processingFormat
            let ratio = outputFormat.sampleRate / buffer.format.sampleRate
            let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 64
            if outputBuffer == nil || outputBuffer!.frameCapacity < capacity {
                outputBuffer = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: capacity)
            }
            guard let outputBuffer else { return }
            outputBuffer.frameLength = 0

            var consumed = false
            var error: NSError?
            _ = converter.convert(to: outputBuffer, error: &error) { _, status in
                if consumed {
                    status.pointee = .noDataNow
                    return nil
                }
                consumed = true
                status.pointee = .haveData
                return buffer
            }
            guard error == nil, outputBuffer.frameLength > 0,
                  let channel = outputBuffer.int16ChannelData
            else { return }

            let frames = Int(outputBuffer.frameLength)
            var sum: Double = 0
            for index in 0..<frames {
                let value = Double(channel[0][index]) / 32_768.0
                sum += value * value
            }
            level = Float((sum / Double(frames)).squareRoot())

            let raw = UnsafeRawBufferPointer(start: channel[0], count: frames * AudioFormatSpec.bytesPerFrame)
            if case .capped = writer.append(raw) {
                truncationReason = "Se alcanzó el límite de espacio reservado para esta sesión."
                _ = stop()
            }
        }
    }

    private func startTicking() {
        let timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.isRecording else { return }
                self.elapsed = Date().timeIntervalSince(self.startedAt)
                if self.elapsed >= self.maxSeconds {
                    self.truncationReason = "Se alcanzó la duración máxima configurada para este dispositivo."
                    _ = self.stop()
                }
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }
}
