import UIKit

/// Traduce el análisis a la secuencia de bloques que se imprime.
///
/// Cada sección decide aquí qué merece una gráfica y qué merece una tabla: las
/// magnitudes comparadas van en barras, la composición por estado en apiladas,
/// la evolución en línea, y todo lo que es texto con estructura va en tabla.
/// Una sección sin datos no se emite: un informe con apartados vacíos es peor
/// que uno corto.
enum ReportComposer {

    struct Section {
        let title: String
        let blocks: [ReportBlock]
    }

    static func sections(report: AnalysisReport,
                         session: RecordingSession,
                         transcript: Transcript?,
                         includeTranscript: Bool,
                         limits: ResourceLimits) -> [Section] {
        var sections: [Section] = []

        sections.append(summarySection(report: report, session: session))

        if !report.participation.isEmpty || !report.topics.isEmpty {
            sections.append(overviewSection(report: report))
        }
        if !report.topics.isEmpty {
            sections.append(topicsSection(report: report, limits: limits))
        }
        if !report.proposals.isEmpty {
            sections.append(proposalsSection(report: report, limits: limits))
        }
        if !report.critiques.isEmpty {
            sections.append(critiquesSection(report: report, limits: limits))
        }
        if !report.decisions.isEmpty {
            sections.append(decisionsSection(report: report, limits: limits))
        }
        if !report.commitments.isEmpty {
            sections.append(commitmentsSection(report: report, limits: limits))
        }
        if !report.risks.isEmpty {
            sections.append(risksSection(report: report, limits: limits))
        }
        if !report.openQuestions.isEmpty || !report.nextSteps.isEmpty {
            sections.append(pendingSection(report: report))
        }
        if !report.timeline.isEmpty {
            sections.append(timelineSection(report: report, session: session, limits: limits))
        }
        if !report.quotes.isEmpty || !report.glossary.isEmpty {
            sections.append(appendixSection(report: report, limits: limits))
        }
        if includeTranscript, let transcript, !transcript.isEmpty {
            sections.append(transcriptSection(transcript: transcript, limits: limits))
        }
        sections.append(methodSection(report: report, session: session, transcript: transcript))

        return sections
    }

    // MARK: - Secciones

    private static func summarySection(report: AnalysisReport, session: RecordingSession) -> Section {
        var blocks: [ReportBlock] = []

        let metrics = report.metrics
        blocks.append(.metricTiles([
            MetricTile(value: formatDuration(metrics.durationSeconds),
                       label: "Duración",
                       footnote: session.source.displayName),
            MetricTile(value: "\(metrics.wordCount)",
                       label: "Palabras transcritas",
                       footnote: String(format: "%.0f por minuto", metrics.wordsPerMinute)),
            MetricTile(value: "\(report.commitments.count)",
                       label: "Compromisos",
                       footnote: String(format: "%.1f por hora", metrics.actionDensity)),
            MetricTile(value: "\(report.decisions.count)",
                       label: "Decisiones",
                       footnote: "\(report.proposals.count) propuestas")
        ]))
        blocks.append(.spacer(10))

        if !report.executiveSummary.isEmpty {
            for paragraph in report.executiveSummary.components(separatedBy: "\n\n") where !paragraph.isEmpty {
                blocks.append(.paragraph(paragraph))
            }
        }
        if !report.keyPoints.isEmpty {
            blocks.append(.subheading("Lo que hay que retener"))
            blocks.append(.bullets(report.keyPoints))
        }

        let indexPercent = Int(metrics.agreementIndex * 100)
        blocks.append(.callout(
            title: "Clima de la sesión",
            body: "Índice de acuerdo \(indexPercent) % (proporción de manifestaciones de acuerdo frente a objeciones). "
                + "Sentimiento medio \(String(format: "%.2f", metrics.overallSentiment)) en una escala de −1 a +1. "
                + "\(metrics.questionCount) preguntas formuladas. "
                + "Cobertura de habla reconocida: \(Int(metrics.speakingCoverage * 100)) % del audio.",
            color: PDFTheme.series[0]))

        return Section(title: "Resumen ejecutivo", blocks: blocks)
    }

