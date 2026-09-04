import Foundation

/// Escritor incremental de PCM crudo con tope duro de tamano.
///
/// No acumula nada: cada bloque que llega se escribe y se olvida. Es la pieza
/// que usa la extension de difusion, donde el presupuesto de memoria es de unas
/// decenas de megas y una sola reserva descuidada mata el proceso.
final class PCMFileWriter {

    enum WriteResult {
        case written(Int)
        /// Se alcanzo el tope; el escritor deja de aceptar datos.
        case capped
    }

    private let handle: FileHandle
    private let maxBytes: UInt64
    private(set) var bytesWritten: UInt64 = 0
    private(set) var isCapped = false

    let url: URL

    init(url: URL, maxBytes: UInt64) throws {
        self.url = url
        self.maxBytes = maxBytes
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: url.deletingLastPathComponent(),
                                        withIntermediateDirectories: true)
        if !fileManager.fileExists(atPath: url.path) {
            fileManager.createFile(atPath: url.path, contents: nil)
        }
        handle = try FileHandle(forWritingTo: url)
        try handle.seekToEnd()
        bytesWritten = (try? handle.offset()) ?? 0
    }

    /// Escribe sin copiar. `bytes` solo tiene que ser valido durante la llamada.
    @discardableResult
    func append(_ bytes: UnsafeRawBufferPointer) -> WriteResult {
        guard !isCapped, let base = bytes.baseAddress, bytes.count > 0 else {
            return isCapped ? .capped : .written(0)
        }
        let remaining = maxBytes > bytesWritten ? maxBytes - bytesWritten : 0
        guard remaining > 0 else {
            isCapped = true
            return .capped
        }
        let count = min(bytes.count, Int(min(remaining, UInt64(Int.max))))
        let data = Data(bytesNoCopy: UnsafeMutableRawPointer(mutating: base),
                        count: count,
                        deallocator: .none)
        do {
            try handle.write(contentsOf: data)
        } catch {
            isCapped = true
            return .capped
        }
        bytesWritten += UInt64(count)
        if bytesWritten >= maxBytes { isCapped = true }
        return .written(count)
    }

    var seconds: TimeInterval {
        AudioFormatSpec.seconds(fromBytes: bytesWritten)
    }

    func close() {
        try? handle.synchronize()
        try? handle.close()
    }

    deinit {
        try? handle.close()
    }
}
