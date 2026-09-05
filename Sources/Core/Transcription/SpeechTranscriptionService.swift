import Foundation
import Speech
import AVFoundation
import os

/// Convierte el audio de una sesion en texto con marcas de tiempo.
///
/// El reconocedor de Apple no acepta horas de audio de una vez, asi que el
/// fichero se recorre en ventanas solapadas cuyo tamano lo fija el gobernador
/// de memoria. Cada ventana se reconoce, se queda con su texto y se libera; en
/// ningun momento hay mas de una ventana de audio en memoria.
final class SpeechTranscriptionService {

    enum TranscriptionError: LocalizedError {
        case notAuthorized
        case recognizerUnavailable(String)
        case noAudio

        var errorDescription: String? {
            switch self {
            case .notAuthorized:
                return "Sin permiso de reconocimiento de voz. Actívalo en Ajustes › Privacidad › Reconocimiento de voz."
            case .recognizerUnavailable(let locale):
                return "El reconocimiento de voz no está disponible para \(locale). Prueba con otro idioma o descarga el idioma en Ajustes del sistema."
            case .noAudio:
                return "La sesión no tiene audio utilizable."
            }
        }
    }

    struct Progress {
        var completedWindows: Int
        var totalWindows: Int

        var fraction: Double {
            totalWindows > 0 ? Double(completedWindows) / Double(totalWindows) : 0
        }
    }

    private let log = Logger(subsystem: "com.grabaanalisis.app", category: "transcripcion")

    static func requestAuthorization() async -> Bool {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }
    }

    func transcribe(session: RecordingSession,
                    localeIdentifier: String,
                    forceOnDevice: Bool,
                    limits: ResourceLimits,
                    progress: @escaping @Sendable (Progress) -> Void) async throws -> Transcript {

        guard await Self.requestAuthorization() else { throw TranscriptionError.notAuthorized }

        let locale = Locale(identifier: localeIdentifier)
        guard let recognizer = SFSpeechRecognizer(locale: locale), recognizer.isAvailable else {
            throw TranscriptionError.recognizerUnavailable(localeIdentifier)
        }
        let onDevice = forceOnDevice && recognizer.supportsOnDeviceRecognition
        recognizer.defaultTaskHint = .dictation

        guard FileManager.default.fileSizeBytes(at: session.audioURL) > UInt64(AudioFormatSpec.bytesPerSecond) else {
            throw TranscriptionError.noAudio
        }

        let reader = try PCMFileReader(url: session.audioURL)
        defer { reader.close() }
        let windows = reader.windows(seconds: limits.transcriptionWindowSeconds,
                                     overlap: limits.transcriptionOverlapSeconds)
        guard !windows.isEmpty else { throw TranscriptionError.noAudio }

        var utterances: [Utterance] = []
        var recognizedSeconds: TimeInterval = 0
        var completed = 0

        for window in windows {
            // Antes de cada ventana se comprueba el margen de memoria; si el
            // sistema esta apretando, se espera en vez de encadenar reservas.
            await MainActor.run { MemoryGovernor.shared.sample() }
            if await MainActor.run(body: { MemoryGovernor.shared.shouldThrottle }) {
                try? await Task.sleep(nanoseconds: 500_000_000)
            }

            let segments = try await recognize(reader: reader,
                                               window: window,
                                               recognizer: recognizer,
                                               onDevice: onDevice,
                                               chunkBytes: limits.audioReadChunkBytes)

            for segment in segments {
                let start = window.start + segment.timestamp
                let end = start + segment.duration
                // El solapamiento entre ventanas puede repetir palabras; se
                // descarta lo que ya cubrio la ventana anterior.
                if let last = utterances.last, start < last.end - 0.15 { continue }
                guard !segment.substring.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
                utterances.append(Utterance(start: start,
                                            end: end,
                                            text: segment.substring,
                                            confidence: segment.confidence))
                recognizedSeconds += max(0, end - start)
            }

            completed += 1
            progress(Progress(completedWindows: completed, totalWindows: windows.count))
            try Task.checkCancellation()
        }

        let merged = Self.mergeIntoUtterances(utterances)
        let totalDuration = max(session.duration, reader.duration)

        return Transcript(sessionID: session.id,
                          localeIdentifier: localeIdentifier,
                          generatedAt: Date(),
                          engine: onDevice ? "Apple Speech (en el dispositivo)" : "Apple Speech (servidor)",
                          utterances: merged,
                          coverage: totalDuration > 0 ? min(1, recognizedSeconds / totalDuration) : 0)
    }

    // MARK: - Reconocimiento de una ventana

    private func recognize(reader: PCMFileReader,
                           window: PCMFileReader.Window,
                           recognizer: SFSpeechRecognizer,
                           onDevice: Bool,
                           chunkBytes: Int) async throws -> [SFTranscriptionSegment] {

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = false
        request.requiresOnDeviceRecognition = onDevice
        request.taskHint = .dictation
        if #available(iOS 16.0, *) { request.addsPunctuation = true }

        return try await withCheckedThrowingContinuation { continuation in
            let box = ContinuationBox(continuation)
            let task = recognizer.recognitionTask(with: request) { result, error in
                if error != nil {
                    // Una ventana sin voz devuelve error; no es motivo para
                    // abortar la transcripcion entera.
                    box.resumeOnce(with: .success([]))
                    return
                }
                guard let result, result.isFinal else { return }
                box.resumeOnce(with: .success(result.bestTranscription.segments))
            }

            do {
                try reader.readFloatBuffers(range: window.byteRange, chunkBytes: chunkBytes) { buffer in
                    request.append(buffer)
                }
                request.endAudio()
            } catch {
                task.cancel()
                box.resumeOnce(with: .failure(error))
                return
            }

            // Red de seguridad: si el reconocedor se queda mudo, no bloqueamos
            // la cadena entera.
            DispatchQueue.global().asyncAfter(deadline: .now() + window.duration + 25) {
                if box.resumeOnce(with: .success([])) { task.cancel() }
            }
        }
    }

    /// Une segmentos contiguos en frases legibles. Sin esto el informe seria
    /// una lista de palabras sueltas.
    private static func mergeIntoUtterances(_ segments: [Utterance]) -> [Utterance] {
        let sorted = segments.sorted { $0.start < $1.start }
        var result: [Utterance] = []

        for segment in sorted {
            guard var last = result.last,
                  segment.start - last.end < 0.8,
                  last.text.count < 600,
                  !last.text.hasSuffix(".") || last.text.count < 120
            else {
                result.append(segment)
                continue
            }
            last.text += segment.text.hasPrefix(" ") ? segment.text : " " + segment.text
            last.end = segment.end
            last.confidence = (last.confidence + segment.confidence) / 2
            result[result.count - 1] = last
        }
        return result
    }
}

/// Garantiza que una continuacion se reanuda exactamente una vez, aunque el
/// reconocedor entregue resultado y error, o el temporizador de seguridad se
/// dispare a la vez.
private final class ContinuationBox: @unchecked Sendable {
    private var continuation: CheckedContinuation<[SFTranscriptionSegment], Error>?
    private let lock = NSLock()

    init(_ continuation: CheckedContinuation<[SFTranscriptionSegment], Error>) {
        self.continuation = continuation
    }

    @discardableResult
    func resumeOnce(with result: Result<[SFTranscriptionSegment], Error>) -> Bool {
        lock.lock()
        guard let continuation else {
            lock.unlock()
            return false
        }
        self.continuation = nil
        lock.unlock()
        continuation.resume(with: result)
        return true
    }
}
