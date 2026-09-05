import Foundation

/// Motor de análisis en la nube.
///
/// La transcripción se trocea según los límites del aparato, cada trozo se
/// analiza por separado y un último paso consolida todo en un solo informe. Ese
/// reparto no es solo por el contexto del modelo: mantiene acotado el texto que
/// la app tiene en memoria a la vez.
///
/// Las cifras objetivas (participación, sentimiento, métricas) no se le piden
/// al modelo: se calculan aquí a partir del audio y de la transcripción, que es
/// más fiable y más barato.
struct ClaudeAnalyzer: AnalysisEngine {

    let displayName = "Análisis con Claude"
    let sendsDataOffDevice = true

    private let client = ClaudeClient()

    func analyze(transcript: Transcript,
                 session: RecordingSession,
                 limits: ResourceLimits,
                 progress: @escaping @Sendable (Double, String) -> Void) async throws -> AnalysisReport {

        let chunks = transcript.chunks(maxChars: limits.analysisChunkChars)
        guard !chunks.isEmpty else {
            throw ClaudeClient.ClientError.decoding("La transcripción está vacía.")
        }

        var partials: [ClaudePayload] = []
        partials.reserveCapacity(chunks.count)

        for (index, chunk) in chunks.enumerated() {
            await MainActor.run { MemoryGovernor.shared.sample() }
            progress(Double(index) / Double(chunks.count + 1),
                     "Analizando bloque \(index + 1) de \(chunks.count)")

            let response = try await client.complete(
                system: Self.systemPrompt,
                user: Self.chunkPrompt(chunk: chunk,
                                       index: index,
                                       total: chunks.count,
                                       session: session),
                jsonSchema: Self.schema,
                maxTokens: 24_000)
            partials.append(try Self.decode(response.text))
            try Task.checkCancellation()
        }

        progress(Double(chunks.count) / Double(chunks.count + 1), "Consolidando el informe")

        let merged: ClaudePayload
        var modelUsed = ClaudeClient.model
        if partials.count == 1 {
            merged = partials[0]
        } else {
            let consolidated = try await client.complete(
                system: Self.systemPrompt,
                user: Self.reducePrompt(partials: partials, session: session),
                jsonSchema: Self.schema,
                maxTokens: 32_000)
            modelUsed = consolidated.model
            merged = try Self.decode(consolidated.text)
        }

        // Lo medible se mide, no se pregunta.
        let sentimentScores = TranscriptStatistics.sentiment(for: transcript)
        let sentimentSeries = TranscriptStatistics.sentimentSeries(from: transcript,
                                                                   scores: sentimentScores,
                                                                   maxPoints: limits.maxChartPoints)
        var report = merged.toReport(session: session, limits: limits)
        report.sentimentSeries = sentimentSeries
        report.metrics = TranscriptStatistics.metrics(transcript: transcript,
                                                      session: session,
                                                      commitments: report.commitments,
                                                      critiques: report.critiques,
                                                      agreements: report.decisions.count + report.commitments.count,
                                                      sentiment: sentimentScores)
        report.provenance = AnalysisProvenance(
            engine: displayName,
            model: modelUsed,
            generatedAt: Date(),
            transcriptWords: transcript.wordCount,
            chunksProcessed: chunks.count,
            notes: "Las cifras de sentimiento y las métricas se calculan en el dispositivo a partir del audio; el texto analítico procede del modelo.")

        progress(1.0, "Análisis terminado")
        return report
    }

    // MARK: - Instrucciones

