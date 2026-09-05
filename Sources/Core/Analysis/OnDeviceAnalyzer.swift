import Foundation
import NaturalLanguage

/// Motor de análisis que no sale del aparato.
///
/// Clasifica cada frase por los marcadores de discurso que contiene, puntúa las
/// frases por densidad de palabras clave para el resumen extractivo, y calcula
/// las métricas a partir del audio. No inventa nada: todo lo que aparece en el
/// informe está literalmente en la transcripción.
///
/// El coste en memoria está acotado por `ResourceLimits.maxTranscriptCharsInMemory`:
/// si la transcripción es más larga, se analiza por bloques y se conserva solo
/// lo seleccionado.
struct OnDeviceAnalyzer: AnalysisEngine {

    let displayName = "Análisis en el dispositivo"
    let sendsDataOffDevice = false

    private struct Sentence {
        let text: String
        let timestamp: TimeInterval
        let utteranceID: UUID
        var score: Double = 0
    }

    func analyze(transcript: Transcript,
                 session: RecordingSession,
                 limits: ResourceLimits,
                 progress: @escaping @Sendable (Double, String) -> Void) async throws -> AnalysisReport {

        progress(0.1, "Midiendo el tono")
        let sentimentScores = TranscriptStatistics.sentiment(for: transcript)

        progress(0.2, "Extrayendo vocabulario")
        let keywords = TranscriptStatistics.keywords(from: transcript, limit: 40)
        let keywordWeights = Self.weights(from: keywords)

        progress(0.35, "Segmentando en frases")
        var sentences = Self.sentences(from: transcript, charBudget: limits.maxTranscriptCharsInMemory)
        var truncationNote = ""
        let totalChars = transcript.utterances.reduce(0) { $0 + $1.text.count }
        if totalChars > limits.maxTranscriptCharsInMemory {
            truncationNote = "La transcripción supera el presupuesto de memoria del dispositivo (\(totalChars) caracteres). Se analizó una selección uniforme del \(Int(Double(limits.maxTranscriptCharsInMemory) / Double(totalChars) * 100)) % del texto."
        }

        for index in sentences.indices {
            sentences[index].score = Self.score(sentences[index], keywordWeights: keywordWeights)
        }

        progress(0.5, "Clasificando aportaciones")
        var proposals: [Proposal] = []
        var critiques: [Critique] = []
        var commitments: [Commitment] = []
        var decisions: [Decision] = []
        var risks: [Risk] = []
        var openQuestions: [String] = []
        var agreements = 0

        for sentence in sentences {
            let text = sentence.text

            if LinguisticResources.containsAny(text, markers: LinguisticResources.agreementMarkers) {
                agreements += 1
            }

            if LinguisticResources.containsAny(text, markers: LinguisticResources.commitmentMarkers) {
                commitments.append(Self.commitment(from: sentence, reference: session.createdAt))
            }
            if LinguisticResources.containsAny(text, markers: LinguisticResources.proposalMarkers) {
                proposals.append(Self.proposal(from: sentence))
            }
            if LinguisticResources.containsAny(text, markers: LinguisticResources.critiqueMarkers) {
                critiques.append(Self.critique(from: sentence))
            }
            if LinguisticResources.containsAny(text, markers: LinguisticResources.decisionMarkers) {
                decisions.append(Self.decision(from: sentence))
            }
            if LinguisticResources.containsAny(text, markers: LinguisticResources.riskMarkers) {
                risks.append(Self.risk(from: sentence))
            }
            if LinguisticResources.isQuestion(text) && text.count > 20 && openQuestions.count < limits.maxTableRows {
                openQuestions.append(text)
            }
        }

        // Las preguntas que alguien contestó justo después no siguen abiertas.
        openQuestions = Self.filterAnswered(openQuestions, in: sentences)

        proposals = Array(Self.deduplicate(proposals, key: \.statement).prefix(limits.maxTableRows))
        critiques = Array(Self.deduplicate(critiques, key: \.statement).prefix(limits.maxTableRows))
        commitments = Array(Self.deduplicate(commitments, key: \.statement).prefix(limits.maxTableRows))
        decisions = Array(Self.deduplicate(decisions, key: \.statement).prefix(limits.maxTableRows))
        risks = Array(Self.deduplicate(risks, key: \.statement).prefix(limits.maxTableRows).sorted { $0.score > $1.score })

        progress(0.7, "Redactando resumen")
        let ranked = sentences.sorted { $0.score > $1.score }
        let summarySentences = Array(ranked.prefix(8)).sorted { $0.timestamp < $1.timestamp }
        let executiveSummary = Self.buildSummary(summarySentences,
                                                 session: session,
                                                 commitments: commitments,
                                                 decisions: decisions)
        let keyPoints = ranked.dropFirst(8).prefix(7).map(\.text).map(Self.tidy)

        let topics = Self.topics(from: sentences, keywords: keywords, limit: 8)
        let quotes = ranked.prefix(5).map { sentence in
            Quote(text: Self.tidy(sentence.text),
                  speaker: Self.namedAuthor(in: sentence.text),
                  timestamp: sentence.timestamp,
                  whyItMatters: "Concentra los términos más repetidos de la sesión.")
        }
        let glossary = keywords.prefix(12).compactMap { keyword -> GlossaryTerm? in
            guard let sentence = sentences.first(where: {
                LinguisticResources.normalize($0.text).contains(LinguisticResources.normalize(keyword.term))
            }) else { return nil }
            return GlossaryTerm(term: keyword.term.capitalized,
                                definition: Self.tidy(sentence.text),
                                occurrences: keyword.count)
        }

        progress(0.85, "Componiendo cronología")
        let timeline = Self.timeline(proposals: proposals,
                                     decisions: decisions,
                                     commitments: commitments,
                                     critiques: critiques,
                                     risks: risks,
                                     topics: topics,
                                     limit: limits.maxChartPoints)
        let sentimentSeries = TranscriptStatistics.sentimentSeries(from: transcript,
                                                                   scores: sentimentScores,
                                                                   maxPoints: limits.maxChartPoints)
        let metrics = TranscriptStatistics.metrics(transcript: transcript,
                                                   session: session,
                                                   commitments: commitments,
                                                   critiques: critiques,
                                                   agreements: agreements,
                                                   sentiment: sentimentScores)

        let nextSteps = Self.nextSteps(commitments: commitments,
                                       proposals: proposals,
                                       openQuestions: openQuestions,
                                       risks: risks)

        progress(1.0, "Análisis terminado")

        return AnalysisReport(
            sessionID: session.id,
            title: session.title,
            subtitle: Self.subtitle(session: session, topics: topics),
            executiveSummary: executiveSummary,
            keyPoints: Array(keyPoints),
            topics: topics,
            proposals: proposals,
            critiques: critiques,
            commitments: commitments,
            decisions: decisions,
            risks: risks,
            openQuestions: Array(openQuestions.prefix(12)),
            nextSteps: nextSteps,
            quotes: Array(quotes),
            glossary: Array(glossary),
            timeline: timeline,
            sentimentSeries: sentimentSeries,
            metrics: metrics,
            provenance: AnalysisProvenance(
                engine: displayName,
                model: nil,
                generatedAt: Date(),
                transcriptWords: transcript.wordCount,
                chunksProcessed: 1,
                notes: [truncationNote,
                        "Motor heurístico: clasifica por marcadores de discurso y frecuencia de términos. No interpreta ironía ni contexto implícito."]
                    .filter { !$0.isEmpty }
                    .joined(separator: " ")))
    }

