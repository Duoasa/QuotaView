import CryptoKit
import Darwin
import Foundation
import XCTest
@testable import QuotaViewCore

final class AuditTransportSharedSocketTests: XCTestCase {
    func testSilentAndPartialUpgradeHaveOneDeadlineAndReleasePeer() async throws {
        for prefix in ["", "HTTP/1.1 101 Switching Protocols\r\n"] {
            let entered=expectation(description:"upgrade request read"),closed=expectation(description:"peer closed within deadline")
            let fixture=try AuditTransportSharedPeer(entered:entered,closed:closed,prefix:prefix)
            defer { fixture.close() }
            let client=CodexSharedAppServerActivityClient(configuration:.init(isEnabled:true,socketURL:fixture.url,executablePath:nil,startupTimeoutSeconds:1))
            let started=DispatchTime.now().uptimeNanoseconds
            await client.start(handler:{ _ in },connectionStateHandler:{ _ in })
            await fulfillment(of:[entered],timeout:2)
            await fulfillment(of:[closed],timeout:2)
            let elapsed=Double(DispatchTime.now().uptimeNanoseconds-started)/1_000_000
            XCTAssertLessThan(elapsed,1_500)
            print("AUDIT017 partialHeader=\(!prefix.isEmpty) deadlineElapsedMs=\(elapsed)")
            await client.stop()
        }
    }
    func testStopDuringUpgradeClosesUnfinishedFDAndNextRunConnects() async throws {
        let entered=expectation(description:"stalled upgrade"),closed=expectation(description:"stop woke peer")
        let fixture=try AuditTransportSharedPeer(entered:entered,closed:closed)
        defer { fixture.close() }
        let client=CodexSharedAppServerActivityClient(configuration:.init(isEnabled:true,socketURL:fixture.url,executablePath:nil,startupTimeoutSeconds:3))
        await client.start(handler:{ _ in },connectionStateHandler:{ _ in })
        await fulfillment(of:[entered],timeout:2)
        await client.stop()
        await fulfillment(of:[closed],timeout:1)
        fixture.enableHealthyMode()
        let connected=expectation(description:"healthy new generation")
        await client.start(handler:{ _ in },connectionStateHandler:{ state in if state == .connected { connected.fulfill() } })
        await fulfillment(of:[connected],timeout:2)
        await client.stop()
    }
    func testBlockedSocketWriteHonorsTotalDeadline() throws {
        var pair = [Int32](repeating: 0, count: 2)
        XCTAssertEqual(socketpair(AF_UNIX, SOCK_STREAM, 0, &pair), 0)
        defer { Darwin.close(pair[0]); Darwin.close(pair[1]) }
        let flags = fcntl(pair[0], F_GETFL)
        XCTAssertEqual(fcntl(pair[0], F_SETFL, flags | O_NONBLOCK), 0)
        var size: Int32 = 1_024
        _ = setsockopt(pair[0], SOL_SOCKET, SO_SNDBUF, &size, socklen_t(MemoryLayout<Int32>.size))
        let started = DispatchTime.now().uptimeNanoseconds
        XCTAssertThrowsError(try CodexSocketOpening.write(Data(repeating: 1, count: 1_048_576), to: pair[0],
            deadline: CodexSocketOpening.deadline(after: 0.05)))
        let elapsed = Double(DispatchTime.now().uptimeNanoseconds - started) / 1_000_000
        XCTAssertLessThan(elapsed, 150)
        print("AUDIT017 blockedWriteMs=\(elapsed)")
    }

    func testRepeatedUpgradeStopClosesEachOwnedDescriptor() async throws {
        let before = try FileManager.default.contentsOfDirectory(atPath: "/dev/fd").count
        let closeResults = AuditTransportOpeningCloseResults()
        for index in 0..<5 {
            let entered = expectation(description: "cycle \(index) entered")
            let closed = expectation(description: "cycle \(index) peer stopped")
            let ownedClosed = expectation(description: "cycle \(index) owned fd closed")
            let fixture = try AuditTransportSharedPeer(entered: entered, closed: closed)
            let client = CodexSharedAppServerActivityClient(configuration: .init(isEnabled: true,
                socketURL: fixture.url, executablePath: nil, startupTimeoutSeconds: 3))
            await client.setOpeningSocketCloseObserver { result in
                closeResults.record(cycle: index, result: result)
                ownedClosed.fulfill()
            }
            await client.start(handler: { _ in }, connectionStateHandler: { _ in })
            await fulfillment(of: [entered], timeout: 2)
            await client.stop()
            await fulfillment(of: [closed, ownedClosed], timeout: 1)
            fixture.close()
        }
        let results = closeResults.values
        XCTAssertEqual(results.count, 5, "Each of the five opening owners must close exactly once")
        XCTAssertEqual(results.map(\.cycle).sorted(), Array(0..<5))
        XCTAssertTrue(results.allSatisfy { $0.result == 0 }, "Each owned descriptor's Darwin.close must succeed")
        let after = try FileManager.default.contentsOfDirectory(atPath: "/dev/fd").count
        // Hosted XCTest opens unrelated resources. Preserve this sample as a
        // metric; the assertions above are scoped to these exact five owners.
        print("AUDIT017 repeatedStopCycles=5 ownedSuccessfulCloses=\(results.filter { $0.result == 0 }.count) descriptorsBefore=\(before) descriptorsAfter=\(after)")
    }

