import Foundation

/// Identity and wait evidence are parsed from the wire before display JSON can
/// round an integer or interpret a missing collection as an empty collection.
public enum CodexSharedMessageIdentity {
    public static func rpcID(messageData: Data, field: String = "id") -> CodexDesktopIPCRequestID? {
        guard messageData.count <= 1_048_576 else { return nil }
        let decoder = JSONDecoder()
        decoder.userInfo[identityField] = field
        guard let identity = try? decoder.decode(IdentityEnvelope.self, from: messageData).identity else { return nil }
        if case .string(let value) = identity, value.isEmpty { return nil }
        return identity
    }
    private static let identityField = CodingUserInfoKey(rawValue: "QuotaView.rpcIdentityField")!
    private struct IdentityEnvelope: Decodable {
        let identity: CodexDesktopIPCRequestID
        init(from decoder: Decoder) throws {
            let values = try decoder.container(keyedBy: Field.self)
            let key = Field(stringValue: decoder.userInfo[identityField] as? String ?? "id")!
            identity = try values.decode(CodexDesktopIPCRequestID.self, forKey: key)
        }
    }
    private struct Field: CodingKey {
        let stringValue: String
        var intValue: Int? { nil }
        init?(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { return nil }
    }
    public static func waitStatus(statusData: Data) -> CodexDesktopThreadWaitStatus {
        guard statusData.count <= 65_536,
              let status = try? JSONDecoder().decode(DesktopIPCJSON.self, from: statusData),
              status["type"]?.string == "active", let raw = status["activeFlags"]?.array,
              raw.allSatisfy({ $0.string != nil }) else { return .unavailable }
        let flags = Set(raw.compactMap(\.string))
        guard flags.isSubset(of: ["waitingOnApproval", "waitingOnUserInput"]) else { return .unavailable }
        if flags.contains("waitingOnUserInput") { return .waiting(.userInput) }
        if flags.contains("waitingOnApproval") { return .waiting(.approval) }
        return .running
    }
}