    // MARK: - Construcción de frases

    private static func sentences(from transcript: Transcript, charBudget: Int) -> [Sentence] {
        let ordered = transcript.utterances.sorted { $0.start < $1.start }
        let totalChars = ordered.reduce(0) { $0 + $1.text.count }
        // Si no cabe entero, se toma una de cada N intervenciones repartidas por
        // toda la sesión, en vez de cortar por el final y perder el cierre.
        let stride = totalChars > charBudget ? max(1, Int((Double(totalChars) / Double(charBudget)).rounded(.up))) : 1

        let tokenizer = NLTokenizer(unit: .sentence)
        var result: [Sentence] = []
        var consumed = 0

        for (index, utterance) in ordered.enumerated() {
            guard index % stride == 0 else { continue }
            guard consumed < charBudget else { break }
            let text = utterance.text
            tokenizer.string = text
            let ranges = tokenizer.tokens(for: text.startIndex..<text.endIndex)
            let spans = ranges.isEmpty ? [text.startIndex..<text.endIndex] : ranges

            for range in spans {
                let fragment = String(text[range]).trimmingCharacters(in: .whitespacesAndNewlines)
                guard fragment.count > 12 else { continue }
                let offsetRatio = text.isEmpty ? 0 : Double(text.distance(from: text.startIndex, to: range.lowerBound)) / Double(text.count)
                result.append(Sentence(text: fragment,
                                       timestamp: utterance.start + utterance.duration * offsetRatio,
                                       utteranceID: utterance.id))
                consumed += fragment.count
            }
        }
        return result
    }