    private static let systemPrompt = """
    Eres un analista de reuniones. Recibes la transcripción, con marcas de tiempo, de todo el \
    audio que sonó por la salida de audio de un dispositivo mientras se grabó: puede ser una \
    llamada, una videollamada, un podcast o un vídeo. Es una sola pista continua, sin \
    diarización: no sabes cuántas personas hablan salvo que la propia transcripción lo deje claro \
    (alguien se presenta, lo nombran, dice su propio nombre).

    Reglas de trabajo:
    - No inventes. Cada elemento que extraigas tiene que estar sostenido por la transcripción.
    - Si un dato no aparece (responsable, fecha, motivo), deja el campo vacío en vez de suponerlo.
    - Solo atribuyas algo a una persona por su nombre si el texto lo identifica explícitamente. \
      Si no se puede saber quién lo dijo, deja el campo de responsable vacío: no inventes ni \
      «Hablante 1» ni etiquetas por el estilo.
    - Los tiempos van en segundos desde el inicio, deducidos de las marcas [mm:ss] o [h:mm:ss].
    - Distingue con cuidado: una propuesta es algo que alguien plantea hacer; una decisión es \
      algo que quedó cerrado; un compromiso es alguien asumiendo una tarea concreta.
    - Las críticas incluyen objeciones, reservas y problemas señalados, con su gravedad real, \
      sin suavizarlas y sin dramatizarlas.
    - Escribe en el mismo idioma que la transcripción.
    - El resumen ejecutivo debe poder leerse solo: dos o tres párrafos que expliquen de qué se \
      habló, a qué se llegó y qué queda pendiente.
    """

    private static func chunkPrompt(chunk: String,
                                    index: Int,
                                    total: Int,
                                    session: RecordingSession) -> String {
        """
        Sesión: «\(session.title)»
        Fecha: \(ISO8601DateFormatter().string(from: session.createdAt))
        Bloque \(index + 1) de \(total).

        Analiza este bloque y devuelve el JSON del esquema. Si el bloque no contiene \
        elementos de alguna categoría, devuelve la lista vacía.

        --- TRANSCRIPCIÓN ---
        \(chunk)
        --- FIN ---
        """
    }

