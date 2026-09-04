import Foundation

/// Marcadores de discurso que delatan cada tipo de contenido.
///
/// El motor en el dispositivo no entiende la conversación: reconoce las
/// fórmulas con las que la gente propone, objeta, decide y se compromete. Es
/// una heurística, y por eso el informe marca siempre con qué motor se generó.
enum LinguisticResources {

    static let stopwords: Set<String> = [
        // Español
        "a", "al", "algo", "algunas", "algunos", "ante", "antes", "como", "con", "contra",
        "cual", "cuando", "de", "del", "desde", "donde", "durante", "e", "el", "ella",
        "ellas", "ellos", "en", "entre", "era", "eran", "es", "esa", "esas", "ese", "eso",
        "esos", "esta", "estaba", "estamos", "estan", "están", "estar", "este", "esto",
        "estos", "estoy", "fue", "fueron", "ha", "haber", "habia", "había", "han", "hasta",
        "hay", "la", "las", "le", "les", "lo", "los", "mas", "más", "me", "mi", "mientras",
        "muy", "nada", "ni", "no", "nos", "nosotros", "o", "os", "otra", "otro", "para",
        "pero", "poco", "por", "porque", "que", "qué", "quien", "quienes", "se", "sea",
        "segun", "según", "ser", "si", "sí", "sido", "sin", "sobre", "solo", "sólo", "son",
        "su", "sus", "tambien", "también", "tanto", "te", "tenemos", "tener", "tengo",
        "ti", "tiene", "tienen", "todo", "todos", "tu", "tus", "un", "una", "uno", "unos",
        "vamos", "vosotros", "vuestra", "y", "ya", "yo", "eh", "em", "bueno", "vale",
        "entonces", "pues", "osea", "digamos", "claro", "mira", "oye",
        // Inglés
        "about", "after", "all", "also", "an", "and", "any", "are", "as", "at", "be",
        "because", "been", "but", "by", "can", "come", "could", "do", "does", "for", "from",
        "get", "go", "has", "have", "he", "her", "here", "his", "how", "i", "if", "in",
        "into", "is", "it", "its", "just", "like", "make", "more", "my", "not",
        "of", "on", "one", "or", "other", "our", "out", "over", "own", "say", "she", "so",
        "some", "than", "that", "the", "their", "them", "then", "there", "these", "they",
        "this", "to", "up", "us", "was", "we", "were", "what", "when", "which", "who",
        "will", "with", "would", "you", "your", "okay", "yeah", "right", "well"
    ]

    static let commitmentMarkers = [
        "me comprometo", "nos comprometemos", "yo me encargo", "me encargo de",
        "lo hago yo", "quedamos en que", "quedo en", "me lo llevo", "lo asumo",
        "voy a preparar", "voy a enviar", "voy a hablar", "voy a revisar", "voy a montar",
        "lo tendré", "lo tendre", "te lo paso", "te lo envío", "te lo envio",
        "para el lunes", "para el martes", "para el miércoles", "para el jueves",
        "para el viernes", "antes del", "antes de fin de", "de aquí al",
        "i will", "i'll take", "we commit", "action item", "i'll send", "i'll prepare",
        "by monday", "by friday", "by the end of"
    ]

    static let proposalMarkers = [
        "propongo", "propuesta", "yo propondría", "yo propondria", "sugiero", "sugerencia",
        "deberíamos", "deberiamos", "podríamos", "podriamos", "planteo", "yo plantearía",
        "qué tal si", "que tal si", "y si hacemos", "una idea", "mi propuesta",
        "lo ideal sería", "lo ideal seria", "convendría", "convendria",
        "i propose", "we should", "we could", "my suggestion", "what if we", "let's"
    ]

    static let critiqueMarkers = [
        "no estoy de acuerdo", "discrepo", "el problema es", "el problema está",
        "me preocupa", "no me convence", "objeción", "objecion", "no funciona",
        "es un error", "está mal", "esta mal", "falla", "no veo claro", "en contra",
        "no tiene sentido", "no lo veo", "eso no", "el riesgo de eso", "lo malo es",
        "sin embargo", "el inconveniente", "es insuficiente", "no cuadra",
        "i disagree", "the problem is", "i'm concerned", "that won't work", "the issue is"
    ]

    static let decisionMarkers = [
        "decidimos", "queda decidido", "está decidido", "esta decidido", "aprobado",
        "se aprueba", "acordamos", "de acuerdo entonces", "cerramos", "vamos con",
        "nos quedamos con", "adelante con", "queda aprobado", "lo damos por",
        "we decided", "approved", "let's go with", "agreed", "final decision"
    ]

    static let riskMarkers = [
        "riesgo", "peligro", "podría fallar", "podria fallar", "amenaza",
        "cuello de botella", "retraso", "dependemos de", "si no llega", "si falla",
        "no llegamos", "nos quedamos sin", "puede caerse", "es frágil", "es fragil",
        "bloquea", "bloqueante", "sin presupuesto", "falta gente",
        "risk", "blocker", "bottleneck", "delay", "we depend on", "might fail"
    ]

    static let agreementMarkers = [
        "de acuerdo", "me parece bien", "perfecto", "correcto", "sí, claro",
        "eso es", "exacto", "buena idea", "lo veo", "adelante",
        "agreed", "sounds good", "makes sense", "exactly", "good idea"
    ]

    static let intensifiers = [
        "muy", "grave", "gravísimo", "crítico", "critico", "inaceptable", "urgente",
        "imposible", "catastrófico", "catastrofico", "enorme", "bloquea", "jamás",
        "nunca", "severe", "critical", "urgent", "unacceptable", "blocking"
    ]

    static let smallEffortMarkers = [
        "rápido", "rapido", "sencillo", "fácil", "facil", "en un rato", "esta tarde",
        "un par de horas", "trivial", "quick", "simple", "easy"
    ]

    static let largeEffortMarkers = [
        "complejo", "complicado", "meses", "un trimestre", "reescribir", "migrar",
        "hace falta un equipo", "gran esfuerzo", "costoso", "complex", "months", "rewrite"
    ]

    /// Coincidencia por marcador, insensible a mayúsculas y acentos.
    static func matches(_ text: String, markers: [String]) -> String? {
        let normalized = normalize(text)
        for marker in markers where normalized.contains(normalize(marker)) {
            return marker
        }
        return nil
    }

    static func containsAny(_ text: String, markers: [String]) -> Bool {
        matches(text, markers: markers) != nil
    }

    static func normalize(_ text: String) -> String {
        text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "es_ES"))
    }

    static func isQuestion(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.hasSuffix("?") || trimmed.hasPrefix("¿")
    }
}
