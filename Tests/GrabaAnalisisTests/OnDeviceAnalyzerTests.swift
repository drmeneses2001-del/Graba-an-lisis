import XCTest
@testable import GrabaAnalisis

final class OnDeviceAnalyzerTests: XCTestCase {

    private func makeTranscript() -> (RecordingSession, Transcript) {
        let session = RecordingSession(title: "Reunión de prueba",
                                       duration: 600,
                                       stage: .captured)
        let lines: [(Double, String)] = [
            (5, "Buenos días a todos. Hoy tenemos que cerrar el presupuesto del proyecto de migración."),
            (20, "Propongo que dividamos la migración en dos fases para reducir el riesgo del corte de servicio."),
            (40, "No estoy de acuerdo, el problema es que dos fases duplican el coste de pruebas y es un riesgo grave."),
            (60, "Me comprometo a preparar la estimación de costes de ambas opciones para el viernes."),
            (80, "Perfecto, entonces decidimos esperar a esa estimación antes de aprobar el presupuesto."),
            (100, "¿Quién se encarga de avisar al equipo de infraestructura sobre el calendario?"),
            (120, "El riesgo principal es que dependemos de la ventana de mantenimiento del proveedor y podría fallar.")
        ]
        let utterances = lines.map { start, text in
            Utterance(start: start, end: start + 8, text: text, confidence: 0.9)
        }
        let transcript = Transcript(sessionID: session.id,
                                    localeIdentifier: "es-ES",
                                    generatedAt: Date(),
                                    engine: "prueba",
                                    utterances: utterances,
                                    coverage: 0.4)
        return (session, transcript)
    }

    func testExtractsEachCategory() async throws {
        let (session, transcript) = makeTranscript()
        let report = try await OnDeviceAnalyzer().analyze(transcript: transcript,
                                                          session: session,
                                                          limits: ResourceLimits.baseline(for: .compact),
                                                          progress: { _, _ in })

        XCTAssertFalse(report.executiveSummary.isEmpty)
        XCTAssertFalse(report.proposals.isEmpty, "Debe detectar «propongo»")
        XCTAssertFalse(report.critiques.isEmpty, "Debe detectar «no estoy de acuerdo»")
        XCTAssertFalse(report.commitments.isEmpty, "Debe detectar «me comprometo»")
        XCTAssertFalse(report.decisions.isEmpty, "Debe detectar «decidimos»")
        XCTAssertFalse(report.risks.isEmpty, "Debe detectar «riesgo»")
        XCTAssertEqual(report.provenance.engine, OnDeviceAnalyzer().displayName)
    }

    func testRespectsCharacterBudget() async throws {
        let (session, transcript) = makeTranscript()
        var tight = ResourceLimits.baseline(for: .compact)
        tight.maxTranscriptCharsInMemory = 120
        let report = try await OnDeviceAnalyzer().analyze(transcript: transcript,
                                                          session: session,
                                                          limits: tight,
                                                          progress: { _, _ in })
        XCTAssertTrue(report.provenance.notes.contains("presupuesto de memoria"))
    }

    func testTranscriptChunkingNeverSplitsUtterances() {
        let (_, transcript) = makeTranscript()
        let chunks = transcript.chunks(maxChars: 200)
        XCTAssertGreaterThan(chunks.count, 1)
        for chunk in chunks {
            XCTAssertTrue(chunk.hasSuffix("\n"))
            XCTAssertLessThanOrEqual(chunk.count, 200 + 200)
        }
    }
}
