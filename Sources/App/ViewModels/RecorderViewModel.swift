import Foundation
import Combine
import SwiftUI

/// Estado de la pantalla de grabación. Une el grabador por micrófono, el
/// seguimiento de la difusión del sistema y el gobernador de memoria.
@MainActor
final class RecorderViewModel: ObservableObject {

    enum Mode: String, CaseIterable, Identifiable {
        case microphone
        case broadcast

        var id: String { rawValue }

        var title: String {
            switch self {
            case .microphone: return "Micrófono"
            case .broadcast: return "Todo el dispositivo"
            }
        }

        var explanation: String {
            switch self {
            case .microphone:
                return "Graba con el micrófono lo que suena en la sala y por el altavoz. Funciona con la app en segundo plano."
            case .broadcast:
                return "Captura el audio de las demás apps y el micrófono a la vez, en pistas separadas. Se inicia desde el botón del sistema y se detiene desde la barra roja o el Centro de control."
            }
        }
    }

    static let broadcastExtensionBundleID = "com.grabaanalisis.app.broadcast"

    @Published var mode: Mode = .microphone
    @Published var title: String = ""
    @Published var errorMessage: String?
    @Published private(set) var broadcastHandoff: CaptureHandoff?
    @Published private(set) var lastSession: RecordingSession?

    let microphone = MicrophoneCaptureController()
    private var handoffTimer: Timer?
    private var cancellables = Set<AnyCancellable>()

    init() {
        microphone.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
        startWatchingHandoff()
    }

    var isBroadcasting: Bool {
        guard let handoff = broadcastHandoff, !handoff.isFinished else { return false }
        return Date().timeIntervalSince(handoff.updatedAt) < 6
    }

    var suggestedTitle: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "es_ES")
        formatter.dateFormat = "EEEE d 'de' MMMM, HH:mm"
        return "Sesión del \(formatter.string(from: Date()))"
    }

    // MARK: - Micrófono

    func startMicrophone() {
        errorMessage = nil
        let governor = MemoryGovernor.shared
        let settings = AppSettings.shared
        let limits = governor.limits
        let maxSeconds = settings.effectiveSessionSeconds(limits: limits)
        let sessionTitle = title.trimmingCharacters(in: .whitespaces).isEmpty ? suggestedTitle : title

        Task {
            do {
                let session = try await microphone.start(title: sessionTitle,
                                                         limits: limits,
                                                         maxSeconds: maxSeconds)
                SessionStore.shared.save(session)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    func stopMicrophone() {
        guard let session = microphone.stop() else { return }
        SessionStore.shared.save(session)
        lastSession = session
        title = ""
    }

    // MARK: - Difusión

    private func startWatchingHandoff() {
        let timer = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.pollHandoff() }
        }
        RunLoop.main.add(timer, forMode: .common)
        handoffTimer = timer
        pollHandoff()
    }

    private func pollHandoff() {
        let handoff = CaptureHandoff.load()
        if let handoff, handoff.isFinished {
            if let session = SessionStore.shared.adoptBroadcastSessionIfNeeded() {
                lastSession = session
            }
            broadcastHandoff = nil
            return
        }
        broadcastHandoff = handoff
    }
}
