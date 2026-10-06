import Foundation
import XCTest
@testable import QuotaViewCore

final class AuditTransportWebSocketTests: XCTestCase {
    func testSplitFramesCopyOnlyPayloadOnceAndCoalescedCompactionIsLinear() throws {
        for chunkSize in [1, 4_096, 65_536, 2_000_000] {
            let payload = Data(repeating: 97, count: chunkSize == 1 ? 4_096 : 1_048_576)
            let input = frame(payload)
            var decoder = CodexAppServerWebSocketMessageDecoder()
            var events: [CodexAppServerWebSocketEvent] = []
            for offset in stride(from: 0, to: input.count, by: chunkSize) {
                events += try decoder.append(Data(input[offset..<min(input.count, offset + chunkSize)]))
            }
            XCTAssertEqual(events, [.text(payload)])
            XCTAssertEqual(decoder.copiedPayloadBytes,payload.count)
            XCTAssertTrue(decoder.buffer.isEmpty)
            print("AUDIT012 chunk=\(chunkSize) input=\(input.count) payloadCopied=\(decoder.copiedPayloadBytes) compacted=\(decoder.compactedBytes)")
        }
        let payload = Data(repeating: 98, count: 1_024)
        let input = (0..<256).reduce(into: Data()) { result, _ in result.append(frame(payload)) }
        var decoder = CodexAppServerWebSocketMessageDecoder()
        XCTAssertEqual(try decoder.append(input), Array(repeating: .text(payload), count: 256))
        XCTAssertLessThanOrEqual(decoder.compactedBytes,input.count)
        XCTAssertEqual(decoder.copiedPayloadBytes,256 * payload.count)
    }
    func testFragmentControlValidationAndReconnectReset() throws {
        var decoder = CodexAppServerWebSocketMessageDecoder()
        let first = frame(Data("a".utf8), opcode: 1, final: false)
        let ping = frame(Data("p".utf8), opcode: 9)
        let last = frame(Data("b".utf8), opcode: 0)
        XCTAssertEqual(try decoder.append(first + ping + last + frame(Data(), opcode: 8)), [.ping(Data("p".utf8)), .text(Data("ab".utf8)), .close])
        decoder = .init()
        XCTAssertThrowsError(try decoder.append(frame(Data(), opcode: 0)))
        decoder = .init()
        XCTAssertThrowsError(try decoder.append(frame(Data(repeating: 0, count: 126), opcode: 9)))
        decoder = .init()
        XCTAssertThrowsError(try decoder.append(Data([0x81, 0xFF, 0, 0, 0, 0, 0, 0x20, 0, 0])))
    }
    private func frame(_ data: Data, opcode: UInt8 = 1, final: Bool = true) -> Data {
        var result = Data([(final ? 0x80 : 0) | opcode])
        if data.count < 126 { result.append(UInt8(data.count)) }
        else if data.count <= 65_535 { result.append(contentsOf: [126, UInt8(data.count >> 8), UInt8(data.count & 255)]) }
        else { result.append(127); for shift in stride(from: 56, through: 0, by: -8) { result.append(UInt8(truncatingIfNeeded: UInt64(data.count) >> shift)) } }
        result.append(data); return result
    }
}
