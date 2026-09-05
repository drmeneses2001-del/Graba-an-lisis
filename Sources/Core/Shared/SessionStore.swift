import Foundation
import Combine

/// Almacen de sesiones en ficheros. No hay base de datos a proposito: los
/// manifiestos son diminutos y todo lo pesado (audio, transcripcion, PDF) se
/// lee por trozos desde disco, nunca entero en memoria.
@MainActor
final class SessionStore: ObservableObject {

    static let shared = SessionStore()

    @Published private(set) var sessions: [RecordingSession] = []

    private init() {
        AppGroup.prepareDirectories()
        reload()
    }

    func reload() {
        let fileManager = FileManager.default
        let directories = (try? fileManager.contentsOfDirectory(at: AppGroup.sessionsURL,
                                                                includingPropertiesForKeys: nil)) ?? []
        var loaded: [RecordingSession] = []
        for directory in directories {
            let manifest = directory.appendingPathComponent("session.json")
            guard let data = try? Data(contentsOf: manifest),
                  let session = try? JSONDecoder.grabaAnalisis.decode(RecordingSession.self, from: data)
            else { continue }
            loaded.append(session)
        }
        sessions = loaded.sorted { $0.createdAt > $1.createdAt }
    }

    func save(_ session: RecordingSession) {
        try? FileManager.default.createDirectory(at: session.directoryURL, withIntermediateDirectories: true)
        guard let data = try? JSONEncoder.grabaAnalisis.encode(session) else { return }
        try? data.write(to: session.manifestURL, options: .atomic)
        if let index = sessions.firstIndex(where: { $0.id == session.id }) {
            sessions[index] = session
        } else {
            sessions.insert(session, at: 0)
            sessions.sort { $0.createdAt > $1.createdAt }
        }
    }

    func session(id: UUID) -> RecordingSession? {
        sessions.first { $0.id == id }
    }

    func delete(_ session: RecordingSession) {
        try? FileManager.default.removeItem(at: session.directoryURL)
        sessions.removeAll { $0.id == session.id }
    }

    func deleteAll() {
        for session in sessions { try? FileManager.default.removeItem(at: session.directoryURL) }
        sessions.removeAll()
        CaptureHandoff.clear()
    }

    /// Adopta una sesion que dejo la extension de difusion. Se llama al volver
    /// a primer plano.
    @discardableResult
    func adoptBroadcastSessionIfNeeded() -> RecordingSession? {
        guard let handoff = CaptureHandoff.load() else { return nil }
        reload()
        guard var session = session(id: handoff.sessionID) else { return nil }
        guard handoff.isFinished else { return session }

        session.duration = handoff.seconds
        session.audioBytes = handoff.bytes
        session.truncationReason = handoff.stopReason
        if session.stage == .recording { session.stage = .captured }
        // Audio insuficiente: la app de origen pudo proteger su sonido con
        // DRM, o la difusion se detuvo casi al instante.
        if session.audioBytes < UInt64(AudioFormatSpec.bytesPerSecond) && session.truncationReason == nil {
            session.truncationReason = "La difusión no capturó audio utilizable. Algunas apps protegen su sonido con DRM."
        }
        save(session)
        CaptureHandoff.clear()
        return session
    }

    func diskUsage() -> UInt64 {
        sessions.reduce(0) { $0 + $1.audioBytes }
    }
}
