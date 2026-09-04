import Foundation

/// Contenedor compartido entre la app y la extension de ReplayKit.
///
/// La extension escribe el audio aqui mientras graba; la app lo lee cuando
/// termina la difusion. Es el unico punto de contacto entre los dos procesos,
/// asi que todo lo que se guarda tiene que ser barato de escribir: PCM crudo y
/// un manifiesto JSON diminuto.
enum AppGroup {

    static let identifier = "group.com.grabaanalisis.shared"

    /// Raiz del contenedor compartido. Si el App Group no esta configurado
    /// (simulador sin entitlement, tests unitarios) cae a Application Support
    /// para que nada explote en desarrollo.
    static var containerURL: URL {
        if let url = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: identifier) {
            return url
        }
        let fallback = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("GrabaAnalisis", isDirectory: true)
        try? FileManager.default.createDirectory(at: fallback, withIntermediateDirectories: true)
        return fallback
    }

    /// Una carpeta por sesion: audio, transcripcion, analisis e informe.
    static var sessionsURL: URL {
        containerURL.appendingPathComponent("Sessions", isDirectory: true)
    }

    /// Buzon que la extension usa mientras graba, antes de que la app adopte
    /// la sesion.
    static var handoffURL: URL {
        containerURL.appendingPathComponent("Handoff", isDirectory: true)
    }

    static var defaults: UserDefaults {
        UserDefaults(suiteName: identifier) ?? .standard
    }

    static func prepareDirectories() {
        for url in [sessionsURL, handoffURL] {
            try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        }
    }

    static func directory(for sessionID: UUID) -> URL {
        sessionsURL.appendingPathComponent(sessionID.uuidString, isDirectory: true)
    }
}
