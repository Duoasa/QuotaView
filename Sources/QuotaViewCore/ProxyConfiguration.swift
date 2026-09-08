import Foundation
import Darwin

/// An app-scoped forward proxy. No credentials or system settings are persisted.
public struct ProxyConfiguration: Codable, Equatable, Sendable {
    public enum Scheme: String, Codable, CaseIterable, Sendable {
        case http
        case socks5
    }

    public enum ValidationError: Error, Equatable, Sendable {
        case invalidHost
        case invalidPort
        case authenticationUnsupported
    }

    public var isEnabled: Bool
    public var scheme: Scheme
    public var host: String
    public var port: String

    public init(isEnabled: Bool = false, scheme: Scheme = .http,
                host: String = "127.0.0.1", port: String = "7890") {
        self.isEnabled = isEnabled
        self.scheme = scheme
        self.host = host
        self.port = port
    }

    public static let `default` = ProxyConfiguration()

    public func validated() throws -> Self {
        var value = self
        value.host = host.trimmingCharacters(in: .whitespacesAndNewlines)
        value.port = port.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.host.contains("@") else {
            throw ValidationError.authenticationUnsupported
        }
        // Accept a bare IPv6 address or its bracketed display form.
        if value.host.hasPrefix("["), value.host.hasSuffix("]") {
            value.host = String(value.host.dropFirst().dropLast())
        }
        var ipv6 = in6_addr()
        let isIPv6 = value.host.withCString { inet_pton(AF_INET6, $0, &ipv6) == 1 }
        let labels = value.host.split(separator: ".", omittingEmptySubsequences: false)
        let isHostname = !value.host.isEmpty && value.host.utf8.count <= 253
            && labels.allSatisfy { label in
                !label.isEmpty && label.utf8.count <= 63
                    && label.first != "-" && label.last != "-"
                    && label.utf8.allSatisfy {
                        (65...90).contains($0) || (97...122).contains($0)
                            || (48...57).contains($0) || $0 == 45
                    }
            }
        guard isIPv6 || isHostname else { throw ValidationError.invalidHost }
        guard !value.port.isEmpty,
              value.port.utf8.allSatisfy({ (48...57).contains($0) }),
              let number = Int(value.port), (1...65535).contains(number)
        else { throw ValidationError.invalidPort }
        value.port = String(number)
        return value
    }

    public func applying(to inherited: [String: String]) throws -> [String: String] {
        guard isEnabled else { return inherited }
        let value = try validated()
        let host = value.host.contains(":") ? "[\(value.host)]" : value.host
        // Remote DNS is necessary when only the proxy can resolve the destination.
        let scheme = value.scheme == .http ? "http" : "socks5h"
        let address = "\(scheme)://\(host):\(value.port)"
        var environment = inherited
        for key in ["HTTP_PROXY", "HTTPS_PROXY", "ALL_PROXY",
                    "http_proxy", "https_proxy", "all_proxy"] {
            environment[key] = address
        }
        for key in ["NO_PROXY", "no_proxy"] {
            environment[key] = "localhost,127.0.0.1,::1"
        }
        return environment
    }
}

public enum ProxyConnectionTestState: Equatable, Sendable {
    case idle
    case testing
    case success
    case failed(ProxyConnectionFailure)
}

public enum ProxyConnectionFailure: Equatable, Sendable {
    case invalidHost, invalidPort, authenticationUnsupported
    case codexNotFound, timedOut, permissionDenied, invalidResponse, connectionFailed

    public static func classify(_ error: Error) -> Self {
        if let error = error as? ProxyConfiguration.ValidationError {
            switch error {
            case .invalidHost: return .invalidHost
            case .invalidPort: return .invalidPort
            case .authenticationUnsupported: return .authenticationUnsupported
            }
        }
        if let error = error as? CodexAppServerClient.ClientError {
            switch error {
            case .executableNotFound: return .codexNotFound
            case .requestTimedOut: return .timedOut
            case .invalidMessage, .messageTooLarge: return .invalidResponse
            case .server(let code, _) where code == 401 || code == 403: return .permissionDenied
            default: return .connectionFailed
            }
        }
        if let error = error as? ProviderError, error == .protocolViolation {
            return .invalidResponse
        }
        return .connectionFailed
    }
}
