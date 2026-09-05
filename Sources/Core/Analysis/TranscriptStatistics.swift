import Foundation
import NaturalLanguage

/// Métricas objetivas que no dependen del motor de análisis: quién habló
/// cuánto, cómo evolucionó el tono, qué palabras cargan el peso.
///
/// Se calculan en una pasada sobre las intervenciones, sin construir el texto
/// completo en memoria más de una vez.
enum TranscriptStatistics {

    /// Puntuación de sentimiento por intervención. Usa el modelo de Apple
    /// cuando el idioma está soportado y un léxico de marcadores cuando no.
    static func sentiment(for transcript: Transcript) -> [UUID: Double] {
        let tagger = NLTagger(tagSchemes: [.sentimentScore])
        var result: [UUID: Double] = [:]
        for utterance in transcript.utterances {
            let text = utterance.text
            guard text.count > 12 else {
                result[utterance.id] = 0
                continue
            }
            tagger.string = text
            let (tag, _) = tagger.tag(at: text.startIndex, unit: .paragraph, scheme: .sentimentScore)
            if let raw = tag?.rawValue, let value = Double(raw), value != 0 {
                result[utterance.id] = value
            } else {
                result[utterance.id] = lexicalSentiment(text)
            }
            tagger.string = nil
        }
        return result
    }

    private static func lexicalSentiment(_ text: String) -> Double {
        var score = 0.0
        if LinguisticResources.containsAny(text, markers: LinguisticResources.agreementMarkers) { score += 0.4 }
        if LinguisticResources.containsAny(text, markers: LinguisticResources.critiqueMarkers) { score -= 0.4 }
        if LinguisticResources.containsAny(text, markers: LinguisticResources.riskMarkers) { score -= 0.3 }
        if LinguisticResources.containsAny(text, markers: LinguisticResources.intensifiers) { score *= 1.4 }
        return max(-1, min(1, score))
    }

    /// Serie temporal de sentimiento, remuestreada al número de puntos que
    /// permita el aparato para que la gráfica no crezca con la duración.
    static func sentimentSeries(from transcript: Transcript,
                                scores: [UUID: Double],
                                maxPoints: Int) -> [SentimentPoint] {
        let sorted = transcript.utterances.sorted { $0.start < $1.start }
        guard !sorted.isEmpty, maxPoints > 1 else { return [] }
        let duration = max(1, transcript.duration)
        let bucketSeconds = duration / Double(maxPoints)

        var buckets: [Int: [Double]] = [:]
        for utterance in sorted {
            let index = min(maxPoints - 1, Int(utterance.start / bucketSeconds))
            buckets[index, default: []].append(scores[utterance.id] ?? 0)
        }
        return buckets.keys.sorted().map { index in
            let values = buckets[index] ?? []
            let mean = values.isEmpty ? 0 : values.reduce(0, +) / Double(values.count)
            return SentimentPoint(timestamp: Double(index) * bucketSeconds, score: mean)
        }
    }

    /// Palabras clave por frecuencia lematizada, descontando vacías.
    static func keywords(from transcript: Transcript, limit: Int) -> [(term: String, count: Int)] {
        let tagger = NLTagger(tagSchemes: [.lemma])
        var counts: [String: Int] = [:]

        for utterance in transcript.utterances {
            let text = utterance.text.lowercased()
            guard text.count > 3 else { continue }
            tagger.string = text
            tagger.enumerateTags(in: text.startIndex..<text.endIndex,
                                 unit: .word,
                                 scheme: .lemma,
                                 options: [.omitPunctuation, .omitWhitespace, .omitOther]) { tag, range in
                let raw = tag?.rawValue ?? String(text[range])
                let term = raw.trimmingCharacters(in: .punctuationCharacters)
                if term.count > 3 && !LinguisticResources.stopwords.contains(term) && Int(term) == nil {
                    counts[term, default: 0] += 1
                }
                return true
            }
            tagger.string = nil
        }
        return counts
            .sorted { $0.value == $1.value ? $0.key < $1.key : $0.value > $1.value }
            .prefix(limit)
            .map { (term: $0.key, count: $0.value) }
    }

    /// Nombres propios de persona citados, para intentar poner responsable a
    /// los compromisos.
    static func personNames(in text: String) -> [String] {
        let tagger = NLTagger(tagSchemes: [.nameType])
        tagger.string = text
        var names: [String] = []
        tagger.enumerateTags(in: text.startIndex..<text.endIndex,
                             unit: .word,
                             scheme: .nameType,
                             options: [.omitPunctuation, .omitWhitespace, .joinNames]) { tag, range in
            if tag == .personalName {
                names.append(String(text[range]))
            }
            return true
        }
        return names
    }

    static func dueDate(in text: String, reference: Date) -> (date: Date?, phrase: String) {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue) else {
            return (nil, "")
        }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = detector.firstMatch(in: text, options: [], range: range) else {
            return (nil, "")
        }
        let phrase = (text as NSString).substring(with: match.range)
        return (match.date, phrase)
    }

    static func metrics(transcript: Transcript,
                        session: RecordingSession,
                        commitments: [Commitment],
                        critiques: [Critique],
                        agreements: Int,
                        sentiment: [UUID: Double]) -> ReportMetrics {
        let duration = max(transcript.duration, session.duration)
        let minutes = max(1.0 / 60.0, duration / 60)
        let questions = transcript.utterances.filter { LinguisticResources.isQuestion($0.text) }.count
        let sentimentValues = Array(sentiment.values)
        let overall = sentimentValues.isEmpty ? 0 : sentimentValues.reduce(0, +) / Double(sentimentValues.count)
        let objections = max(critiques.count, 0)
        let agreementIndex = (agreements + objections) > 0
            ? Double(agreements) / Double(agreements + objections)
            : 0.5

        return ReportMetrics(durationSeconds: duration,
                             wordCount: transcript.wordCount,
                             wordsPerMinute: Double(transcript.wordCount) / minutes,
                             speakingCoverage: transcript.coverage,
                             questionCount: questions,
                             actionDensity: Double(commitments.count) / max(0.1, duration / 3600),
                             agreementIndex: agreementIndex,
                             overallSentiment: overall)
    }
}
