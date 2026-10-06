import Darwin
import Foundation
import XCTest
@testable import QuotaViewCore

final class AuditTransportLifecycleTests: XCTestCase {
    func testCLIInitializationIsSharedByTenCallersAndCallerCancellationIsIsolated() async throws {
        let fixture = try AuditTransportCLIProcess()
        defer { fixture.remove() }
        let client = CodexAppServerClient(executablePath: fixture.executable.path, startupTimeoutSeconds: 3, requestTimeoutSeconds: 2)
        let joined = expectation(description: "nine callers joined the same initialization")
        joined.expectedFulfillmentCount = 9
        await client.setInitializationJoinObserver { joined.fulfill() }
        let first = Task { try await client.fetchThreadDisplayName(matchingSessionHash: CodexActivityPrivacy.hashIdentifier("thread")) }
        try await fixture.waitForInitialize()
        let others = (0..<9).map { _ in Task { try await client.fetchThreadDisplayName(matchingSessionHash: CodexActivityPrivacy.hashIdentifier("thread")) } }
        await fulfillment(of: [joined], timeout: 3)
        first.cancel()
        try fixture.release()
        do { _ = try await first.value; XCTFail("cancelled waiter succeeded") } catch { }
        for task in others { let value = try await task.value; XCTAssertEqual(value, "Fixture") }
        XCTAssertEqual(try fixture.launchCount(), 1)
        let next = try await client.fetchThreadDisplayName(matchingSessionHash: CodexActivityPrivacy.hashIdentifier("thread"))
        XCTAssertEqual(next, "Fixture")
        await client.stop()
    }

    func testExplicitStopAndOldInitializationFailureCannotStopNewGeneration() async throws {
        let fixture = try AuditTransportCLIProcess()
        defer { fixture.remove() }
        let client = CodexAppServerClient(executablePath: fixture.executable.path, startupTimeoutSeconds: 3, requestTimeoutSeconds: 2)
        let first = Task { try await client.fetchThreadDisplayName(matchingSessionHash: CodexActivityPrivacy.hashIdentifier("thread")) }
        try await fixture.waitForInitialize()
        await client.stop()
        let second = Task { try await client.fetchThreadDisplayName(matchingSessionHash: CodexActivityPrivacy.hashIdentifier("thread")) }
        try await fixture.waitForInitialize()
        try fixture.release()
        do { _ = try await first.value; XCTFail("stopped generation succeeded") } catch { }
        let secondValue = try await second.value
        XCTAssertEqual(secondValue, "Fixture")
        XCTAssertEqual(try fixture.launchCount(), 2)
        let next = try await client.fetchThreadDisplayName(matchingSessionHash: CodexActivityPrivacy.hashIdentifier("thread"))
        XCTAssertEqual(next, "Fixture")
        await client.stop()
    }

    func testAcknowledgedReaderBoundsQueueAndRetainsOrderedTerminalBytes() async throws {
        let pipe = Pipe()
        let reader = CodexBoundedInputReader(handle: pipe.fileHandleForReading)
        let terminal = Data("<terminal-control>".utf8)
        let payload = Data((0..<2_097_152).map { UInt8(truncatingIfNeeded: $0) }) + terminal
        let rssBefore = residentBytes()
        let finished = expectation(description: "producer finished")
        let writer = Task.detached {
            defer { try? pipe.fileHandleForWriting.close(); finished.fulfill() }
            try pipe.fileHandleForWriting.write(contentsOf: payload)
        }
        var iterator = reader.chunks.makeAsyncIterator()
        let nextChunk = await iterator.next()
        let first = try XCTUnwrap(nextChunk)
        let stalled = reader.metrics
        let rssPaused = residentBytes()
        XCTAssertEqual(stalled.queuedBytes,first.count)
        XCTAssertLessThanOrEqual(stalled.highWaterBytes,CodexBoundedInputReader.maximumChunkBytes)
        var received = first
        reader.acknowledgeRead()
        let start = DispatchTime.now().uptimeNanoseconds
        while let chunk = await iterator.next() { received.append(chunk); reader.acknowledgeRead() }
        try await writer.value
        await fulfillment(of: [finished], timeout: 2)
        XCTAssertEqual(received,payload)
        print("AUDIT010 pausedQueued=\(stalled.queuedBytes) highWater=\(reader.metrics.highWaterBytes) received=\(received.count) terminalDrainMs=\(Double(DispatchTime.now().uptimeNanoseconds-start)/1_000_000) rssPausedDeltaBytes=\(Int64(rssPaused)-Int64(rssBefore))")
        reader.close()
    }