    func testPrivatePathRejectsForeignUIDWritableDirectoryAndSymlink() throws {
        let fixture=try AuditTransportSharedPeer()
        defer { fixture.close() }
        XCTAssertNoThrow(try CodexSocketOpening.verifyPath(fixture.url.path))
        XCTAssertThrowsError(try CodexSocketOpening.verifyPath(fixture.url.path,expectedUID:getuid()+1))
        try FileManager.default.setAttributes([.posixPermissions:0o770],ofItemAtPath:fixture.url.deletingLastPathComponent().path)
        XCTAssertThrowsError(try CodexSocketOpening.verifyPath(fixture.url.path))
        try FileManager.default.setAttributes([.posixPermissions:0o700],ofItemAtPath:fixture.url.deletingLastPathComponent().path)
        let link=fixture.url.deletingLastPathComponent().appendingPathComponent("link.sock")
        try FileManager.default.createSymbolicLink(at:link,withDestinationURL:fixture.url)
        XCTAssertThrowsError(try CodexSocketOpening.verifyPath(link.path))
    }
    func testSocketReplacementDuringUpgradeNeverPublishesConnectedAuthority() async throws {
        let entered=expectation(description:"upgrade entered"),closed=expectation(description:"replaced source closed")
        let fixture=try AuditTransportSharedPeer(entered:entered,closed:closed)
        defer { fixture.close() }
        let statuses=AuditTransportSharedStatuses()
        let client=CodexSharedAppServerActivityClient(configuration:.init(isEnabled:true,socketURL:fixture.url,executablePath:nil,startupTimeoutSeconds:2))
        await client.start(handler:{ _ in },connectionStateHandler:{ state in statuses.record(state) })
        await fulfillment(of:[entered],timeout:2)
        try fixture.replacePathAndCompleteUpgrade()
        await fulfillment(of:[closed],timeout:2)
        await client.stop()
        XCTAssertFalse(statuses.connected)
    }
}

private final class AuditTransportOpeningCloseResults: @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [(cycle: Int, result: Int32)] = []
    func record(cycle: Int, result: Int32) { lock.withLock { recorded.append((cycle, result)) } }
    var values: [(cycle: Int, result: Int32)] { lock.withLock { recorded } }
}

