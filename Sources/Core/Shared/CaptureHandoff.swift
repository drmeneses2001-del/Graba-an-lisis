import Foundation

/// Estado que la extension de ReplayKit publica mientras graba y que la app lee
/// para saber que hay una sesion en curso o recien terminada.
///
/// Se escribe entero en cada actualizacion (son unos pocos cientos de bytes) y
/// como maximo una vez por segundo, para no castigar el presupuesto de memoria
/// ni el de CPU de la extension.
struct CaptureHandoff: Codable {
    var sessionID: UUID
    var startedAt: Date
    var updatedAt: Date
    var seconds: TimeInterval
    var bytes: UInt64
    var isFinished: Bool
    var footprintBytes: UInt64
    var stopReason: String?

    static var fileURL: URL {
        AppGroup.handoffURL.appendingPathComponent("current.json")
    }

    static func load() -> CaptureHandoff? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        return try? JSONDecoder.grabaAnalisis.decode(CaptureHandoff.self, from: data)
    }

    func save() {
        AppGroup.prepareDirectories()
        guard let data = try? JSONEncoder.grabaAnalisis.encode(self) else { return }
        try? data.write(to: Self.fileURL, options: .atomic)
    }

    static func clear() {
        try? FileManager.default.removeItem(at: fileURL)
    }
}

extension JSONEncoder {
    static let grabaAnalisis: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()
}

extension JSONDecoder {
    static let grabaAnalisis: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}
