import Foundation
import SQLite3
import LocalAuthentication
import Security
import Yams

private final class QuotaHTTPDelegate: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

/// An opt-in account read. Only the report leaves this client. Services do not share a cookie jar.
struct NativeQuotaClient {
    typealias Object = NativeQuotaResponse.Object
    typealias Loader = (URLRequest) async throws -> Data
    private static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.urlCache = nil
        config.httpCookieStorage = nil
        config.urlCredentialStorage = nil
        config.httpShouldSetCookies = false
        config.timeoutIntervalForRequest = 10
        config.timeoutIntervalForResource = 15
        return URLSession(configuration: config, delegate: QuotaHTTPDelegate(), delegateQueue: nil)
    }()

    let home: URL
    let environment: [String: String]
    let load: Loader
    let readSecret: (String, Bool) -> String?
    let allowCredentialPrompt: Bool
    init(home: URL = FileManager.default.homeDirectoryForCurrentUser,
         environment: [String: String] = ProcessInfo.processInfo.environment,
         readSecret: ((String, Bool) -> String?)? = nil, allowCredentialPrompt: Bool = false,
         load: Loader? = nil) {
        self.home = home
        self.environment = environment
        self.load = load ?? Self.download
        self.readSecret = readSecret ?? Self.uniqueKeychainSecret
        self.allowCredentialPrompt = allowCredentialPrompt
    }

    private static func download(_ request: URLRequest) async throws -> Data {
        let (bytes, response) = try await session.bytes(for: request)
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        guard http.statusCode == 200 else { throw HTTPStatus(code: http.statusCode) }
        let limit = 1_048_576
        guard response.expectedContentLength <= limit else { throw URLError(.dataLengthExceedsMaximum) }
        var data = Data()
        for try await byte in bytes {
            guard data.count < limit else { throw URLError(.dataLengthExceedsMaximum) }
            data.append(byte)
        }
        return data
    }
    struct HTTPStatus: Error { let code: Int }

    private func request(_ url: URL, headers: [String: String], body: Object? = nil) async throws -> Object {
        try Task.checkCancellation()
        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("QuotaView", forHTTPHeaderField: "User-Agent")
        for (key, value) in headers {
            guard value.rangeOfCharacter(from: .controlCharacters) == nil else { throw URLError(.userAuthenticationRequired) }
            request.setValue(value, forHTTPHeaderField: key)
        }
        if let body {
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        let data = try await load(request)
        guard let json = try JSONSerialization.jsonObject(with: data) as? Object else { throw URLError(.cannotParseResponse) }
        return json
    }

    private func required(_ values: String?...) throws -> String {
        for value in values {
            if let clean = value?.trimmingCharacters(in: .whitespacesAndNewlines), !clean.isEmpty,
               clean.rangeOfCharacter(from: .controlCharacters) == nil { return clean }
        }
        throw URLError(.userAuthenticationRequired)
    }

    private func file(_ url: URL) -> Object? {
        guard let stream = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? stream.close() }
        guard let data = try? stream.read(upToCount: 1_048_577), data.count <= 1_048_576 else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? Object
    }

    func fetch(_ provider: IslandAgentProvider, credentialData: Data) async throws -> AgentQuotaReport {
        let fields = credentialData.isEmpty ? [:] : try JSONDecoder().decode([String: String].self, from: credentialData)
        let key = fields["credential"]
        let json: Object
        switch provider {
        case .dsh:
            let configured = try? required(key, environment["DEEPSEEK_API_KEY"], environment["DEEPSEEK_KEY"])
            let token = try required(configured ?? dshLogin())
            json = try await request(URL(string: "https://api.deepseek.com/user/balance")!, headers: bearer(token))
            if configured == nil, dshLogin() != token { throw URLError(.userAuthenticationRequired) }
        case .kimiCode:
            let international = fields["kimiRegion"] == "international"
            let endpoint = international ? "https://api.kimi.ai" : "https://api.kimi.com"
            let dir = environment["KIMI_CODE_HOME"].map { URL(fileURLWithPath: $0) } ?? home.appendingPathComponent(".kimi-code")
            var token = key ?? environment["KIMI_CODE_API_KEY"]
            if token == nil, !international, environment["KIMI_CODE_BASE_URL"] == nil,
               environment["KIMI_CODE_OAUTH_HOST"] == nil, environment["KIMI_OAUTH_HOST"] == nil,
               let cached = file(dir.appendingPathComponent("credentials/kimi-code.json")),
               let expiry = NativeQuotaResponse.number(cached["expires_at"]), expiry > Date().timeIntervalSince1970 + 60 {
                token = cached["access_token"] as? String
            }
            var url = URL(string: endpoint)!
            if let override = environment["KIMI_CODE_BASE_URL"], !override.isEmpty {
                guard let custom = URL(string: override), custom.scheme == "https", custom.host != nil,
                      custom.user == nil, custom.password == nil, custom.query == nil, custom.fragment == nil else { throw URLError(.badURL) }
                url = custom
            }
            let path = url.pathComponents.last
            url.appendPathComponent(path == "v1" ? "usages" : path == "coding" ? "v1/usages" : "coding/v1/usages")
            json = try await request(url, headers: bearer(try required(token)))
        case .openCode:
            let configured = key ?? environment["OPENCODE_API_KEY"]
            let token = try required(configured ?? openCodeLogin())
            json = try await request(URL(string: "https://opencode.ai/zen/go/v1/usage")!, headers: bearer(token))
        case .copilotCLI:
            let token = try required(key ?? copilotLogin(prompt: allowCredentialPrompt))
            json = try await request(URL(string: "https://api.github.com/copilot_internal/user")!,
                                     headers: ["Authorization": "token " + token, "X-Github-Api-Version": "2025-04-01"])
            if key == nil, try copilotLogin(prompt: false) != token { throw URLError(.userAuthenticationRequired) }
        case .cursor:
            let cookie = try required(key ?? cursorLogin(prompt: allowCredentialPrompt))
            json = try await cursor(cookie: cookie)
            if key == nil, try cursorLogin(prompt: false) != cookie { throw URLError(.userAuthenticationRequired) }
        case .devinCLI, .devinDesktop:
            json = try await devin(token: try required(key), organization: try required(fields["organization"]))
        case .geminiCLI:
            json = try await gemini()
        default: throw URLError(.unsupportedURL)
        }
        guard let report = NativeQuotaResponse.report(for: provider, json: json) else { throw URLError(.cannotParseResponse) }
        return report
    }

    private func bearer(_ token: String) -> [String: String] { ["Authorization": "Bearer " + token] }

    private struct DSHCredentials: Decodable {
        struct References: Decodable {
            let deepSeekAPIKey: String
            enum CodingKeys: String, CodingKey { case deepSeekAPIKey = "DEEPSEEK_API_KEY" }
        }
        let version: Int
        let refs: References
    }

    private func dshLogin() -> String? {
        if let custom = environment["DEEPSEEK_BASE_URL"], !custom.isEmpty,
           URL(string: custom)?.host?.lowercased() != "api.deepseek.com" { return nil }
        let root = environment["DSH_HOME"]?.trimmingCharacters(in: .whitespacesAndNewlines)
        let directory = root.flatMap { $0.isEmpty ? nil : URL(fileURLWithPath: ($0 as NSString).expandingTildeInPath) }
            ?? home.appendingPathComponent(".dsh")
        let url = directory.appendingPathComponent(".credentials.yaml")
        let fd = Darwin.open(url.path, O_RDONLY | O_NOFOLLOW | O_CLOEXEC | O_NONBLOCK)
        guard fd >= 0 else { return nil }
        let file = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
        defer { try? file.close() }
        var info = stat()
        let limit = 1_048_576
        guard fstat(fd, &info) == 0, info.st_mode & S_IFMT == S_IFREG,
              info.st_uid == getuid(), info.st_size <= limit,
              let data = try? file.read(upToCount: limit + 1), data.count <= limit,
              let credentials = try? YAMLDecoder().decode(DSHCredentials.self, from: data),
              credentials.version == 1 else { return nil }
        return try? required(credentials.refs.deepSeekAPIKey)
    }

    private func openCodeLogin() throws -> String? {
        let root = environment["XDG_DATA_HOME"].flatMap { $0.hasPrefix("/") ? URL(fileURLWithPath: $0) : nil }
            ?? home.appendingPathComponent(".local/share")
        let dir = root.appendingPathComponent("opencode")
        let name = environment["OPENCODE_DB"] ?? "opencode.db"
        guard name != ":memory:" else { return nil }
        let dbURL = name.hasPrefix("/") ? URL(fileURLWithPath: name) : dir.appendingPathComponent(name)
        if FileManager.default.fileExists(atPath: dbURL.path) {
            var db: OpaquePointer?
            defer { sqlite3_close(db) }
            guard sqlite3_open_v2(dbURL.path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else { throw URLError(.cannotOpenFile) }
            var schema: OpaquePointer?
            defer { sqlite3_finalize(schema) }
            guard sqlite3_prepare_v2(db, "SELECT 1 FROM sqlite_master WHERE type='table' AND name='credential'", -1, &schema, nil) == SQLITE_OK else { throw URLError(.cannotOpenFile) }
            switch sqlite3_step(schema) {
            case SQLITE_ROW: return try activeOpenCodeLogin(db)
            case SQLITE_DONE: break
            default: throw URLError(.cannotOpenFile)
            }
        }
        let entry = file(dir.appendingPathComponent("auth.json"))?["opencode-go"] as? Object
        return entry?["key"] as? String
    }

    private func activeOpenCodeLogin(_ db: OpaquePointer?) throws -> String? {
        let sql = """
        SELECT integration_id, value FROM credential
        WHERE active = 1 AND integration_id IN ('opencode-go','opencode')
        ORDER BY CASE integration_id WHEN 'opencode-go' THEN 0 ELSE 1 END LIMIT 2
        """
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { throw URLError(.cannotOpenFile) }
        guard sqlite3_step(statement) == SQLITE_ROW, let kind = sqlite3_column_text(statement, 0),
              let bytes = sqlite3_column_blob(statement, 1) else { return nil }
        let count = Int(sqlite3_column_bytes(statement, 1))
        guard count <= 16_384 else { return nil }
        let selected = String(cString: kind)
        let data = Data(bytes: bytes, count: count)
        let next = sqlite3_step(statement)
        guard next == SQLITE_DONE || (next == SQLITE_ROW && sqlite3_column_text(statement, 0).map { String(cString: $0) } != selected),
              let record = try JSONSerialization.jsonObject(with: data) as? Object else { return nil }
        if record["type"] as? String == "key" { return record["key"] as? String }
        guard record["type"] as? String == "oauth", let expiry = NativeQuotaResponse.date(record["expires"]),
              expiry > Date() else { return nil }
        return record["access"] as? String
    }

    /// Reads one provider-specific item only. Multiple accounts need explicit selection.
    /// Background refresh never presents a system credential prompt.
    private static func uniqueKeychainSecret(service: String, prompt: Bool) -> String? {
        let context = LAContext()
        context.interactionNotAllowed = !prompt
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
            kSecMatchLimit as String: kSecMatchLimitAll, kSecReturnPersistentRef as String: true,
            kSecUseAuthenticationContext as String: context
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let refs = result as? [Data], refs.count == 1 else { return nil }
        let read: [String: Any] = [kSecValuePersistentRef as String: refs[0],
            kSecReturnData as String: true, kSecUseAuthenticationContext as String: context]
        guard SecItemCopyMatching(read as CFDictionary, &result) == errSecSuccess,
              let bytes = result as? Data, bytes.count <= 16_384 else { return nil }
        return String(data: bytes, encoding: .utf8)
    }

    private func copilotLogin(prompt: Bool) throws -> String? {
        for name in ["COPILOT_API_TOKEN", "COPILOT_GITHUB_TOKEN", "GH_TOKEN", "GITHUB_TOKEN"] {
            if let token = environment[name], !token.isEmpty { return try required(token) }
        }
        let dir = environment["COPILOT_HOME"].map { URL(fileURLWithPath: $0) }
            ?? home.appendingPathComponent(".copilot")
        // Enterprise credentials must never be sent to the public GitHub endpoint.
        if let user = file(dir.appendingPathComponent("config.json"))?["last_logged_in_user"] as? Object,
           let host = user["host"] as? String,
           !["github.com", "https://github.com", "https://github.com/"].contains(host.lowercased()) {
            throw URLError(.userAuthenticationRequired)
        }
        return readSecret("copilot-cli", prompt)
    }

    private func cursorLogin(prompt: Bool) throws -> String? {
        let database = home.appendingPathComponent("Library/Application Support/Cursor/User/globalStorage/state.vscdb")
        if FileManager.default.fileExists(atPath: database.path) {
            var db: OpaquePointer?
            defer { sqlite3_close(db) }
            guard sqlite3_open_v2(database.path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
                throw URLError(.cannotOpenFile)
            }
            sqlite3_busy_timeout(db, 100)
            var statement: OpaquePointer?
            defer { sqlite3_finalize(statement) }
            guard sqlite3_prepare_v2(db, "SELECT value FROM ItemTable WHERE key = 'cursorAuth/accessToken' LIMIT 2", -1, &statement, nil) == SQLITE_OK else {
                throw URLError(.cannotParseResponse)
            }
            guard sqlite3_step(statement) == SQLITE_ROW, let bytes = sqlite3_column_text(statement, 0),
                  sqlite3_column_bytes(statement, 0) <= 16_384 else { return nil }
            let token = String(cString: bytes)
            guard sqlite3_step(statement) == SQLITE_DONE else { return nil }
            // A logged-out desktop is authoritative; do not silently select a CLI account.
            return try cursorCookie(token)
        }
        guard let token = readSecret("cursor-access-token", prompt) else { return nil }
        return try cursorCookie(token)
    }

    private func cursorCookie(_ token: String) throws -> String {
        let token = try required(token)
        let pieces = token.split(separator: ".", omittingEmptySubsequences: false)
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_-")
        guard token.utf8.count <= 16_384, pieces.count == 3,
              pieces.allSatisfy({ !$0.isEmpty && $0.unicodeScalars.allSatisfy(allowed.contains) }) else {
            throw URLError(.userAuthenticationRequired)
        }
        var payload = pieces[1].replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        payload += String(repeating: "=", count: (4 - payload.count % 4) % 4)
        guard let bytes = Data(base64Encoded: payload),
              let claims = (try? JSONSerialization.jsonObject(with: bytes)) as? Object,
              let subject = claims["sub"] as? String, let user = subject.components(separatedBy: "|").last,
              !user.isEmpty, user.unicodeScalars.allSatisfy(allowed.contains) else { throw URLError(.userAuthenticationRequired) }
        return "WorkosCursorSessionToken=" + user + "%3A%3A" + token
    }

    private func cursor(cookie: String) async throws -> Object {
        let value = cookie.lowercased().hasPrefix("cookie:") ? String(cookie.dropFirst("cookie:".count)).trimmingCharacters(in: .whitespaces) : cookie
        let headers = ["Cookie": value]
        let base = URL(string: "https://cursor.com/api")!
        async let summary = request(base.appendingPathComponent("usage-summary"), headers: headers)
        async let sand = try? request(base.appendingPathComponent("dashboard/get-sand-usage-status"), headers: headers, body: [:])
        async let legacy = cursorRequests(base: base, headers: headers)
        var response = (try? await summary) ?? [:]
        response["sand"] = await sand
        response["requests"] = await legacy
        return response
    }

    private func cursorRequests(base: URL, headers: [String: String]) async -> Object? {
        guard let user = try? await request(base.appendingPathComponent("auth/me"), headers: headers),
              let id = user["sub"] as? String ?? user["id"] as? String, !id.isEmpty else { return nil }
        let endpoint = base.appendingPathComponent("usage").appending(queryItems: [.init(name: "user", value: id)])
        return try? await request(endpoint, headers: headers)["gpt-4"] as? Object
    }

    private func devin(token: String, organization: String) async throws -> Object {
        var org = organization
        if let url = URL(string: org), let host = url.host, host == "devin.ai" || host.hasSuffix(".devin.ai") { org = url.path }
        let parts = org.split(separator: "/")
        guard let first = parts.first, let id = ["org","organizations"].contains(first) ? parts.dropFirst().first : parts.first,
              id.utf8.count <= 160, id.utf8.allSatisfy({ (65...90).contains($0) || (97...122).contains($0) || (48...57).contains($0) || $0 == 45 || $0 == 95 })
        else { throw URLError(.badURL) }
        var value = token
        for prefix in ["authorization:", "bearer "] where value.lowercased().hasPrefix(prefix) {
            value = value.dropFirst(prefix.count).trimmingCharacters(in: .whitespaces)
        }
        var headers = bearer(try required(value))
        if id.hasPrefix("org-") { headers["x-cog-org-id"] = String(id) }
        let paths = first == "organizations" || id.hasPrefix("org-") ? ["\(id)", "organizations/\(id)"] : ["org/\(id)", "\(id)"]
        for path in paths {
            let url = URL(string: "https://app.devin.ai/api/\(path)/billing/quota/usage")!
            do { return try await request(url, headers: headers) }
            catch let status as HTTPStatus where status.code == 404 { continue }
        }
        throw URLError(.resourceUnavailable)
    }

    private func gemini() async throws -> Object {
        let base = environment["GEMINI_CLI_HOME"].map { URL(fileURLWithPath: ($0 as NSString).expandingTildeInPath) } ?? home
        let dir = base.appendingPathComponent(".gemini")
        let security = file(dir.appendingPathComponent("settings.json"))?["security"] as? Object
        if let mode = (security?["auth"] as? Object)?["selectedType"] as? String, mode != "oauth-personal" {
            throw URLError(.userAuthenticationRequired)
        }
        guard let account = file(dir.appendingPathComponent("oauth_creds.json")) else { throw URLError(.userAuthenticationRequired) }
        if let token = try? required(account["access_token"] as? String),
           NativeQuotaResponse.date(account["expiry_date"]).map({ $0 > Date().addingTimeInterval(30) }) != false {
            do { return try await geminiQuota(token: token) }
            catch let status as HTTPStatus where status.code == 401 { /* Renew an expired access token once. */ }
        }
        return try await geminiQuota(token: refreshedGeminiToken(account))
    }

    private func geminiQuota(token: String) async throws -> Object {
        let headers = bearer(token)
        let base = URL(string: "https://cloudcode-pa.googleapis.com")!
        let status = try? await request(base.appendingPathComponent("v1internal:loadCodeAssist"), headers: headers,
                                        body: ["metadata": ["ideType": "GEMINI_CLI", "pluginType": "GEMINI"]])
        let project = status?["cloudaicompanionProject"] as? String ?? (status?["cloudaicompanionProject"] as? Object)?["id"] as? String
            ?? environment["GOOGLE_CLOUD_PROJECT"] ?? environment["GOOGLE_CLOUD_PROJECT_ID"]
        let body: Object = project.map { ["project": $0] } ?? [:]
        return try await request(base.appendingPathComponent("v1internal:retrieveUserQuota"), headers: headers, body: body)
    }

    private func refreshedGeminiToken(_ account: Object) async throws -> String {
        let id = try required(account["client_id"] as? String, environment["GEMINI_OAUTH_CLIENT_ID"])
        let refresh = try required(account["refresh_token"] as? String)
        var fields = ["grant_type": "refresh_token", "client_id": id, "refresh_token": refresh]
        if let secret = account["client_secret"] as? String ?? environment["GEMINI_OAUTH_CLIENT_SECRET"] { fields["client_secret"] = secret }
        var request = URLRequest(url: URL(string: "https://oauth2.googleapis.com/token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let alphabet = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))
        request.httpBody = Data(fields.compactMap { key, value in value.addingPercentEncoding(withAllowedCharacters: alphabet).map { key + "=" + $0 } }.joined(separator: "&").utf8)
        let response = try JSONSerialization.jsonObject(with: try await load(request)) as? Object
        return try required(response?["access_token"] as? String)
    }
}