private final class AuditTransportSharedStatuses: @unchecked Sendable {
    private let lock=NSLock();private var values:[CodexSharedAppServerConnectionState]=[]
    func record(_ value:CodexSharedAppServerConnectionState){lock.withLock{values.append(value)}}
    var connected:Bool{lock.withLock{values.contains(.connected)}}
}
private final class AuditTransportSharedPeer: @unchecked Sendable {
    let url:URL
    private let directory:URL
    private let listener:Int32
    private let lock=NSLock()
    private let workerEnded = DispatchGroup()
    private var accepted:Int32 = -1
    private var healthy=false
    private var ended=false
    private var key=""
    private var replacementFD:Int32 = -1
    private let entered:XCTestExpectation?
    private let closed:XCTestExpectation?
    private let prefix:String
    init(entered:XCTestExpectation?=nil,closed:XCTestExpectation?=nil,prefix:String="") throws {
        self.entered=entered;self.closed=closed;self.prefix=prefix
        directory=URL(fileURLWithPath:"/private/tmp/qvs-\(UUID().uuidString.prefix(8))")
        try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true,attributes:[.posixPermissions:0o700])
        url=directory.appendingPathComponent("s.sock")
        listener=try Self.listen(url)
        workerEnded.enter()
        DispatchQueue.global(qos:.utility).async{[self] in defer { workerEnded.leave() }; serve()}
    }
    func enableHealthyMode(){lock.withLock{healthy=true}}
    func replacePathAndCompleteUpgrade() throws {
        try FileManager.default.moveItem(at:url,to:directory.appendingPathComponent("old.sock"))
        let fresh=try Self.listen(url)
        try lock.withLock{replacementFD=fresh;try upgrade(accepted,key:key)}
    }
    func close(){
        lock.lock();guard !ended else{lock.unlock();return};ended=true
        let fd=accepted;let extra=replacementFD;lock.unlock()
        if fd>=0{_ = Darwin.shutdown(fd,SHUT_RDWR)}
        _ = Darwin.shutdown(listener,SHUT_RDWR);Darwin.close(listener)
        if extra>=0{Darwin.close(extra)}
        _ = workerEnded.wait(timeout: .now() + 1)
        try? FileManager.default.removeItem(at:directory)
    }
    private func serve(){
        var first=true
        while !lock.withLock({ended}){
            let fd=Darwin.accept(listener,nil,nil)
            if fd<0{return}
            var noSignal:Int32=1;setsockopt(fd,SOL_SOCKET,SO_NOSIGPIPE,&noSignal,socklen_t(MemoryLayout<Int32>.size))
            lock.withLock{accepted=fd}
            do{
                var request=Data(),byte:UInt8=0
                while request.range(of:Data([13,10,13,10])) == nil {
                    guard Darwin.read(fd,&byte,1)==1 else{throw CodexDesktopIPCError.unavailable}
                    request.append(byte)
                }
                let header=String(decoding:request,as:UTF8.self)
                let value=header.components(separatedBy:"\r\n").first{$0.hasPrefix("Sec-WebSocket-Key:")}?.components(separatedBy:":").last?.trimmingCharacters(in:.whitespaces) ?? ""
                lock.withLock{key=value}
                if first{entered?.fulfill()}
                if lock.withLock({healthy}){
                    try upgrade(fd,key:value)
                    while true{
                        let payload=try readClientFrame(fd)
                        let message=try XCTUnwrap(JSONSerialization.jsonObject(with:payload) as? [String:Any])
                        guard let id=message["id"] else{continue}
                        let method=message["method"] as? String
                        let result:[String:Any]=method == "thread/loaded/list" ? ["data":[]] : [:]
                        try write(fd,frame(try JSONSerialization.data(withJSONObject:["id":id,"result":result])))
                    }
                }else{
                    if !prefix.isEmpty{try write(fd,Data(prefix.utf8))}
                    while Darwin.read(fd,&byte,1)>0{}
                }
            }catch{}
            lock.withLock{if accepted==fd{accepted = -1}}
            Darwin.close(fd)
            if first{closed?.fulfill();first=false}
        }
    }
    private func upgrade(_ fd:Int32,key:String)throws{
        let accept=Data(Insecure.SHA1.hash(data:Data((key+"258EAFA5-E914-47DA-95CA-C5AB0DC85B11").utf8))).base64EncodedString()
        let response="HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Accept: \(accept)\r\n\r\n"
        try write(fd,Data(response.utf8))
    }
    private func readClientFrame(_ fd:Int32)throws->Data{
        let head=try read(fd,2)
        var count=Int(head[1]&127)
        if count==126{let size=try read(fd,2);count=Int(size[0])*256+Int(size[1])}
        else if count==127{let size=try read(fd,8);count=size.reduce(0){$0*256+Int($1)}}
        guard count<=1_048_576 else{throw CodexDesktopIPCError.resourceLimit}
        let mask=try read(fd,4),body=try read(fd,count)
        return Data(body.enumerated().map{$0.element ^ mask[$0.offset%4]})
    }
    private func read(_ fd:Int32,_ count:Int)throws->Data{
        var data=Data(),bytes=[UInt8](repeating:0,count:max(1,count))
        while data.count<count{let n=Darwin.read(fd,&bytes,count-data.count);guard n>0 else{throw CodexDesktopIPCError.unavailable};data.append(bytes,count:n)}
        return data
    }
    private func write(_ fd:Int32,_ data:Data)throws{
        try data.withUnsafeBytes{bytes in
            var offset=0
            while offset<bytes.count{let n=Darwin.write(fd,bytes.baseAddress!.advanced(by:offset),bytes.count-offset);guard n>0 else{throw CodexDesktopIPCError.unavailable};offset+=n}
        }
    }
    private func frame(_ payload:Data)->Data{
        var data=Data([0x81])
        if payload.count<126{data.append(UInt8(payload.count))}
        else{data.append(contentsOf:[126,UInt8(payload.count>>8),UInt8(payload.count&255)])}
        return data+payload
    }
    private static func listen(_ url:URL)throws->Int32{
        let fd=Darwin.socket(AF_UNIX,SOCK_STREAM,0)
        guard fd>=0 else{throw CodexDesktopIPCError.unavailable}
        var address=sockaddr_un();address.sun_family=sa_family_t(AF_UNIX);address.sun_len=UInt8(MemoryLayout<sockaddr_un>.size)
        let bytes=Array(url.path.utf8)+[0]
        withUnsafeMutableBytes(of:&address.sun_path){$0.copyBytes(from:bytes)}
        let result=withUnsafePointer(to:&address){$0.withMemoryRebound(to:sockaddr.self,capacity:1){Darwin.bind(fd,$0,socklen_t(MemoryLayout<sockaddr_un>.size))}}
        guard result==0,Darwin.listen(fd,8)==0 else{Darwin.close(fd);throw CodexDesktopIPCError.unavailable}
        return fd
    }
}
