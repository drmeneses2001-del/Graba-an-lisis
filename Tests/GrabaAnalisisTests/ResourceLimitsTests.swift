import XCTest
@testable import GrabaAnalisis

final class ResourceLimitsTests: XCTestCase {

    func testBaselinesGrowWithDeviceClass() {
        let compact = ResourceLimits.baseline(for: .compact)
        let standard = ResourceLimits.baseline(for: .standard)
        let pro = ResourceLimits.baseline(for: .pro)

        XCTAssertLessThan(compact.maxSessionSeconds, standard.maxSessionSeconds)
        XCTAssertLessThan(standard.maxSessionSeconds, pro.maxSessionSeconds)
        XCTAssertLessThan(compact.maxAudioBytes, standard.maxAudioBytes)
        XCTAssertLessThan(compact.maxTranscriptCharsInMemory, pro.maxTranscriptCharsInMemory)
        XCTAssertLessThanOrEqual(compact.maxConcurrentTranscriptions, pro.maxConcurrentTranscriptions)
    }

    func testDegradedLimitsNeverExceedBaseline() {
        for deviceClass in DeviceClass.allCases {
            let baseline = ResourceLimits.baseline(for: deviceClass)
            let degraded = baseline.degraded()
            XCTAssertLessThanOrEqual(degraded.transcriptionWindowSeconds, baseline.transcriptionWindowSeconds)
            XCTAssertLessThanOrEqual(degraded.audioReadChunkBytes, baseline.audioReadChunkBytes)
            XCTAssertLessThanOrEqual(degraded.maxTranscriptCharsInMemory, baseline.maxTranscriptCharsInMemory)
            XCTAssertLessThanOrEqual(degraded.analysisChunkChars, baseline.analysisChunkChars)
            XCTAssertLessThanOrEqual(degraded.maxChartPoints, baseline.maxChartPoints)
            XCTAssertEqual(degraded.maxConcurrentTranscriptions, 1)
        }
    }

    func testDegradedLimitsKeepFunctionalFloor() {
        let degraded = ResourceLimits.baseline(for: .compact).degraded().degraded().degraded()
        XCTAssertGreaterThanOrEqual(degraded.transcriptionWindowSeconds, 20)
        XCTAssertGreaterThanOrEqual(degraded.analysisChunkChars, 6_000)
        XCTAssertGreaterThanOrEqual(degraded.maxChartPoints, 20)
    }

    func testFootprintIsReadable() {
        XCTAssertGreaterThan(MemoryReporter.footprintBytes(), 0)
    }

    func testAudioFormatArithmetic() {
        XCTAssertEqual(AudioFormatSpec.bytesPerSecondPerTrack, 32_000)
        XCTAssertEqual(AudioFormatSpec.seconds(fromBytes: 1_920_000), 60, accuracy: 0.0001)
        XCTAssertEqual(AudioFormatSpec.bytes(forSeconds: 1), 32_000)
    }
}