    private static func weights(from keywords: [(term: String, count: Int)]) -> [String: Double] {
        guard let maximum = keywords.first?.count, maximum > 0 else { return [:] }
        var result: [String: Double] = [:]
        for keyword in keywords {
            result[LinguisticResources.normalize(keyword.term)] = Double(keyword.count) / Double(maximum)
        }
        return result
    }

    private static func score(_ sentence: Sentence, keywordWeights: [String: Double]) -> Double {
        let normalized = LinguisticResources.normalize(sentence.text)
        var score = 0.0
        for (term, weight) in keywordWeights where normalized.contains(term) {
            score += weight
        }
        // Frases muy cortas o interminables rara vez resumen bien.
        let length = Double(sentence.text.count)
        let lengthFactor = length < 40 ? 0.5 : (length > 320 ? 0.6 : 1.0)
        var bonus = 1.0
        if LinguisticResources.containsAny(sentence.text, markers: LinguisticResources.decisionMarkers) { bonus += 0.6 }
        if LinguisticResources.containsAny(sentence.text, markers: LinguisticResources.commitmentMarkers) { bonus += 0.5 }
        if LinguisticResources.containsAny(sentence.text, markers: LinguisticResources.proposalMarkers) { bonus += 0.3 }
        return score * lengthFactor * bonus
    }

    // MARK: - Clasificadores

    private static func commitment(from sentence: Sentence, reference: Date) -> Commitment {
        let due = TranscriptStatistics.dueDate(in: sentence.text, reference: reference)
        let names = TranscriptStatistics.personNames(in: sentence.text)
        let owner = names.first ?? Self.unidentified
        let status: CommitmentStatus
        if LinguisticResources.containsAny(sentence.text, markers: LinguisticResources.critiqueMarkers) {
            status = .atRisk
        } else if LinguisticResources.normalize(sentence.text).contains("si ") || sentence.text.contains("siempre que") {
            status = .conditional
        } else if due.date != nil {
            status = .agreed
        } else {
            status = .pending
        }
        return Commitment(statement: tidy(sentence.text),
                          owner: owner,
                          dueDescription: due.phrase.isEmpty ? "Sin fecha explícita" : due.phrase,
                          dueDate: due.date,
                          status: status,
                          timestamp: sentence.timestamp,
                          verifiable: due.date != nil && !names.isEmpty)
    }

    private static func proposal(from sentence: Sentence) -> Proposal {
        let effort: Effort
        if LinguisticResources.containsAny(sentence.text, markers: LinguisticResources.largeEffortMarkers) {
            effort = .large
        } else if LinguisticResources.containsAny(sentence.text, markers: LinguisticResources.smallEffortMarkers) {
            effort = .small
        } else {
            effort = .unknown
        }
        return Proposal(statement: tidy(sentence.text),
                        proposedBy: Self.namedAuthor(in: sentence.text),
                        rationale: "",
                        expectedImpact: "",
                        effort: effort,
                        timestamp: sentence.timestamp,
                        supportingQuotes: [])
    }

