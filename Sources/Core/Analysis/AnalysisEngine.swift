import Foundation

/// Contrato comun de los dos motores de análisis.
protocol AnalysisEngine {
    var displayName: String { get }
    /// `true` si el texto sale del dispositivo.
    var sendsDataOffDevice: Bool { get }

    func analyze(transcript: Transcript,
                 session: RecordingSession,
                 limits: ResourceLimits,
                 progress: @escaping @Sendable (Double, String) -> Void) async throws -> AnalysisReport
}