    private static func reducePrompt(partials: [ClaudePayload], session: RecordingSession) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.withoutEscapingSlashes]
        let blocks = partials.enumerated().compactMap { index, payload -> String? in
            guard let data = try? encoder.encode(payload),
                  let text = String(data: data, encoding: .utf8) else { return nil }
            return "### Bloque \(index + 1)\n\(text)"
        }.joined(separator: "\n\n")

        return """
        Sesión: «\(session.title)»

        Estos son los análisis parciales de cada bloque de la misma sesión. Consolídalos en un \
        único informe siguiendo el esquema:
        - Funde los elementos duplicados o equivalentes en uno solo, conservando el tiempo del \
          primero en que aparecieron.
        - Ordena por tiempo dentro de cada lista.
        - Reescribe el resumen ejecutivo para la sesión completa, no como suma de resúmenes.
        - Los temas deben reflejar la sesión entera, con pesos que sumen aproximadamente 1.

        \(blocks)
        """
    }

    // MARK: - Esquema de salida

    private static var schema: [String: Any] {
        func array(_ properties: [String: Any], required: [String]) -> [String: Any] {
            ["type": "array",
             "items": ["type": "object",
                       "properties": properties,
                       "required": required,
                       "additionalProperties": false]]
        }
        let string: [String: Any] = ["type": "string"]
        let number: [String: Any] = ["type": "number"]
        let stringList: [String: Any] = ["type": "array", "items": string]

        return [
            "type": "object",
            "additionalProperties": false,
            "required": ["title", "subtitle", "executiveSummary", "keyPoints", "topics",
                         "proposals", "critiques", "commitments", "decisions", "risks",
                         "openQuestions", "nextSteps", "quotes", "glossary"],
            "properties": [
                "title": string,
                "subtitle": string,
                "executiveSummary": string,
                "keyPoints": stringList,
                "openQuestions": stringList,
                "nextSteps": stringList,
                "topics": array(["name": string,
                                 "summary": string,
                                 "weight": number,
                                 "mentions": ["type": "integer"],
                                 "keywords": stringList,
                                 "firstMention": number],
                                required: ["name", "summary", "weight", "mentions", "keywords", "firstMention"]),
                "proposals": array(["statement": string,
                                    "proposedBy": string,
                                    "rationale": string,
                                    "expectedImpact": string,
                                    "effort": ["type": "string", "enum": ["small", "medium", "large", "unknown"]],
                                    "timestamp": number],
                                   required: ["statement", "proposedBy", "rationale", "expectedImpact", "effort", "timestamp"]),
                "critiques": array(["statement": string,
                                    "target": string,
                                    "severity": ["type": "string", "enum": ["low", "medium", "high", "critical"]],
                                    "raisedBy": string,
                                    "counterpoint": string,
                                    "timestamp": number],
                                   required: ["statement", "target", "severity", "raisedBy", "counterpoint", "timestamp"]),
                "commitments": array(["statement": string,
                                      "owner": string,
                                      "dueDescription": string,
                                      "status": ["type": "string", "enum": ["agreed", "conditional", "pending", "atRisk"]],
                                      "timestamp": number],
                                     required: ["statement", "owner", "dueDescription", "status", "timestamp"]),
                "decisions": array(["statement": string,
                                    "madeBy": string,
                                    "rationale": string,
                                    "alternativesConsidered": stringList,
                                    "timestamp": number],
                                   required: ["statement", "madeBy", "rationale", "alternativesConsidered", "timestamp"]),
                "risks": array(["statement": string,
                                "likelihood": ["type": "string", "enum": ["low", "medium", "high", "critical"]],
                                "impact": ["type": "string", "enum": ["low", "medium", "high", "critical"]],
                                "mitigation": string,
                                "timestamp": number],
                               required: ["statement", "likelihood", "impact", "mitigation", "timestamp"]),
                "quotes": array(["text": string,
                                 "speaker": string,
                                 "timestamp": number,
                                 "whyItMatters": string],
                                required: ["text", "speaker", "timestamp", "whyItMatters"]),
                "glossary": array(["term": string,
                                   "definition": string,
                                   "occurrences": ["type": "integer"]],
                                  required: ["term", "definition", "occurrences"])
            ]
        ]
    }

    private static func decode(_ text: String) throws -> ClaudePayload {
        guard let data = text.data(using: .utf8) else {
            throw ClaudeClient.ClientError.decoding("La respuesta no es texto válido.")
        }
        do {
            return try JSONDecoder().decode(ClaudePayload.self, from: data)
        } catch {
            throw ClaudeClient.ClientError.decoding(error.localizedDescription)
        }
    }
}

// MARK: - Carga útil del modelo

struct ClaudePayload: Codable {

    struct TopicPayload: Codable {
        var name: String
        var summary: String
        var weight: Double
        var mentions: Int
        var keywords: [String]
        var firstMention: Double
    }

    struct ProposalPayload: Codable {
        var statement: String
        var proposedBy: String
        var rationale: String
        var expectedImpact: String
        var effort: String
        var timestamp: Double
    }

    struct CritiquePayload: Codable {
        var statement: String
        var target: String
        var severity: String
        var raisedBy: String
        var counterpoint: String
        var timestamp: Double
    }

    struct CommitmentPayload: Codable {
        var statement: String
        var owner: String
        var dueDescription: String
        var status: String
        var timestamp: Double
    }

    struct DecisionPayload: Codable {
        var statement: String
        var madeBy: String
        var rationale: String
        var alternativesConsidered: [String]
        var timestamp: Double
    }

    struct RiskPayload: Codable {
        var statement: String
        var likelihood: String
        var impact: String
        var mitigation: String
        var timestamp: Double
    }

    struct QuotePayload: Codable {
        var text: String
        var speaker: String
        var timestamp: Double
        var whyItMatters: String
    }

    struct GlossaryPayload: Codable {
        var term: String
        var definition: String
        var occurrences: Int
    }

    var title: String
    var subtitle: String
    var executiveSummary: String
    var keyPoints: [String]
    var topics: [TopicPayload]
    var proposals: [ProposalPayload]
    var critiques: [CritiquePayload]
    var commitments: [CommitmentPayload]
    var decisions: [DecisionPayload]
    var risks: [RiskPayload]
    var openQuestions: [String]
    var nextSteps: [String]
    var quotes: [QuotePayload]
    var glossary: [GlossaryPayload]