    private static func overviewSection(report: AnalysisReport) -> Section {
        var blocks: [ReportBlock] = []

        if !report.participation.isEmpty {
            let items = report.participation.map { stat in
                (label: stat.speaker,
                 value: stat.seconds,
                 valueLabel: "\(Int(stat.share * 100)) %")
            }
            blocks.append(.chart(.horizontalBars(
                title: "Reparto del tiempo hablado",
                subtitle: "Segundos de habla por interlocutor, con su porcentaje sobre el total",
                items: items,
                useSequentialRamp: false)))
            blocks.append(.caption("Las pistas se separan en el momento de grabar: lo que sonó por la salida de audio y lo que entró por el micrófono se transcriben por separado."))
            blocks.append(.spacer(12))

            blocks.append(.table(TableSpec(
                title: "Detalle por interlocutor",
                columns: [TableColumn(title: "Interlocutor", widthFraction: 0.34),
                          TableColumn(title: "Tiempo", widthFraction: 0.16, alignment: .right),
                          TableColumn(title: "Turnos", widthFraction: 0.14, alignment: .right),
                          TableColumn(title: "Palabras", widthFraction: 0.18, alignment: .right),
                          TableColumn(title: "Tono medio", widthFraction: 0.18, alignment: .right)],
                rows: report.participation.map { stat in
                    [TableCell(stat.speaker),
                     TableCell(formatDuration(stat.seconds)),
                     TableCell("\(stat.turns)"),
                     TableCell("\(stat.words)"),
                     TableCell(String(format: "%+.2f", stat.averageSentiment))]
                },
                note: nil)))
        }

        if report.sentimentSeries.count > 2 {
            blocks.append(.spacer(14))
            blocks.append(.chart(.line(
                title: "Evolución del tono a lo largo de la sesión",
                subtitle: "Media de sentimiento por tramo, de −1 (tenso) a +1 (favorable)",
                points: report.sentimentSeries.map { (x: $0.timestamp, y: $0.score) },
                yRange: -1...1,
                xAxisLabel: "Tiempo desde el inicio",
                zeroBaseline: true)))
        }

        return Section(title: "Panorama de la sesión", blocks: blocks)
    }

    private static func topicsSection(report: AnalysisReport, limits: ResourceLimits) -> Section {
        var blocks: [ReportBlock] = []
        let topics = Array(report.topics.prefix(min(10, limits.maxTableRows)))

        blocks.append(.chart(.horizontalBars(
            title: "Peso relativo de cada tema",
            subtitle: "Proporción de la conversación dedicada a cada asunto",
            items: topics.map { (label: $0.name,
                                 value: $0.weight,
                                 valueLabel: "\(Int($0.weight * 100)) %") },
            useSequentialRamp: true)))
        blocks.append(.spacer(12))

        blocks.append(.table(TableSpec(
            title: "Temas tratados",
            columns: [TableColumn(title: "Tema", widthFraction: 0.20),
                      TableColumn(title: "De qué se habló", widthFraction: 0.52),
                      TableColumn(title: "Menciones", widthFraction: 0.13, alignment: .right),
                      TableColumn(title: "Primera vez", widthFraction: 0.15, alignment: .right)],
            rows: topics.map { topic in
                [TableCell(topic.name),
                 TableCell(topic.summary),
                 TableCell("\(topic.mentions)"),
                 TableCell(Transcript.timestamp(topic.firstMention))]
            },
            note: nil)))

        return Section(title: "Temas tratados", blocks: blocks)
    }

    private static func proposalsSection(report: AnalysisReport, limits: ResourceLimits) -> Section {
        var blocks: [ReportBlock] = []
        let proposals = Array(report.proposals.prefix(limits.maxTableRows))

        blocks.append(.lead("Se recogen las propuestas planteadas durante la sesión, con quién las planteó y el esfuerzo que aparenta cada una según lo que se dijo. Una propuesta no es una decisión: aquí solo está lo que se puso sobre la mesa."))

        let byEffort = Effort.allCases.map { effort in
            (label: effort.displayName,
             value: Double(proposals.filter { $0.effort == effort }.count),
             valueLabel: "\(proposals.filter { $0.effort == effort }.count)")
        }.filter { $0.value > 0 }
        if byEffort.count > 1 {
            blocks.append(.chart(.horizontalBars(
                title: "Propuestas por esfuerzo estimado",
                subtitle: "Recuento según los indicios de coste mencionados en la conversación",
                items: byEffort,
                useSequentialRamp: true)))
            blocks.append(.spacer(12))
        }

        blocks.append(.table(TableSpec(
            title: "Propuestas",
            columns: [TableColumn(title: "Momento", widthFraction: 0.10),
                      TableColumn(title: "Propuesta", widthFraction: 0.46),
                      TableColumn(title: "Quién", widthFraction: 0.20),
                      TableColumn(title: "Impacto esperado", widthFraction: 0.14),
                      TableColumn(title: "Esfuerzo", widthFraction: 0.10, alignment: .right)],
            rows: proposals.map { proposal in
                [TableCell(Transcript.timestamp(proposal.timestamp)),
                 TableCell(proposal.statement),
                 TableCell(proposal.proposedBy),
                 TableCell(proposal.expectedImpact.isEmpty ? "—" : proposal.expectedImpact),
                 TableCell(proposal.effort.displayName)]
            },
            note: nil)))

        return Section(title: "Propuestas", blocks: blocks)
    }

