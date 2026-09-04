import Foundation
import AVFoundation
import CoreMedia

/// Convierte los `CMSampleBuffer` que entrega ReplayKit al formato canonico de
/// la app (16 kHz mono Int16) sin acumular nada entre llamadas.
///
/// Se crea un conversor por formato de entrada y se reutiliza; el buffer de
/// salida tambien se reutiliza. En regimen estable esta clase no reserva
/// memoria en absoluto, que es el requisito para vivir dentro del limite de la
/// extension de difusion.
final class SampleBufferConverter {

    private static let maximumBuffers = 8

    private var converter: AVAudioConverter?
    private var inputFormat: AVAudioFormat?
    private var outputBuffer: AVAudioPCMBuffer?
    private let outputFormat = AudioFormatSpec.processingFormat
    /// Lista de buffers reservada una sola vez; admite hasta ocho canales no
    /// entrelazados, mas de lo que ReplayKit entrega nunca.
    private let bufferList = AudioBufferList.allocate(maximumBuffers: SampleBufferConverter.maximumBuffers)

    deinit {
        free(bufferList.unsafeMutablePointer)
    }

    /// Convierte un sample buffer y entrega los bytes resultantes al bloque.
    /// Los bytes solo son validos dentro del bloque.
    func convert(_ sampleBuffer: CMSampleBuffer,
                 into body: (UnsafeRawBufferPointer) -> Void) {
        autoreleasepool {
            guard let formatDescription = CMSampleBufferGetFormatDescription(sampleBuffer),
                  let asbdPointer = CMAudioFormatDescriptionGetStreamBasicDescription(formatDescription)
            else { return }

            var asbd = asbdPointer.pointee
            if inputFormat == nil || inputFormat?.streamDescription.pointee.mSampleRate != asbd.mSampleRate
                || inputFormat?.streamDescription.pointee.mChannelsPerFrame != asbd.mChannelsPerFrame {
                guard let format = AVAudioFormat(streamDescription: &asbd) else { return }
                inputFormat = format
                converter = AVAudioConverter(from: format, to: outputFormat)
                converter?.sampleRateConverterQuality = AVAudioQuality.medium.rawValue
                outputBuffer = nil
            }

            guard let inputFormat, let converter else { return }

            var blockBuffer: CMBlockBuffer?
            let status = CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
                sampleBuffer,
                bufferListSizeNeededOut: nil,
                bufferListOut: bufferList.unsafeMutablePointer,
                bufferListSize: AudioBufferList.sizeInBytes(maximumBuffers: Self.maximumBuffers),
                blockBufferAllocator: nil,
                blockBufferMemoryAllocator: nil,
                flags: kCMSampleBufferFlag_AudioBufferList_Assure16ByteAlignment,
                blockBufferOut: &blockBuffer)
            // `blockBuffer` mantiene vivos los datos hasta que termina la
            // conversion; no se toca, pero tiene que existir.
            guard status == noErr, blockBuffer != nil else { return }

            guard let inputBuffer = AVAudioPCMBuffer(pcmFormat: inputFormat,
                                                     bufferListNoCopy: bufferList.unsafeMutablePointer,
                                                     deallocator: nil)
            else { return }

            let ratio = outputFormat.sampleRate / inputFormat.sampleRate
            let capacity = AVAudioFrameCount(Double(inputBuffer.frameLength) * ratio) + 64
            if outputBuffer == nil || outputBuffer!.frameCapacity < capacity {
                outputBuffer = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: capacity)
            }
            guard let outputBuffer else { return }
            outputBuffer.frameLength = 0

            var consumed = false
            var error: NSError?
            _ = converter.convert(to: outputBuffer, error: &error) { _, statusPointer in
                if consumed {
                    statusPointer.pointee = .noDataNow
                    return nil
                }
                consumed = true
                statusPointer.pointee = .haveData
                return inputBuffer
            }
            guard error == nil, outputBuffer.frameLength > 0,
                  let channelData = outputBuffer.int16ChannelData
            else { return }

            let byteCount = Int(outputBuffer.frameLength) * AudioFormatSpec.bytesPerFrame
            let raw = UnsafeRawBufferPointer(start: channelData[0], count: byteCount)
            body(raw)
        }
    }
}