    private func residentBytes() -> UInt64 {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        return result == KERN_SUCCESS ? UInt64(info.resident_size) : 0
    }

    func testClosingReaderWakesProducerAndConsumerWithoutAcknowledgement() async throws {
        var pair = [Int32](repeating: 0, count: 2)
        XCTAssertEqual(socketpair(AF_UNIX, SOCK_STREAM, 0, &pair), 0)
        let reader = CodexBoundedInputReader(handle: FileHandle(fileDescriptor: pair[0], closeOnDealloc: true), isSocket: true)
        let peer = FileHandle(fileDescriptor: pair[1], closeOnDealloc: true)
        try peer.write(contentsOf: Data([1,2,3]))
        var iterator = reader.chunks.makeAsyncIterator()
        let firstChunk = await iterator.next()
        XCTAssertNotNil(firstChunk)
        reader.close()
        let closedChunk = await iterator.next()
        XCTAssertNil(closedChunk)
        var byte: UInt8 = 0
        XCTAssertEqual(Darwin.read(pair[1], &byte, 1), 0)
        try peer.close()
    }
}

private final class AuditTransportCLIProcess {
    let directory: URL
    let executable: URL
    private let entered: URL
    private let releaseFIFO: URL
    private let launches: URL
    init() throws {
        directory = URL(fileURLWithPath: "/private/tmp/qva-\(UUID().uuidString.prefix(8))")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        executable = directory.appendingPathComponent("server.py")
        entered = directory.appendingPathComponent("entered")
        releaseFIFO = directory.appendingPathComponent("release")
        launches = directory.appendingPathComponent("launches")
        guard mkfifo(entered.path, 0o600) == 0, mkfifo(releaseFIFO.path, 0o600) == 0 else { throw CodexDesktopIPCError.unavailable }
        let script = """
        #!/usr/bin/python3
        import json, os, sys
        with open(\(String(reflecting: launches.path)), 'a') as f: f.write(str(os.getpid())+'\\n')
        for line in sys.stdin:
            m=json.loads(line)
            if m.get('method') == 'initialize':
                with open(\(String(reflecting: entered.path)), 'w') as f: f.write('entered\\n')
                with open(\(String(reflecting: releaseFIFO.path)), 'r') as f: f.readline()
                print(json.dumps({'id':m['id'],'result':{}}),flush=True)
            elif m.get('method') == 'thread/list':
                print(json.dumps({'id':m['id'],'result':{'data':[{'id':'thread','name':'Fixture'}]}}),flush=True)
        """
        try script.write(to: executable, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)
    }
    func waitForInitialize() async throws {
        let path = entered.path
        try await Task.detached {
            let fd = Darwin.open(path,O_RDONLY)
            guard fd >= 0 else { throw CodexDesktopIPCError.unavailable }
            defer { Darwin.close(fd) }
            var bytes = [UInt8](repeating: 0,count: 32)
            guard Darwin.read(fd,&bytes,bytes.count) > 0 else { throw CodexDesktopIPCError.unavailable }
        }.value
    }
    func release() throws {
        let fd = Darwin.open(releaseFIFO.path,O_WRONLY)
        guard fd >= 0 else { throw CodexDesktopIPCError.unavailable }
        defer { Darwin.close(fd) }
        var byte: UInt8 = 10
        guard Darwin.write(fd,&byte,1) == 1 else { throw CodexDesktopIPCError.unavailable }
    }
    func launchCount() throws -> Int { try String(contentsOf: launches, encoding: .utf8).split(separator: "\n").count }
    func remove() { try? FileManager.default.removeItem(at: directory) }
}