    private static func critique(from sentence: Sentence) -> Critique {
        let intense = LinguisticResources.containsAny(sentence.text, markers: LinguisticResources.intensifiers)
        let risky = LinguisticResources.containsAny(sentence.text, markers: LinguisticResources.riskMarkers)
        let severity: Severity = intense && risky ? .critical : (intense ? .high : (risky ? .medium : .low))
        return Critique(statement: tidy(sentence.text),
                        target: "",
                        severity: severity,
                        raisedBy: Self.namedAuthor(in: sentence.text),
                        counterpoint: "",
                        timestamp: sentence.timestamp)
    }

    private static func decision(from sentence: Sentence) -> Decision {
        Decision(statement: tidy(sentence.text),
                 madeBy: Self.namedAuthor(in: sentence.text),
                 rationale: "",
                 alternativesConsidered: [],
                 timestamp: sentence.timestamp)
    }

    private static func risk(from sentence: Sentence) -> Risk {
        let intense = LinguisticResources.containsAny(sentence.text, markers: LinguisticResources.intensifiers)
        return Risk(statement: tidy(sentence.text),
                    likelihood: intense ? .high : .medium,
                    impact: intense ? .critical : .medium,
                    mitigation: "",
                    timestamp: sentence.timestamp)
    }

    private static func filterAnswered(_ questions: [String], in sentences: [Sentence]) -> [String] {
        questions.filter { question in
            guard let index = sentences.firstIndex(where: { $0.text == question }) else { return true }
            let following = sentences.dropFirst(index + 1).prefix(3)
            // Si lo que sigue no es otra pregunta, dejamos la pregunta por
            // contestada: no hay diarización, así que no se puede exigir que
            // responda "otra persona".
            let answered = following.contains { !LinguisticResources.isQuestion($0.text) }
            return !answered
        }
    }

    /// Único nombre propio citado en la frase, si lo hay. Sin diarización, es
    /// la única manera honesta de intentar poner responsable a algo.
    private static let unidentified = "Sin identificar"

    private static func namedAuthor(in text: String) -> String {
        TranscriptStatistics.personNames(in: text).first ?? unidentified
    }

    private static func deduplicate<T>(_ items: [T], key: KeyPath<T, String>) -> [T] {
        var seen = Set<String>()
        var result: [T] = []
        for item in items {
            let signature = String(LinguisticResources.normalize(item[keyPath: key]).prefix(60))
            if seen.insert(signature).inserted { result.append(item) }
        }
        return result
    }

    // MARK: - Composición

    private static func topics(from sentences: [Sentence],
                               keywords: [(term: String, count: Int)],
                               limit: Int) -> [Topic] {
        let total = max(1, keywords.reduce(0) { $0 + $1.count })
        var used = Set<String>()
        var result: [Topic] = []

        for keyword in keywords {
            guard result.count < limit else { break }
            let normalized = LinguisticResources.normalize(keyword.term)
            guard !used.contains(normalized) else { continue }

            let related = sentences.filter {
                LinguisticResources.normalize($0.text).contains(normalized)
            }
            guard related.count >= 2 else { continue }

            let companions = keywords
                .filter { candidate in
                    let candidateNormalized = LinguisticResources.normalize(candidate.term)
                    guard candidateNormalized != normalized, !used.contains(candidateNormalized) else { return false }
                    return related.contains { LinguisticResources.normalize($0.text).contains(candidateNormalized) }
                }
                .prefix(4)

            used.insert(normalized)
            companions.forEach { used.insert(LinguisticResources.normalize($0.term)) }

            let best = related.max { $0.score < $1.score }
            result.append(Topic(name: keyword.term.capitalized,
                                summary: tidy(best?.text ?? ""),
                                weight: Double(keyword.count) / Double(total),
                                mentions: keyword.count,
                                keywords: [keyword.term] + companions.map(\.term),
                                firstMention: related.map(\.timestamp).min() ?? 0))
        }
        return result
    }

