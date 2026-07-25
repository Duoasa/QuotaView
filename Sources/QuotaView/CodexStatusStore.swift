import QuotaViewCore
import Foundation
import SwiftUI

@MainActor
final class CodexStatusStore: ObservableObject {
    @Published private(set) var snapshot: CodexSnapshot?
    @Published private(set) var isRefreshing = false
    @Published private(set) var errorMessage: String?

    private let client: CodexAppServerClient
    private let diagnostics: UserDefaults
    private var pollingTask: Task<Void, Never>?

    init(
        client: CodexAppServerClient = CodexAppServerClient(),
        diagnostics: UserDefaults = .standard
    ) {
        self.client = client
        self.diagnostics = diagnostics
    }

    var menuBarIcon: String {
        if errorMessage != nil {
            return "exclamationmark.triangle.fill"
        }

        switch snapshot?.availability {
        case .ready:
            return "bolt.circle.fill"
        case .limited:
            return "gauge.with.dots.needle.67percent"
        case .exhausted:
            return "exclamationmark.octagon.fill"
        case nil:
            return "bolt.circle"
        }
    }

    var accessibilityStatus: String {
        if let errorMessage {
            return "QuotaView：\(errorMessage)"
        }
        if let snapshot {
            return "Codex \(snapshot.availability.displayName)，剩余 \(snapshot.remainingPercent)%"
        }
        return "QuotaView 正在连接"
    }

    func start() {
        guard pollingTask == nil else { return }

        pollingTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh()
                try? await Task.sleep(for: .seconds(60))
            }
        }
    }

    func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        do {
            snapshot = try await client.fetchSnapshot()
            errorMessage = nil
            recordSuccess(snapshot)
        } catch {
            errorMessage = error.localizedDescription
            recordFailure(error)
        }
    }

    private func recordSuccess(_ snapshot: CodexSnapshot?) {
        guard let snapshot else { return }
        diagnostics.set(
            snapshot.lastUpdatedAt.timeIntervalSince1970,
            forKey: "diagnostics.lastSuccessAt"
        )
        diagnostics.set(
            snapshot.usedPercent,
            forKey: "diagnostics.lastUsedPercent"
        )
        diagnostics.set(
            snapshot.availability.rawValue,
            forKey: "diagnostics.lastAvailability"
        )
        diagnostics.removeObject(forKey: "diagnostics.lastError")
        diagnostics.removeObject(forKey: "diagnostics.lastErrorAt")
    }

    private func recordFailure(_ error: Error) {
        diagnostics.set(
            error.localizedDescription,
            forKey: "diagnostics.lastError"
        )
        diagnostics.set(
            Date().timeIntervalSince1970,
            forKey: "diagnostics.lastErrorAt"
        )
    }
}
