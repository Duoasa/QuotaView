import Foundation
import Network

/// A loopback-only HTTP forward proxy for Codex builds without native SOCKS support.
/// HTTPS remains end-to-end encrypted: CONNECT bytes are relayed without inspection.
final class SOCKS5HTTPBridge: @unchecked Sendable {
    private let queue = DispatchQueue(label: "com.quotaview.socks-bridge")
    private var listener: NWListener?
    private var sessions: [UUID: SOCKSBridgeSession] = [:]
    private var startContinuation: CheckedContinuation<UInt16, Error>?
    private var stopped = false

    func start(configuration: ProxyConfiguration) async throws -> UInt16 {
        let value = try configuration.validated()
        return try await withCheckedThrowingContinuation { continuation in
            queue.async {
                guard !self.stopped else {
                    continuation.resume(throwing: CodexAppServerClient.ClientError.cancelled)
                    return
                }
                self.startContinuation = continuation
                do {
                    let parameters = NWParameters.tcp
                    parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
                    let listener = try NWListener(using: parameters)
                    self.listener = listener
                    listener.stateUpdateHandler = { [weak self] state in
                        guard let self else { return }
                        switch state {
                        case .ready:
                            if let port = listener.port?.rawValue {
                                self.finishStart(.success(port))
                            }
                        case .failed, .cancelled:
                            self.finishStart(.failure(CodexAppServerClient.ClientError.connectionClosed))
                        default: break
                        }
                    }
                    listener.newConnectionHandler = { [weak self] connection in
                        guard let self, !self.stopped, self.sessions.count < 16 else {
                            connection.cancel()
                            return
                        }
                        let id = UUID()
                        let session = SOCKSBridgeSession(
                            incoming: connection, proxy: value, queue: self.queue
                        ) { [weak self] in self?.sessions.removeValue(forKey: id) }
                        self.sessions[id] = session
                        session.start()
                    }
                    listener.start(queue: self.queue)
                    self.queue.asyncAfter(deadline: .now() + 5) { [weak self] in
                        guard let self, self.startContinuation != nil else { return }
                        self.finishStart(.failure(CodexAppServerClient.ClientError.requestTimedOut("proxy")))
                        self.stopOnQueue()
                    }
                } catch {
                    self.finishStart(.failure(CodexAppServerClient.ClientError.connectionClosed))
                }
            }
        }
    }

    func stop() {
        queue.async { self.stopOnQueue() }
    }

    private func finishStart(_ result: Result<UInt16, Error>) {
        let continuation = startContinuation
        startContinuation = nil
        continuation?.resume(with: result)
    }

    private func stopOnQueue() {
        guard !stopped else { return }
        stopped = true
        finishStart(.failure(CodexAppServerClient.ClientError.cancelled))
        listener?.stateUpdateHandler = nil
        listener?.newConnectionHandler = nil
        listener?.cancel()
        listener = nil
        let active = Array(sessions.values)
        sessions.removeAll()
        active.forEach { $0.stop() }
    }
}

private final class SOCKSBridgeSession {
    private let incoming: NWConnection
    private var outgoing: NWConnection?
    private let proxy: ProxyConfiguration
    private let queue: DispatchQueue
    private let onStop: () -> Void
    private var timer: DispatchSourceTimer?
    private var header = Data()
    private var stopped = false
    private var tunnel = false
    private var initialPayload = Data()

    init(incoming: NWConnection, proxy: ProxyConfiguration,
         queue: DispatchQueue, onStop: @escaping () -> Void) {
        self.incoming = incoming
        self.proxy = proxy
        self.queue = queue
        self.onStop = onStop
    }

