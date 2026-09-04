import Foundation
import Combine

/// Preferencias del usuario. Viven en el App Group para que la extension pueda
/// leer las que le afectan.
@MainActor
final class AppSettings: ObservableObject {

    static let shared = AppSettings()

    enum AnalysisEngineKind: String, Codable, CaseIterable, Identifiable {
        case onDevice
        case claude

        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .onDevice: return "En el dispositivo"
            case .claude: return "Claude (nube)"
            }
        }

        var explanation: String {
            switch self {
            case .onDevice:
                return "Todo el análisis se hace en el aparato. Nada sale del dispositivo. Resúmenes extractivos y detección por patrones."
            case .claude:
                return "El texto de la transcripción se envía a la API de Anthropic para un análisis mucho más rico. Requiere clave propia y conexión."
            }
        }
    }

    private let defaults = AppGroup.defaults

    @Published var engine: AnalysisEngineKind {
        didSet { defaults.set(engine.rawValue, forKey: Keys.engine) }
    }

    @Published var forceOnDeviceRecognition: Bool {
        didSet { defaults.set(forceOnDeviceRecognition, forKey: Keys.onDeviceRecognition) }
    }

    @Published var localeIdentifier: String {
        didSet { defaults.set(localeIdentifier, forKey: Keys.locale) }
    }

    @Published var includeTranscriptInReport: Bool {
        didSet { defaults.set(includeTranscriptInReport, forKey: Keys.includeTranscript) }
    }

    @Published var organizationName: String {
        didSet { defaults.set(organizationName, forKey: Keys.organization) }
    }

    /// Recorte manual sobre el maximo que permite el aparato, en minutos.
    @Published var userSessionMinuteCap: Int {
        didSet { defaults.set(userSessionMinuteCap, forKey: Keys.sessionCap) }
    }

    private enum Keys {
        static let engine = "analysis.engine"
        static let onDeviceRecognition = "speech.onDeviceOnly"
        static let locale = "speech.locale"
        static let includeTranscript = "report.includeTranscript"
        static let organization = "report.organization"
        static let sessionCap = "capture.sessionCapMinutes"
    }

    static let supportedLocales: [(id: String, name: String)] = [
        ("es-ES", "Español (España)"),
        ("es-MX", "Español (México)"),
        ("es-419", "Español (Latinoamérica)"),
        ("en-US", "Inglés (EE. UU.)"),
        ("en-GB", "Inglés (Reino Unido)"),
        ("pt-BR", "Portugués (Brasil)"),
        ("fr-FR", "Francés"),
        ("it-IT", "Italiano"),
        ("de-DE", "Alemán")
    ]

    private init() {
        let defaults = AppGroup.defaults
        engine = AnalysisEngineKind(rawValue: defaults.string(forKey: Keys.engine) ?? "") ?? .onDevice
        forceOnDeviceRecognition = (defaults.object(forKey: Keys.onDeviceRecognition) as? Bool) ?? true
        localeIdentifier = defaults.string(forKey: Keys.locale) ?? "es-ES"
        includeTranscriptInReport = (defaults.object(forKey: Keys.includeTranscript) as? Bool) ?? true
        organizationName = defaults.string(forKey: Keys.organization) ?? ""
        userSessionMinuteCap = (defaults.object(forKey: Keys.sessionCap) as? Int) ?? 0
    }

    /// Duracion efectiva: el minimo entre lo que aguanta el aparato y lo que
    /// haya pedido el usuario.
    func effectiveSessionSeconds(limits: ResourceLimits) -> TimeInterval {
        guard userSessionMinuteCap > 0 else { return limits.maxSessionSeconds }
        return min(limits.maxSessionSeconds, TimeInterval(userSessionMinuteCap) * 60)
    }
}
