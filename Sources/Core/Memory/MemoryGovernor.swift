import Foundation
import Combine
import os

/// Punto unico donde se decide cuanta memoria puede gastar la app.
///
/// Publica la huella actual, el techo estimado del proceso y unos limites que
/// el resto de subsistemas consultan antes de reservar nada. Cuando el sistema
/// avisa de presion, degrada esos limites y avisa a quien este trabajando para
/// que suelte cachés y baje el ritmo.
@MainActor
final class MemoryGovernor: ObservableObject {

    static let shared = MemoryGovernor()

    enum Pressure: String {
        case normal, warning, critical

        var displayName: String {
            switch self {
            case .normal: return "Normal"
            case .warning: return "Aviso"
            case .critical: return "Crítica"
            }
        }
    }

    @Published private(set) var footprintBytes: UInt64 = 0
    @Published private(set) var availableBytes: UInt64 = 0
    @Published private(set) var pressure: Pressure = .normal
    @Published private(set) var limits: ResourceLimits

    let deviceClass: DeviceClass
    private let baseline: ResourceLimits
    private var pressureSource: DispatchSourceMemoryPressure?
    private var timer: Timer?
    private let log = Logger(subsystem: "com.grabaanalisis.app", category: "memoria")

    /// Callbacks que se invocan cuando hay que soltar memoria ya.
    private var reliefHandlers: [UUID: () -> Void] = [:]

    private init() {
        let deviceClass = DeviceClass.current
        self.deviceClass = deviceClass
        self.baseline = ResourceLimits.baseline(for: deviceClass)
        self.limits = ResourceLimits.baseline(for: deviceClass)
        sample()
        installPressureSource()
        startSampling()
    }

    // MARK: - Muestreo

    private func startSampling() {
        let timer = Timer(timeInterval: 2.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.sample() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func sample() {
        footprintBytes = MemoryReporter.footprintBytes()
        availableBytes = MemoryReporter.availableBytes()
        reconcileLimits()
    }

    /// Techo del proceso: lo que ya gastamos mas lo que nos dejan gastar.
    var estimatedLimitBytes: UInt64 {
        availableBytes > 0 ? footprintBytes + availableBytes : MemoryReporter.physicalMemoryBytes / 2
    }

    /// Cuanto del presupuesto llevamos consumido, entre 0 y 1.
    var usedFraction: Double {
        let limit = estimatedLimitBytes
        guard limit > 0 else { return 0 }
        return min(1.0, Double(footprintBytes) / Double(limit))
    }

    /// Los limites de partida se recortan si el aparato viene ya justo de
    /// memoria (otras apps abiertas, dispositivo caliente, poco espacio).
    private func reconcileLimits() {
        var candidate = baseline

        if usedFraction > baseline.pressureThreshold || pressure != .normal {
            candidate = candidate.degraded()
        }

        // Un aparato con menos de 200 MB de margen no aguanta ventanas largas
        // de reconocimiento aunque sea un modelo grande.
        if availableBytes > 0 && availableBytes < 200 * 1_048_576 {
            candidate = candidate.degraded()
        }

        // El audio nunca puede ocupar mas de un tercio del disco libre.
        let freeDisk = MemoryReporter.freeDiskBytes()
        if freeDisk > 0 {
            candidate.maxAudioBytes = min(candidate.maxAudioBytes, freeDisk / 3)
            let secondsAllowedByDisk = Double(candidate.maxAudioBytes) / AudioFormatSpec.bytesPerSecondPerTrack / 2.0
            candidate.maxSessionSeconds = min(candidate.maxSessionSeconds, secondsAllowedByDisk)
        }

        if candidate != limits {
            limits = candidate
        }
    }

    // MARK: - Presion de memoria

    private func installPressureSource() {
        let source = DispatchSource.makeMemoryPressureSource(eventMask: [.warning, .critical], queue: .main)
        source.setEventHandler { [weak self] in
            guard let self else { return }
            let event = source.mask
            Task { @MainActor in
                self.handlePressure(critical: event.contains(.critical))
            }
        }
        source.resume()
        pressureSource = source
    }

    private func handlePressure(critical: Bool) {
        pressure = critical ? .critical : .warning
        log.warning("Presión de memoria \(self.pressure.rawValue, privacy: .public), huella \(self.footprintBytes)")
        limits = baseline.degraded()
        for handler in reliefHandlers.values { handler() }
        sample()

        // Se vuelve a normal sola si la huella baja.
        DispatchQueue.main.asyncAfter(deadline: .now() + 20) { [weak self] in
            guard let self else { return }
            if self.usedFraction < self.baseline.pressureThreshold {
                self.pressure = .normal
                self.reconcileLimits()
            }
        }
    }

    /// Registra un bloque que suelta memoria cuando el sistema aprieta.
    @discardableResult
    func onRelief(_ handler: @escaping () -> Void) -> UUID {
        let token = UUID()
        reliefHandlers[token] = handler
        return token
    }

    func removeRelief(_ token: UUID) {
        reliefHandlers.removeValue(forKey: token)
    }

    /// Consulta rapida antes de una fase cara: si estamos por encima del umbral
    /// conviene esperar o trocear mas.
    var shouldThrottle: Bool {
        pressure != .normal || usedFraction > limits.pressureThreshold
    }

    /// Espera activa y barata hasta que haya margen, con un tope para no
    /// bloquear la interfaz indefinidamente.
    func waitForHeadroom(timeout: TimeInterval = 8) async {
        let deadline = Date().addingTimeInterval(timeout)
        while shouldThrottle && Date() < deadline {
            try? await Task.sleep(nanoseconds: 400_000_000)
            sample()
        }
    }
}
