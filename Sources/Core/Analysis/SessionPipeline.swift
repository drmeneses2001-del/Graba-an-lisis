import Foundation
import Combine

/// Encadena transcripción, análisis e informe para una sesión.
///
/// Cada fase se ejecuta fuera del hilo principal, publica su progreso y respeta
/// los límites del gobernador de memoria. La cadena es reanudable: si ya existe
/// la transcripción no se vuelve a calcular, y lo mismo con el análisis.
@MainActor
final class SessionPipeline: ObservableObject {

    enum Phase: Equatable {
        case idle
        case transcribing(Double, String)
        case analyzing(Double, String)
        case rendering
        case finished
        case failed(String)

        var isRunning: Bool {
            switch self {
            case .transcribing, .analyzing, .rendering: return true
            default: return false
            }
        }

        var description: String {
            switch self {
            case .idle: return "Listo"
            case .transcribing(let fraction, let detail): return "Transcribiendo \(Int(fraction * 100)) % · \(detail)"
            case .analyzing(let fraction, let detail): return "Analizando \(Int(fraction * 100)) % · \(detail)"
            case .rendering: return "Componiendo el PDF"
            case .finished: return "Informe listo"
            case .failed(let message): return message
            }
        }

        var fraction: Double {
            switch self {
            case .idle: return 0
            case .transcribing(let value, _): return value * 0.5
            case .analyzing(let value, _): return 0.5 + value * 0.4
            case .rendering: return 0.95
            case .finished: return 1
            case .failed: return 0
            }
        }
    }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var transcript: Transcript?
    @Published private(set) var report: AnalysisReport?
    @Published private(set) var reportURL: URL?

    private var task: Task<Void, Never>?
    private let transcriber = SpeechTranscriptionService()

    func loadExisting(for session: RecordingSession) {
        if let data = try? Data(contentsOf: session.transcriptURL) {
            transcript = try? JSONDecoder.grabaAnalisis.decode(Transcript.self, from: data)
        }
        if let data = try? Data(contentsOf: session.analysisURL) {
            report = try? JSONDecoder.grabaAnalisis.decode(AnalysisReport.self, from: data)
        }
        if FileManager.default.fileExists(atPath: session.reportURL.path) {
            reportURL = session.reportURL
        }
        if report != nil { phase = .finished }
    }

    func cancel() {
        task?.cancel()
        task = nil
        phase = .idle
    }

    /// Ejecuta lo que falte: transcripción, análisis e informe.
    func run(session: RecordingSession, force: Bool = false) {
        guard task == nil else { return }
        let settings = AppSettings.shared
        let governor = MemoryGovernor.shared

        task = Task { [weak self] in
            guard let self else { return }
            do {
                var session = session
                let limits = governor.limits

                // 1. Transcripción
                var transcript = force ? nil : self.transcript
                if transcript == nil {
                    self.phase = .transcribing(0, "Preparando")
                    let service = self.transcriber
                    let localeIdentifier = settings.localeIdentifier
                    let onDevice = settings.forceOnDeviceRecognition
                    let result = try await service.transcribe(
                        session: session,
                        localeIdentifier: localeIdentifier,
                        forceOnDevice: onDevice,
                        limits: limits,
                        progress: { progress in
                            Task { @MainActor [weak self] in
                                self?.phase = .transcribing(progress.fraction,
                                                            "\(progress.completedWindows)/\(progress.totalWindows) tramos")
                            }
                        })
                    transcript = result
                    self.transcript = result
                    try Self.write(result, to: session.transcriptURL)
                    session.stage = .transcribed
                    SessionStore.shared.save(session)
                }
                guard let transcript, !transcript.isEmpty else {
                    throw SpeechTranscriptionService.TranscriptionError.noAudio
                }

                try Task.checkCancellation()
                await governor.waitForHeadroom()

                // 2. Análisis
                self.phase = .analyzing(0, "Preparando")
                let engine: AnalysisEngine = settings.engine == .claude && KeychainStore.hasAPIKey
                    ? ClaudeAnalyzer()
                    : OnDeviceAnalyzer()
                let analysis = try await engine.analyze(
                    transcript: transcript,
                    session: session,
                    limits: governor.limits,
                    progress: { fraction, detail in
                        Task { @MainActor [weak self] in
                            self?.phase = .analyzing(fraction, detail)
                        }
                    })
                self.report = analysis
                try Self.write(analysis, to: session.analysisURL)
                session.stage = .analyzed
                SessionStore.shared.save(session)

                try Task.checkCancellation()
                await governor.waitForHeadroom()

                // 3. Informe
                self.phase = .rendering
                let input = PDFReportRenderer.Input(session: session,
                                                    report: analysis,
                                                    transcript: transcript,
                                                    includeTranscript: settings.includeTranscriptInReport,
                                                    organization: settings.organizationName,
                                                    limits: governor.limits)
                let url = session.reportURL
                try await Task.detached(priority: .userInitiated) {
                    _ = try PDFReportRenderer().render(input, to: url)
                }.value

                self.reportURL = url
                session.stage = .reported
                SessionStore.shared.save(session)
                self.phase = .finished
            } catch is CancellationError {
                self.phase = .idle
            } catch {
                self.phase = .failed(error.localizedDescription)
                var session = session
                session.stage = .failed
                SessionStore.shared.save(session)
            }
            self.task = nil
        }
    }

    /// Rehace solo el PDF, por ejemplo tras cambiar si se incluye la
    /// transcripción como anexo.
    func regenerateReport(session: RecordingSession) {
        guard let report, task == nil else { return }
        let settings = AppSettings.shared
        let limits = MemoryGovernor.shared.limits
        let transcript = self.transcript

        task = Task { [weak self] in
            guard let self else { return }
            self.phase = .rendering
            do {
                let input = PDFReportRenderer.Input(session: session,
                                                    report: report,
                                                    transcript: transcript,
                                                    includeTranscript: settings.includeTranscriptInReport,
                                                    organization: settings.organizationName,
                                                    limits: limits)
                let url = session.reportURL
                try await Task.detached(priority: .userInitiated) {
                    _ = try PDFReportRenderer().render(input, to: url)
                }.value
                self.reportURL = url
                self.phase = .finished
            } catch {
                self.phase = .failed(error.localizedDescription)
            }
            self.task = nil
        }
    }

    private static func write<T: Encodable>(_ value: T, to url: URL) throws {
        let data = try JSONEncoder.grabaAnalisis.encode(value)
        try data.write(to: url, options: .atomic)
    }
}
