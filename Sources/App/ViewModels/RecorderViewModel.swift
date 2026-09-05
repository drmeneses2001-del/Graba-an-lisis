import Foundation
import Combine
import SwiftUI

/// Estado de la pantalla de grabación. Sigue la difusión del sistema, que es
/// la única vía de captura de la app: lo que suena por la salida de audio del
/// dispositivo.
@MainActor
final class RecorderViewModel: ObservableObject {

    static let broadcastExtensionBundleID = "com.grabaanalisis.app.broadcast"

    @Published private(set) var broadcastHandoff: CaptureHandoff?
    @Published private(set) var lastSession: RecordingSession?

    private var handoffTimer: Timer?

    init() {
        startWatchingHandoff()
    }

    var isBroadcasting: Bool {
        guard let handoff = broadcastHandoff, !handoff.isFinished else { return false }
        return Date().timeIntervalSince(handoff.updatedAt) < 6
    }

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
