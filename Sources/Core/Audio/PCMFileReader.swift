import Foundation
import AVFoundation

/// Lector por trozos de los ficheros PCM de una sesion.
///
/// Nunca carga el fichero entero. El consumidor recibe buffers pequenos que se
/// reutilizan entre iteraciones, asi que transcribir dos horas de audio cuesta
/// lo mismo en memoria que transcribir dos minutos.
final class PCMFileReader {

    struct Window {
        let index: Int
        let start: TimeInterval
        let end: TimeInterval
        let byteRange: Range<UInt64>

        var duration: TimeInterval { end - start }
    }

    private let handle: FileHandle
    let url: URL
    let totalBytes: UInt64

    init(url: URL) throws {
        self.url = url
        handle = try FileHandle(forReadingFrom: url)
        totalBytes = FileManager.default.fileSizeBytes(at: url)
    }

    var duration: TimeInterval {
        AudioFormatSpec.seconds(fromBytes: totalBytes)
    }

    /// Divide el fichero en ventanas solapadas. Solo devuelve rangos: no se lee
    /// ni un byte de audio aqui.
    func windows(seconds: TimeInterval, overlap: TimeInterval) -> [Window] {
        guard totalBytes > 0, seconds > 0 else { return [] }
        let step = max(1.0, seconds - overlap)
        var result: [Window] = []
        var start: TimeInterval = 0
        var index = 0
        while start < duration {
            let end = min(duration, start + seconds)
            let lower = AudioFormatSpec.bytes(forSeconds: start)
            let upper = min(totalBytes, AudioFormatSpec.bytes(forSeconds: end))
            if upper > lower {
                result.append(Window(index: index, start: start, end: end, byteRange: lower..<upper))
                index += 1
            }
            if end >= duration { break }
            start += step
        }
        return result
    }

    /// Lee un rango y entrega buffers en coma flotante, que es lo que consume
    /// el reconocedor de voz. El buffer se reutiliza; el consumidor no debe
    /// guardarlo.
    func readFloatBuffers(range: Range<UInt64>,
                          chunkBytes: Int,
                          body: (AVAudioPCMBuffer) throws -> Void) throws {
        guard range.upperBound > range.lowerBound else { return }
        let format = AudioFormatSpec.recognitionFormat
        let framesPerChunk = AVAudioFrameCount(max(1, chunkBytes / AudioFormatSpec.bytesPerFrame))
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: framesPerChunk),
              let output = buffer.floatChannelData
        else { return }

        try handle.seek(toOffset: range.lowerBound)
        var remaining = Int(range.upperBound - range.lowerBound)

        while remaining > 0 {
            let wanted = min(remaining, Int(framesPerChunk) * AudioFormatSpec.bytesPerFrame)
            guard let data = try handle.read(upToCount: wanted), !data.isEmpty else { break }
            remaining -= data.count

            let frames = data.count / AudioFormatSpec.bytesPerFrame
            guard frames > 0 else { break }
            buffer.frameLength = AVAudioFrameCount(frames)

            data.withUnsafeBytes { raw in
                let samples = raw.bindMemory(to: Int16.self)
                let destination = output[0]
                for index in 0..<frames {
                    destination[index] = Float(samples[index]) / 32_768.0
                }
            }
            try body(buffer)
        }
    }

    /// Envolvente de la senal para dibujar la forma de onda en el informe y en
    /// la interfaz. Se calcula en una pasada y devuelve como mucho `bins`
    /// valores, sin importar lo larga que sea la grabacion.
    func envelope(bins: Int, chunkBytes: Int) throws -> [Float] {
        guard bins > 0, totalBytes > 0 else { return [] }
        let bytesPerBin = max(UInt64(AudioFormatSpec.bytesPerFrame), totalBytes / UInt64(bins))
        var result: [Float] = []
        result.reserveCapacity(bins)

        try handle.seek(toOffset: 0)
        var accumulator: Double = 0
        var samplesInBin = 0
        var bytesInBin: UInt64 = 0

        while result.count < bins {
            guard let data = try handle.read(upToCount: chunkBytes), !data.isEmpty else { break }
            data.withUnsafeBytes { raw in
                let samples = raw.bindMemory(to: Int16.self)
                for sample in samples {
                    let value = Double(sample) / 32_768.0
                    accumulator += value * value
                    samplesInBin += 1
                }
            }
            bytesInBin += UInt64(data.count)
            while bytesInBin >= bytesPerBin && result.count < bins {
                let mean = samplesInBin > 0 ? accumulator / Double(samplesInBin) : 0
                result.append(Float(mean.squareRoot()))
                accumulator = 0
                samplesInBin = 0
                bytesInBin -= bytesPerBin
            }
        }
        if result.count < bins && samplesInBin > 0 {
            result.append(Float((accumulator / Double(samplesInBin)).squareRoot()))
        }
        return result
    }

    func close() {
        try? handle.close()
    }

    deinit {
        try? handle.close()
    }
}

extension FileManager {
    /// Tamaño de un fichero en bytes, o 0 si no existe.
    func fileSizeBytes(at url: URL) -> UInt64 {
        guard let attributes = try? attributesOfItem(atPath: url.path),
              let size = attributes[.size] as? NSNumber
        else { return 0 }
        return size.uint64Value
    }
}
