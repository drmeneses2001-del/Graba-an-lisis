import Foundation

// MARK: - Escalas

enum Severity: String, Codable, CaseIterable {
    case low, medium, high, critical

    var displayName: String {
        switch self {
        case .low: return "Baja"
        case .medium: return "Media"
        case .high: return "Alta"
        case .critical: return "Crítica"
        }
    }

    var weight: Double {
        switch self {
        case .low: return 0.25
        case .medium: return 0.5
        case .high: return 0.75
        case .critical: return 1.0
        }
    }
}

enum CommitmentStatus: String, Codable, CaseIterable {
    case agreed        // aceptado sin reservas
    case conditional   // aceptado con condiciones
    case pending       // mencionado, sin cierre
    case atRisk        // hay objecion o falta responsable

    var displayName: String {
        switch self {
        case .agreed: return "Acordado"
        case .conditional: return "Condicionado"
        case .pending: return "Pendiente"
        case .atRisk: return "En riesgo"
        }
    }
}

enum Effort: String, Codable, CaseIterable {
    case small, medium, large, unknown

    var displayName: String {
        switch self {
        case .small: return "Bajo"
        case .medium: return "Medio"
        case .large: return "Alto"
        case .unknown: return "Sin estimar"
        }
    }
}

// MARK: - Elementos del análisis

struct Topic: Codable, Identifiable, Hashable {
    var id = UUID()
    var name: String
    var summary: String
    /// Peso relativo dentro de la conversación, 0-1.
    var weight: Double
    var mentions: Int
    var keywords: [String]
    var firstMention: TimeInterval
}

struct Proposal: Codable, Identifiable, Hashable {
    var id = UUID()
    var statement: String
    var proposedBy: String
    var rationale: String
    var expectedImpact: String
    var effort: Effort
    var timestamp: TimeInterval
    var supportingQuotes: [String]
}

struct Critique: Codable, Identifiable, Hashable {
    var id = UUID()
    var statement: String
    var target: String
    var severity: Severity
    var raisedBy: String
    var counterpoint: String
    var timestamp: TimeInterval
}

struct Commitment: Codable, Identifiable, Hashable {
    var id = UUID()
    var statement: String
    var owner: String
    var dueDescription: String
    var dueDate: Date?
    var status: CommitmentStatus
    var timestamp: TimeInterval
    var verifiable: Bool
}

struct Decision: Codable, Identifiable, Hashable {
    var id = UUID()
    var statement: String
    var madeBy: String
    var rationale: String
    var alternativesConsidered: [String]
    var timestamp: TimeInterval
}

struct Risk: Codable, Identifiable, Hashable {
    var id = UUID()
    var statement: String
    var likelihood: Severity
    var impact: Severity
    var mitigation: String
    var timestamp: TimeInterval

    var score: Double { likelihood.weight * impact.weight }
}

struct Quote: Codable, Identifiable, Hashable {
    var id = UUID()
    var text: String
    var speaker: String
    var timestamp: TimeInterval
    var whyItMatters: String
}

struct TimelineEvent: Codable, Identifiable, Hashable {
    enum Kind: String, Codable {
        case topicShift, proposal, decision, commitment, critique, risk

        var displayName: String {
            switch self {
            case .topicShift: return "Cambio de tema"
            case .proposal: return "Propuesta"
            case .decision: return "Decisión"
            case .commitment: return "Compromiso"
            case .critique: return "Crítica"
            case .risk: return "Riesgo"
            }
        }
    }

    var id = UUID()
    var timestamp: TimeInterval
    var kind: Kind
    var label: String
}

struct SpeakerStat: Codable, Identifiable, Hashable {
    var id = UUID()
    var speaker: String
    var seconds: TimeInterval
    var words: Int
    var turns: Int
    /// Fracción del tiempo hablado total, 0-1.
    var share: Double
    var averageSentiment: Double
}

struct SentimentPoint: Codable, Hashable {
    var timestamp: TimeInterval
    /// -1 negativo, 0 neutro, +1 positivo.
    var score: Double
}

struct GlossaryTerm: Codable, Identifiable, Hashable {
    var id = UUID()
    var term: String
    var definition: String
    var occurrences: Int
}

struct ReportMetrics: Codable, Hashable {
    var durationSeconds: TimeInterval
    var wordCount: Int
    var wordsPerMinute: Double
    var speakingCoverage: Double
    var questionCount: Int
    var actionDensity: Double      // compromisos por hora
    var agreementIndex: Double     // acuerdos frente a objeciones, 0-1
    var overallSentiment: Double
}

struct AnalysisProvenance: Codable, Hashable {
    var engine: String
    var model: String?
    var generatedAt: Date
    var transcriptWords: Int
    var chunksProcessed: Int
    var notes: String
}

// MARK: - Informe completo

struct AnalysisReport: Codable, Identifiable, Hashable {
    var id = UUID()
    var sessionID: UUID
    var title: String
    var subtitle: String
    /// Resumen ejecutivo, dos o tres párrafos.
    var executiveSummary: String
    var keyPoints: [String]
    var topics: [Topic]
    var proposals: [Proposal]
    var critiques: [Critique]
    var commitments: [Commitment]
    var decisions: [Decision]
    var risks: [Risk]
    var openQuestions: [String]
    var nextSteps: [String]
    var quotes: [Quote]
    var glossary: [GlossaryTerm]
    var timeline: [TimelineEvent]
    var participation: [SpeakerStat]
    var sentimentSeries: [SentimentPoint]
    var metrics: ReportMetrics
    var provenance: AnalysisProvenance

    static func empty(sessionID: UUID, title: String) -> AnalysisReport {
        AnalysisReport(
            sessionID: sessionID,
            title: title,
            subtitle: "",
            executiveSummary: "",
            keyPoints: [],
            topics: [],
            proposals: [],
            critiques: [],
            commitments: [],
            decisions: [],
            risks: [],
            openQuestions: [],
            nextSteps: [],
            quotes: [],
            glossary: [],
            timeline: [],
            participation: [],
            sentimentSeries: [],
            metrics: ReportMetrics(durationSeconds: 0,
                                   wordCount: 0,
                                   wordsPerMinute: 0,
                                   speakingCoverage: 0,
                                   questionCount: 0,
                                   actionDensity: 0,
                                   agreementIndex: 0,
                                   overallSentiment: 0),
            provenance: AnalysisProvenance(engine: "",
                                           model: nil,
                                           generatedAt: Date(),
                                           transcriptWords: 0,
                                           chunksProcessed: 0,
                                           notes: ""))
    }
}