    private static func critiquesSection(report: AnalysisReport, limits: ResourceLimits) -> Section {
        var blocks: [ReportBlock] = []
        let critiques = Array(report.critiques.prefix(limits.maxTableRows))

        blocks.append(.lead("Objeciones, reservas y problemas señalados. La gravedad se estima por la intensidad del lenguaje y por si la objeción venía acompañada de un riesgo concreto."))

        let severities = Severity.allCases.filter { severity in
            critiques.contains { $0.severity == severity }
        }
        if severities.count > 1 {
            blocks.append(.chart(.stackedBars(
                title: "Críticas por gravedad",
                subtitle: "Recuento por nivel; cada nivel lleva su nombre escrito además del color",
                categories: [(label: "Críticas",
                              segments: severities.map { severity in
                                  (name: severity.displayName,
                                   value: Double(critiques.filter { $0.severity == severity }.count),
                                   color: PDFTheme.color(for: severity))
                              })])))
            blocks.append(.spacer(12))
        }

        blocks.append(.table(TableSpec(
            title: "Críticas y objeciones",
            columns: [TableColumn(title: "Momento", widthFraction: 0.10),
                      TableColumn(title: "Objeción", widthFraction: 0.44),
                      TableColumn(title: "Quién", widthFraction: 0.16),
                      TableColumn(title: "Sobre qué", widthFraction: 0.16),
                      TableColumn(title: "Gravedad", widthFraction: 0.14)],
            rows: critiques.map { critique in
                [TableCell(Transcript.timestamp(critique.timestamp)),
                 TableCell(critique.statement),
                 TableCell(critique.raisedBy),
                 TableCell(critique.target.isEmpty ? "—" : critique.target),
                 TableCell(critique.severity.displayName, dotColor: PDFTheme.color(for: critique.severity))]
            },
            note: "Las contrapropuestas registradas aparecen en la sección de propuestas.")))

        return Section(title: "Críticas y objeciones", blocks: blocks)
    }

    private static func decisionsSection(report: AnalysisReport, limits: ResourceLimits) -> Section {
        let decisions = Array(report.decisions.prefix(limits.maxTableRows))
        return Section(title: "Decisiones", blocks: [
            .lead("Puntos que quedaron cerrados durante la sesión. Si una decisión no lleva motivo escrito es porque no se explicitó en la conversación."),
            .table(TableSpec(
                title: "Decisiones tomadas",
                columns: [TableColumn(title: "Momento", widthFraction: 0.10),
                          TableColumn(title: "Decisión", widthFraction: 0.44),
                          TableColumn(title: "Quién la cierra", widthFraction: 0.18),
                          TableColumn(title: "Motivo", widthFraction: 0.28)],
                rows: decisions.map { decision in
                    [TableCell(Transcript.timestamp(decision.timestamp)),
                     TableCell(decision.statement),
                     TableCell(decision.madeBy),
                     TableCell(decision.rationale.isEmpty ? "No se explicitó" : decision.rationale)]
                },
                note: nil))
        ])
    }

    private static func commitmentsSection(report: AnalysisReport, limits: ResourceLimits) -> Section {
        var blocks: [ReportBlock] = []
        let commitments = Array(report.commitments.prefix(limits.maxTableRows))

        blocks.append(.lead("Tareas que alguien asumió. Un compromiso es verificable cuando tiene responsable y fecha; los que no lo son aparecen marcados, porque son los que se pierden."))

        var byOwner: [String: [CommitmentStatus: Int]] = [:]
        for commitment in commitments {
            byOwner[commitment.owner, default: [:]][commitment.status, default: 0] += 1
        }
        let categories = byOwner
            .sorted { $0.value.values.reduce(0, +) > $1.value.values.reduce(0, +) }
            .prefix(8)
            .map { owner, counts in
                (label: owner,
                 segments: CommitmentStatus.allCases.compactMap { status -> (name: String, value: Double, color: UIColor)? in
                     guard let count = counts[status], count > 0 else { return nil }
                     return (name: status.displayName, value: Double(count), color: PDFTheme.color(for: status))
                 })
            }
        if !categories.isEmpty {
            blocks.append(.chart(.stackedBars(
                title: "Compromisos por responsable y estado",
                subtitle: "Cada tramo lleva su recuento; los estados están además nombrados en la leyenda",
                categories: Array(categories))))
            blocks.append(.spacer(12))
        }

        blocks.append(.table(TableSpec(
            title: "Compromisos adquiridos",
            columns: [TableColumn(title: "Momento", widthFraction: 0.09),
                      TableColumn(title: "Compromiso", widthFraction: 0.42),
                      TableColumn(title: "Responsable", widthFraction: 0.17),
                      TableColumn(title: "Plazo", widthFraction: 0.17),
                      TableColumn(title: "Estado", widthFraction: 0.15)],
            rows: commitments.map { commitment in
                [TableCell(Transcript.timestamp(commitment.timestamp)),
                 TableCell(commitment.statement + (commitment.verifiable ? "" : "  (sin responsable o sin fecha)")),
                 TableCell(commitment.owner),
                 TableCell(commitment.dueDescription),
                 TableCell(commitment.status.displayName, dotColor: PDFTheme.color(for: commitment.status))]
            },
            note: "«En riesgo» marca los compromisos sobre los que se levantó una objeción en la misma sesión.")))

        return Section(title: "Compromisos", blocks: blocks)
    }

