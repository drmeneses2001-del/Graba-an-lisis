import XCTest
import PDFKit
@testable import GrabaAnalisis

final class PDFReportRendererTests: XCTestCase {

    func testRendersMultiPagePDFWithCorrectPageCount() throws {
        let session = RecordingSession(title: "Sesión de prueba para el PDF",
                                       duration: 1800,
                                       source: .microphone,
                                       tracks: [.local],
                                       stage: .analyzed)
        var report = AnalysisReport.empty(sessionID: session.id, title: session.title)
        report.subtitle = "Presupuesto · Migración · Calendario"
        report.executiveSummary = Array(repeating: "Frase de relleno para comprobar que el texto fluye entre páginas sin cortar palabras.", count: 40).joined(separator: " ")
        report.keyPoints = (1...6).map { "Punto clave número \($0)." }
        report.participation = [
            SpeakerStat(speaker: "Interlocutor remoto", seconds: 1000, words: 2500, turns: 40, share: 0.55, averageSentiment: 0.1),
            SpeakerStat(speaker: "Participante local", seconds: 800, words: 1900, turns: 35, share: 0.45, averageSentiment: -0.05)
        ]
        report.topics = (1...6).map { Topic(name: "Tema \($0)", summary: "Resumen del tema \($0).", weight: 1.0 / Double($0), mentions: 10 - $0, keywords: [], firstMention: Double($0) * 100) }
        report.commitments = (1...30).map {
            Commitment(statement: "Compromiso \($0) con una descripción algo larga para forzar el ajuste de línea dentro de la celda.",
                       owner: $0 % 2 == 0 ? "Ana" : "Luis",
                       dueDescription: "viernes",
                       dueDate: Date(),
                       status: CommitmentStatus.allCases[$0 % 4],
                       timestamp: Double($0) * 50,
                       verifiable: true)
        }
        report.risks = [
            Risk(statement: "Ventana de mantenimiento del proveedor", likelihood: .high, impact: .critical, mitigation: "Plan B", timestamp: 120),
            Risk(statement: "Falta de personal en agosto", likelihood: .medium, impact: .high, mitigation: "", timestamp: 400)
        ]
        report.sentimentSeries = (0..<20).map { SentimentPoint(timestamp: Double($0) * 90, score: sin(Double($0) / 3)) }
        report.timeline = report.commitments.prefix(10).map { TimelineEvent(timestamp: $0.timestamp, kind: .commitment, label: $0.statement) }
        report.metrics.durationSeconds = 1800
        report.metrics.wordCount = 4400
        report.provenance.engine = "Prueba"

        let url = FileManager.default.temporaryDirectory.appendingPathComponent("informe-prueba.pdf")
        try? FileManager.default.removeItem(at: url)

        let input = PDFReportRenderer.Input(session: session,
                                            report: report,
                                            transcript: nil,
                                            includeTranscript: false,
                                            organization: "Pruebas",
                                            limits: ResourceLimits.baseline(for: .compact))
        try PDFReportRenderer().render(input, to: url)

        let document = try XCTUnwrap(PDFDocument(url: url))
        XCTAssertGreaterThan(document.pageCount, 4)

        // La última página debe declarar el total correcto, prueba de que la
        // pasada en seco y la real coinciden.
        let lastPage = try XCTUnwrap(document.page(at: document.pageCount - 1))
        let text = lastPage.string ?? ""
        XCTAssertTrue(text.contains("Página \(document.pageCount) de \(document.pageCount)"), text)

        XCTAssertEqual(document.documentAttributes?[PDFDocumentAttribute.titleAttribute] as? String, session.title)
    }
}