    private static func buildSummary(_ sentences: [Sentence],
                                     session: RecordingSession,
                                     commitments: [Commitment],
                                     decisions: [Decision]) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "es_ES")
        formatter.dateStyle = .long
        formatter.timeStyle = .short

        var paragraphs: [String] = []
        let minutes = Int(session.duration / 60)
        paragraphs.append("Sesión de \(minutes) minutos capturada el \(formatter.string(from: session.createdAt)) a partir del audio que sonó por la salida del dispositivo.")

        let body = sentences.map { tidy($0.text) }.joined(separator: " ")
        if !body.isEmpty { paragraphs.append(body) }

        var closing: [String] = []
        if !decisions.isEmpty { closing.append("Se registraron \(decisions.count) decisiones explícitas") }
        if !commitments.isEmpty { closing.append("\(commitments.count) compromisos, de los cuales \(commitments.filter { $0.dueDate != nil }.count) llevan fecha") }
        if !closing.isEmpty {
            paragraphs.append(closing.joined(separator: " y ") + ".")
        }
        return paragraphs.joined(separator: "\n\n")
    }

    private static func nextSteps(commitments: [Commitment],
                                  proposals: [Proposal],
                                  openQuestions: [String],
                                  risks: [Risk]) -> [String] {
        var steps: [String] = []
        for commitment in commitments.prefix(6) {
            steps.append("\(commitment.owner): \(commitment.statement) — \(commitment.dueDescription)")
        }
        if let risk = risks.first {
            steps.append("Asignar responsable a la mitigación del riesgo principal: \(risk.statement)")
        }
        if let question = openQuestions.first {
            steps.append("Cerrar la pregunta abierta: \(question)")
        }
        for proposal in proposals.prefix(2) where proposal.effort != .large {
            steps.append("Decidir sobre la propuesta: \(proposal.statement)")
        }
        return steps
    }

    private static func timeline(proposals: [Proposal],
                                 decisions: [Decision],
                                 commitments: [Commitment],
                                 critiques: [Critique],
                                 risks: [Risk],
                                 topics: [Topic],
                                 limit: Int) -> [TimelineEvent] {
        var events: [TimelineEvent] = []
        events += proposals.map { TimelineEvent(timestamp: $0.timestamp, kind: .proposal, label: shorten($0.statement)) }
        events += decisions.map { TimelineEvent(timestamp: $0.timestamp, kind: .decision, label: shorten($0.statement)) }
        events += commitments.map { TimelineEvent(timestamp: $0.timestamp, kind: .commitment, label: shorten($0.statement)) }
        events += critiques.map { TimelineEvent(timestamp: $0.timestamp, kind: .critique, label: shorten($0.statement)) }
        events += risks.map { TimelineEvent(timestamp: $0.timestamp, kind: .risk, label: shorten($0.statement)) }
        events += topics.map { TimelineEvent(timestamp: $0.firstMention, kind: .topicShift, label: $0.name) }
        return Array(events.sorted { $0.timestamp < $1.timestamp }.prefix(limit))
    }

    private static func subtitle(session: RecordingSession, topics: [Topic]) -> String {
        let names = topics.prefix(3).map(\.name).joined(separator: " · ")
        return names.isEmpty ? "Difusión del sistema" : names
    }

    private static func tidy(_ text: String) -> String {
        var result = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let first = result.first, first.isLowercase {
            result.replaceSubrange(result.startIndex...result.startIndex, with: String(first).uppercased())
        }
        if let last = result.last, last != "." && last != "?" && last != "!" {
            result += "."
        }
        return result
    }

    private static func shorten(_ text: String, limit: Int = 70) -> String {
        text.count <= limit ? text : String(text.prefix(limit - 1)) + "…"
    }
}