    private static func risksSection(report: AnalysisReport, limits: ResourceLimits) -> Section {
        var blocks: [ReportBlock] = []
        let risks = Array(report.risks.prefix(min(12, limits.maxTableRows)))

        blocks.append(.chart(.riskMatrix(
            title: "Matriz de riesgos",
            subtitle: "Posición de cada riesgo por probabilidad e impacto; el número remite a la tabla",
            risks: risks)))
        blocks.append(.spacer(10))

        blocks.append(.table(TableSpec(
            title: "Riesgos identificados",
            columns: [TableColumn(title: "Nº", widthFraction: 0.06, alignment: .right),
                      TableColumn(title: "Riesgo", widthFraction: 0.46),
                      TableColumn(title: "Probabilidad", widthFraction: 0.14),
                      TableColumn(title: "Impacto", widthFraction: 0.14),
                      TableColumn(title: "Mitigación", widthFraction: 0.20)],
            rows: risks.enumerated().map { index, risk in
                [TableCell("\(index + 1)"),
                 TableCell(risk.statement),
                 TableCell(risk.likelihood.displayName, dotColor: PDFTheme.color(for: risk.likelihood)),
                 TableCell(risk.impact.displayName, dotColor: PDFTheme.color(for: risk.impact)),
                 TableCell(risk.mitigation.isEmpty ? "No se propuso" : risk.mitigation)]
            },
            note: nil)))

        return Section(title: "Riesgos", blocks: blocks)
    }

    private static func pendingSection(report: AnalysisReport) -> Section {
        var blocks: [ReportBlock] = []
        if !report.nextSteps.isEmpty {
            blocks.append(.subheading("Próximos pasos"))
            blocks.append(.numbered(report.nextSteps))
        }
        if !report.openQuestions.isEmpty {
            blocks.append(.spacer(8))
            blocks.append(.subheading("Preguntas que quedaron sin respuesta"))
            blocks.append(.bullets(report.openQuestions))
        }
        return Section(title: "Pendiente", blocks: blocks)
    }

    private static func timelineSection(report: AnalysisReport,
                                        session: RecordingSession,
                                        limits: ResourceLimits) -> Section {
        let duration = max(report.metrics.durationSeconds, session.duration)
        var blocks: [ReportBlock] = [
            .chart(.timeline(title: "Cronología de la sesión",
                             subtitle: "Cuándo apareció cada tipo de aportación",
                             events: report.timeline,
                             duration: duration)),
            .spacer(12)
        ]
        blocks.append(.table(TableSpec(
            title: "Hitos",
            columns: [TableColumn(title: "Momento", widthFraction: 0.12),
                      TableColumn(title: "Tipo", widthFraction: 0.18),
                      TableColumn(title: "Qué ocurrió", widthFraction: 0.70)],
            rows: report.timeline.prefix(limits.maxTableRows).map { event in
                [TableCell(Transcript.timestamp(event.timestamp)),
                 TableCell(event.kind.displayName),
                 TableCell(event.label)]
            },
            note: nil)))
        return Section(title: "Cronología", blocks: blocks)
    }