    func toReport(session: RecordingSession, limits: ResourceLimits) -> AnalysisReport {
        var report = AnalysisReport.empty(sessionID: session.id,
                                          title: title.isEmpty ? session.title : title)
        report.subtitle = subtitle
        report.executiveSummary = executiveSummary
        report.keyPoints = keyPoints
        report.openQuestions = openQuestions
        report.nextSteps = nextSteps

        report.topics = topics.prefix(limits.maxTableRows).map {
            Topic(name: $0.name,
                  summary: $0.summary,
                  weight: $0.weight,
                  mentions: $0.mentions,
                  keywords: $0.keywords,
                  firstMention: $0.firstMention)
        }
        report.proposals = proposals.prefix(limits.maxTableRows).map {
            Proposal(statement: $0.statement,
                     proposedBy: $0.proposedBy,
                     rationale: $0.rationale,
                     expectedImpact: $0.expectedImpact,
                     effort: Effort(rawValue: $0.effort) ?? .unknown,
                     timestamp: $0.timestamp,
                     supportingQuotes: [])
        }
        report.critiques = critiques.prefix(limits.maxTableRows).map {
            Critique(statement: $0.statement,
                     target: $0.target,
                     severity: Severity(rawValue: $0.severity) ?? .medium,
                     raisedBy: $0.raisedBy,
                     counterpoint: $0.counterpoint,
                     timestamp: $0.timestamp)
        }
        report.commitments = commitments.prefix(limits.maxTableRows).map { payload in
            let due = TranscriptStatistics.dueDate(in: payload.dueDescription, reference: session.createdAt)
            return Commitment(statement: payload.statement,
                              owner: payload.owner,
                              dueDescription: payload.dueDescription,
                              dueDate: due.date,
                              status: CommitmentStatus(rawValue: payload.status) ?? .pending,
                              timestamp: payload.timestamp,
                              verifiable: due.date != nil && !payload.owner.isEmpty)
        }
        report.decisions = decisions.prefix(limits.maxTableRows).map {
            Decision(statement: $0.statement,
                     madeBy: $0.madeBy,
                     rationale: $0.rationale,
                     alternativesConsidered: $0.alternativesConsidered,
                     timestamp: $0.timestamp)
        }
        report.risks = risks.prefix(limits.maxTableRows).map {
            Risk(statement: $0.statement,
                 likelihood: Severity(rawValue: $0.likelihood) ?? .medium,
                 impact: Severity(rawValue: $0.impact) ?? .medium,
                 mitigation: $0.mitigation,
                 timestamp: $0.timestamp)
        }
        report.quotes = quotes.prefix(8).map {
            Quote(text: $0.text, speaker: $0.speaker, timestamp: $0.timestamp, whyItMatters: $0.whyItMatters)
        }
        report.glossary = glossary.prefix(20).map {
            GlossaryTerm(term: $0.term, definition: $0.definition, occurrences: $0.occurrences)
        }

        var events: [TimelineEvent] = []
        events += report.proposals.map { TimelineEvent(timestamp: $0.timestamp, kind: .proposal, label: $0.statement) }
        events += report.decisions.map { TimelineEvent(timestamp: $0.timestamp, kind: .decision, label: $0.statement) }
        events += report.commitments.map { TimelineEvent(timestamp: $0.timestamp, kind: .commitment, label: $0.statement) }
        events += report.critiques.map { TimelineEvent(timestamp: $0.timestamp, kind: .critique, label: $0.statement) }
        events += report.risks.map { TimelineEvent(timestamp: $0.timestamp, kind: .risk, label: $0.statement) }
        events += report.topics.map { TimelineEvent(timestamp: $0.firstMention, kind: .topicShift, label: $0.name) }
        report.timeline = Array(events.sorted { $0.timestamp < $1.timestamp }.prefix(limits.maxChartPoints))

        return report
    }
}