    func start() {
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.setEventHandler { [weak self] in self?.stop() }
        timer.schedule(deadline: .now() + 10)
        timer.resume()
        self.timer = timer
        incoming.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            switch state {
            case .ready: self.readHeader()
            case .failed, .cancelled: self.stop()
            default: break
            }
        }
        incoming.start(queue: queue)
    }

    func stop() {
        guard !stopped else { return }
        stopped = true
        timer?.cancel()
        timer = nil
        incoming.stateUpdateHandler = nil
        outgoing?.stateUpdateHandler = nil
        incoming.cancel()
        outgoing?.cancel()
        outgoing = nil
        header.removeAll()
        initialPayload.removeAll()
        onStop()
    }

    private func readHeader() {
        incoming.receive(minimumIncompleteLength: 1, maximumLength: 16_384) { [weak self] data, _, done, error in
            guard let self, !self.stopped else { return }
            guard let data, !data.isEmpty, error == nil else { self.stop(); return }
            self.header.append(data)
            guard self.header.count <= 65_536 else { self.stop(); return }
            if let boundary = self.header.range(of: Data("\r\n\r\n".utf8)) {
                self.openSOCKS(headerEnd: boundary.upperBound)
            } else if done { self.stop() }
            else { self.readHeader() }
        }
    }

    private func openSOCKS(headerEnd: Int) {
        guard let text = String(data: header.prefix(headerEnd), encoding: .utf8) else { stop(); return }
        let lines = text.components(separatedBy: "\r\n")
        let first = (lines.first ?? "").split(separator: " ", omittingEmptySubsequences: true)
        guard first.count == 3, first[2].hasPrefix("HTTP/1.") else { stop(); return }
        tunnel = first[0] == "CONNECT"
        let target = String(first[1])
        let components = URLComponents(string: tunnel ? "http://\(target)" : target)
        guard let components, let rawHost = components.host,
              components.user == nil, components.password == nil,
              let port = tunnel ? components.port : (components.port ?? 80),
              (1...65535).contains(port), tunnel || components.scheme == "http"
        else { stop(); return }
        let host = rawHost.hasPrefix("[") && rawHost.hasSuffix("]")
            ? String(rawHost.dropFirst().dropLast()) : rawHost
        guard !host.isEmpty, host.utf8.count <= 255 else { stop(); return }
        let body = Data(header.dropFirst(headerEnd))
        if tunnel {
            initialPayload = body
        } else {
            let path = components.percentEncodedPath.isEmpty ? "/" : components.percentEncodedPath
            let query = components.percentEncodedQuery.map { "?\($0)" } ?? ""
            var request = "\(first[0]) \(path)\(query) \(first[2])\r\n"
            for line in lines.dropFirst() where !line.isEmpty {
                let lower = line.lowercased()
                if lower.hasPrefix("proxy-connection:") || lower.hasPrefix("proxy-authorization:")
                    || lower.hasPrefix("connection:") { continue }
                request += line + "\r\n"
            }
            // One destination per connection. Never pool a plain-HTTP socket across hosts.
            request += "Connection: close\r\n\r\n"
            initialPayload = Data(request.utf8) + body
        }
        header.removeAll()
        guard let proxyPort = UInt16(proxy.port), let nwPort = NWEndpoint.Port(rawValue: proxyPort) else { stop(); return }
        let outgoing = NWConnection(host: NWEndpoint.Host(proxy.host), port: nwPort, using: .tcp)
        self.outgoing = outgoing
        outgoing.stateUpdateHandler = { [weak self] state in
            guard let self, !self.stopped else { return }
            switch state {
            case .ready: self.handshake(host: host, port: UInt16(port))
            case .failed, .cancelled: self.stop()
            default: break
            }
        }
        outgoing.start(queue: queue)
    }

    private func handshake(host: String, port: UInt16) {
        guard let outgoing else { stop(); return }
        send(Data([5, 1, 0]), to: outgoing) { [weak self] in
            self?.readExactly(2, from: outgoing) { [weak self] bytes in
                guard let self else { return }
                guard bytes == Data([5, 0]) else { self.stop(); return }
                // Domain address form delegates DNS to the SOCKS5 server.
                let destination = Data(host.utf8)
                let request = Data([5, 1, 0, 3, UInt8(destination.count)]) + destination
                    + Data([UInt8(port >> 8), UInt8(port & 255)])
                self.send(request, to: outgoing) { [weak self] in
                    self?.readExactly(4, from: outgoing) { [weak self] reply in
                        guard let self else { return }
                        guard reply[0] == 5, reply[1] == 0, reply[2] == 0 else { self.stop(); return }
                        switch reply[3] {
                        case 1: self.finishHandshake(addressBytes: 6)
                        case 4: self.finishHandshake(addressBytes: 18)
                        case 3:
                            self.readExactly(1, from: outgoing) { [weak self] count in
                                self?.finishHandshake(addressBytes: Int(count[0]) + 2)
                            }
                        default: self.stop()
                        }
                    }
                }
            }
        }
    }

    private func finishHandshake(addressBytes: Int) {
        guard let outgoing else { stop(); return }
        readExactly(addressBytes, from: outgoing) { [weak self] _ in
            guard let self, !self.stopped else { return }
            if self.tunnel {
                self.send(Data("HTTP/1.1 200 Connection Established\r\n\r\n".utf8), to: self.incoming) { [weak self] in
                    self?.startRelay()
                }
            } else { self.startRelay() }
        }
    }

    private func startRelay() {
        guard let outgoing, !stopped else { return }
        timer?.schedule(deadline: .now() + 60)
        let initial = initialPayload
        initialPayload.removeAll()
        send(initial, to: outgoing) { [weak self] in
            self?.relay(from: self?.incoming, to: outgoing)
            self?.relay(from: outgoing, to: self?.incoming)
        }
    }

    private func readExactly(_ count: Int, from connection: NWConnection,
                             completion: @escaping (Data) -> Void) {
        connection.receive(minimumIncompleteLength: count, maximumLength: count) { [weak self] data, _, _, error in
            guard let self, !self.stopped else { return }
            guard error == nil, let data, data.count == count else { self.stop(); return }
            completion(data)
        }
    }

    private func send(_ data: Data, to connection: NWConnection, then completion: @escaping () -> Void) {
        guard !stopped else { return }
        guard !data.isEmpty else { completion(); return }
        connection.send(content: data, completion: .contentProcessed { [weak self] error in
            guard let self, !self.stopped else { return }
            guard error == nil else { self.stop(); return }
            completion()
        })
    }

    private func relay(from source: NWConnection?, to destination: NWConnection?) {
        guard let source, let destination, !stopped else { return }
        source.receive(minimumIncompleteLength: 1, maximumLength: 32_768) { [weak self] data, _, done, error in
            guard let self, !self.stopped else { return }
            guard error == nil else { self.stop(); return }
            self.timer?.schedule(deadline: .now() + 60)
            self.send(data ?? Data(), to: destination) { [weak self] in
                guard let self else { return }
                if done { self.stop() }
                else { self.relay(from: source, to: destination) }
            }
        }
    }
}