    private static func appendixSection(report: AnalysisReport, limits: ResourceLimits) -> Section {
        var blocks: [ReportBlock] = []
        if !report.quotes.isEmpty {
            blocks.append(.subheading("Citas destacadas"))
            for quote in report.quotes.prefix(6) {
                blocks.append(.quote(text: quote.text,
                                     attribution: "\(quote.speaker) · \(Transcript.timestamp(quote.timestamp))"))
            }
        }
        if !report.glossary.isEmpty {
            blocks.append(.spacer(10))
            blocks.append(.table(TableSpec(
                title: "Términos recurrentes",
                columns: [TableColumn(title: "Término", widthFraction: 0.22),
                          TableColumn(title: "Cómo se usó en la sesión", widthFraction: 0.64),
                          TableColumn(title: "Veces", widthFraction: 0.14, alignment: .right)],
                rows: report.glossary.prefix(limits.maxTableRows).map { term in
                    [TableCell(term.term),
                     TableCell(term.definition),
                     TableCell("\(term.occurrences)")]
                },
                note: nil)))
        }
        return Section(title: "Citas y glosario", blocks: blocks)
    }

    private static func transcriptSection(transcript: Transcript, limits: ResourceLimits) -> Section {
        var blocks: [ReportBlock] = [
            .lead("Transcripción completa con marcas de tiempo, tal como la produjo el reconocedor de voz. Puede contener errores de reconocimiento; el análisis se hizo sobre este mismo texto.")
        ]
        // Se emite intervención a intervención para que el paginador pueda
        // cortar donde quiera sin construir el texto entero en memoria.
        for utterance in transcript.utterances.sorted(by: { $0.start < $1.start }) {
            blocks.append(.keyValues([("[\(Transcript.timestamp(utterance.start))] \(utterance.speaker)", utterance.text)]))
        }
        return Section(title: "Anexo: transcripción", blocks: blocks)
    }

    private static func methodSection(report: AnalysisReport,
                                      session: RecordingSession,
                                      transcript: Transcript?) -> Section {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "es_ES")
        formatter.dateStyle = .long
        formatter.timeStyle = .medium

        var rows: [[TableCell]] = [
            [TableCell("Origen del audio"), TableCell(session.source.displayName)],
            [TableCell("Pistas grabadas"), TableCell(session.tracks.map(\.speakerLabel).joined(separator: ", "))],
            [TableCell("Duración"), TableCell(formatDuration(session.duration))],
            [TableCell("Audio en disco"), TableCell(MemoryReporter.formatted(session.audioBytes))],
            [TableCell("Formato de audio"), TableCell("PCM 16 kHz mono, 16 bits")],
            [TableCell("Reconocedor de voz"), TableCell(transcript?.engine ?? "No transcrita")],
            [TableCell("Idioma"), TableCell(transcript?.localeIdentifier ?? session.localeIdentifier)],
            [TableCell("Motor de análisis"), TableCell(report.provenance.engine)],
            [TableCell("Modelo"), TableCell(report.provenance.model ?? "No aplica")],
            [TableCell("Bloques analizados"), TableCell("\(report.provenance.chunksProcessed)")],
            [TableCell("Palabras analizadas"), TableCell("\(report.provenance.transcriptWords)")],
            [TableCell("Informe generado"), TableCell(formatter.string(from: report.provenance.generatedAt))],
            [TableCell("Dispositivo"), TableCell("\(DeviceClass.current.displayName) · \(MemoryReporter.formatted(MemoryReporter.physicalMemoryBytes)) de RAM")]
        ]
        if let reason = session.truncationReason {
            rows.append([TableCell("Aviso de captura"), TableCell(reason)])
        }

        var blocks: [ReportBlock] = [
            .lead("Cómo se produjo este documento, para que cualquiera pueda juzgar hasta dónde llega su fiabilidad."),
            .table(TableSpec(title: "Trazabilidad",
                             columns: [TableColumn(title: "Concepto", widthFraction: 0.32),
                                       TableColumn(title: "Valor", widthFraction: 0.68)],
                             rows: rows,
                             note: nil))
        ]
        if !report.provenance.notes.isEmpty {
            blocks.append(.spacer(8))
            blocks.append(.callout(title: "Límites de este análisis",
                                   body: report.provenance.notes,
                                   color: PDFTheme.Status.warning))
        }
        blocks.append(.spacer(8))
        blocks.append(.caption("Los elementos extraídos proceden de la transcripción automática. Antes de usarlos para tomar decisiones, conviene contrastarlos con la grabación original, que permanece en el dispositivo."))
        return Section(title: "Metodología y trazabilidad", blocks: blocks)
    }

    // MARK: - Utilidades

    static func formatDuration(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded())
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let secs = total % 60
        if hours > 0 { return "\(hours) h \(minutes) min" }
        if minutes > 0 { return "\(minutes) min \(secs) s" }
        return "\(secs) s"
    }
}
