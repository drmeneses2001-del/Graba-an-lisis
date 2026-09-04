import Foundation
import os

/// Cliente mínimo de la API de mensajes de Anthropic.
///
/// Swift no tiene SDK oficial, así que se habla HTTP directamente contra
/// `POST /v1/messages`. Se usa respuesta en streaming porque los informes largos
/// pueden tardar minutos y una petición sin streaming se caería por tiempo de
/// espera; el texto se acumula en un solo `String`, que para un informe pesa
/// unas decenas de kilobytes.
final class ClaudeClient {

    enum ClientError: LocalizedError {
        case missingKey
        case unauthorized
        case rateLimited
        case refused(String)
        case server(Int, String)
        case decoding(String)
        case offline

        var errorDescription: String? {
            switch self {
            case .missingKey:
                return "Falta la clave de API. Añádela en Ajustes o cambia al motor en el dispositivo."
            case .unauthorized:
                return "La clave de API no es válida o ha sido revocada."
            case .rateLimited:
                return "La API está limitando las peticiones. Inténtalo de nuevo en unos minutos."
            case .refused(let explanation):
                return "El modelo declinó responder a esta petición. \(explanation)"
            case .server(let code, let body):
                return "La API devolvió un error \(code). \(body)"
            case .decoding(let detail):
                return "La respuesta no tenía el formato esperado. \(detail)"
            case .offline:
                return "Sin conexión. El análisis en la nube necesita red; el motor en el dispositivo no."
            }
        }
    }

    struct Response {
        var text: String
        var model: String
        var inputTokens: Int
        var outputTokens: Int
    }

    static let model = "claude-opus-5"
    private static let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!
    private static let version = "2023-06-01"
    /// Si los clasificadores declinan la petición, el servidor la reintenta
    /// solo en un modelo de reserva dentro de la misma llamada.
    private static let fallbackBeta = "server-side-fallback-2026-07-01"

    private let session: URLSession
    private let log = Logger(subsystem: "com.grabaanalisis.app", category: "claude")

    init() {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 120
        configuration.timeoutIntervalForResource = 900
        configuration.waitsForConnectivity = false
        session = URLSession(configuration: configuration)
    }

    /// Una llamada con salida estructurada: el esquema garantiza que la
    /// respuesta es JSON válido y con la forma que espera el decodificador.
    func complete(system: String,
                  user: String,
                  jsonSchema: [String: Any],
                  maxTokens: Int = 32_000,
                  effort: String = "high") async throws -> Response {

        guard let apiKey = KeychainStore.apiKey(), !apiKey.isEmpty else { throw ClientError.missingKey }

        let body: [String: Any] = [
            "model": Self.model,
            "max_tokens": maxTokens,
            "stream": true,
            "thinking": ["type": "adaptive"],
            "output_config": [
                "effort": effort,
                "format": ["type": "json_schema", "schema": jsonSchema]
            ],
            "fallbacks": "default",
            "system": [
                ["type": "text",
                 "text": system,
                 "cache_control": ["type": "ephemeral"]]
            ],
            "messages": [
                ["role": "user", "content": user]
            ]
        ]

        var request = URLRequest(url: Self.endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue(Self.version, forHTTPHeaderField: "anthropic-version")
        request.setValue(Self.fallbackBeta, forHTTPHeaderField: "anthropic-beta")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        return try await sendWithRetries(request)
    }

    // MARK: - Transporte

    private func sendWithRetries(_ request: URLRequest, attempt: Int = 0) async throws -> Response {
        do {
            return try await stream(request)
        } catch ClientError.rateLimited where attempt < 3 {
            try await backoff(attempt)
            return try await sendWithRetries(request, attempt: attempt + 1)
        } catch ClientError.server(let code, _) where code >= 500 && attempt < 3 {
            try await backoff(attempt)
            return try await sendWithRetries(request, attempt: attempt + 1)
        } catch let error as URLError where attempt < 2 {
            if error.code == .notConnectedToInternet || error.code == .dataNotAllowed {
                throw ClientError.offline
            }
            try await backoff(attempt)
            return try await sendWithRetries(request, attempt: attempt + 1)
        }
    }

    private func backoff(_ attempt: Int) async throws {
        let seconds = pow(2.0, Double(attempt + 1))
        try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
    }

    private func stream(_ request: URLRequest) async throws -> Response {
        let (bytes, response) = try await session.bytes(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw ClientError.server(-1, "Respuesta sin cabecera HTTP.")
        }
        guard http.statusCode == 200 else {
            var detail = ""
            for try await line in bytes.lines {
                detail += line
                if detail.count > 2_000 { break }
            }
            switch http.statusCode {
            case 401, 403: throw ClientError.unauthorized
            case 429: throw ClientError.rateLimited
            default: throw ClientError.server(http.statusCode, detail)
            }
        }

        var text = ""
        var model = Self.model
        var inputTokens = 0
        var outputTokens = 0
        var stopReason: String?
        var refusalExplanation = ""

        for try await line in bytes.lines {
            guard line.hasPrefix("data:") else { continue }
            let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
            guard !payload.isEmpty, payload != "[DONE]",
                  let data = payload.data(using: .utf8),
                  let event = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let type = event["type"] as? String
            else { continue }

            switch type {
            case "message_start":
                if let message = event["message"] as? [String: Any] {
                    model = (message["model"] as? String) ?? model
                    if let usage = message["usage"] as? [String: Any] {
                        inputTokens = (usage["input_tokens"] as? Int) ?? 0
                    }
                }
            case "content_block_delta":
                if let delta = event["delta"] as? [String: Any],
                   delta["type"] as? String == "text_delta",
                   let fragment = delta["text"] as? String {
                    text += fragment
                }
            case "message_delta":
                if let delta = event["delta"] as? [String: Any] {
                    stopReason = (delta["stop_reason"] as? String) ?? stopReason
                    if let details = delta["stop_details"] as? [String: Any] {
                        refusalExplanation = (details["explanation"] as? String) ?? ""
                    }
                }
                if let usage = event["usage"] as? [String: Any] {
                    outputTokens = (usage["output_tokens"] as? Int) ?? outputTokens
                }
            case "error":
                let message = ((event["error"] as? [String: Any])?["message"] as? String) ?? "Error desconocido."
                throw ClientError.server(http.statusCode, message)
            default:
                continue
            }
        }

        if stopReason == "refusal" {
            throw ClientError.refused(refusalExplanation.isEmpty
                                      ? "Prueba con el motor en el dispositivo."
                                      : refusalExplanation)
        }
        guard !text.isEmpty else { throw ClientError.decoding("La respuesta llegó vacía.") }

        return Response(text: text, model: model, inputTokens: inputTokens, outputTokens: outputTokens)
    }

    /// Comprobación rápida de la clave, para el botón de Ajustes.
    func validateKey() async -> Result<String, Error> {
        do {
            let response = try await complete(
                system: "Responde en JSON.",
                user: "Devuelve {\"ok\": true}.",
                jsonSchema: ["type": "object",
                             "properties": ["ok": ["type": "boolean"]],
                             "required": ["ok"],
                             "additionalProperties": false],
                maxTokens: 1_024,
                effort: "low")
            return .success(response.model)
        } catch {
            return .failure(error)
        }
    }
}
