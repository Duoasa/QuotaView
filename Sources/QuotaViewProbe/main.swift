import Foundation
import QuotaViewCore

@main
struct QuotaViewProbe {
    static func main() async {
        let timeout = ProcessInfo.processInfo.environment[
            "QUOTAVIEW_TIMEOUT_SECONDS"
        ]
        .flatMap(TimeInterval.init) ?? 45
        let client = CodexAppServerClient(
            startupTimeoutSeconds: timeout,
            requestTimeoutSeconds: timeout
        )

        do {
            let payload = try await client.fetchPayload()
            let result = try CodexProviderAdapter.makeResult(
                payload: payload
            )
            let snapshot = result.snapshot

            guard let primary = snapshot.rateWindows.first(
                where: {
                    $0.id == CodexDomainCatalog.primaryRateWindowID
                }
            ) else {
                throw ProviderError.protocolViolation
            }

            print("Codex data: available")
            print("Quota: \(riskLabel(primary.quotaRisk))")
            print("Plan: \(snapshot.plan?.rawValue ?? "unavailable")")

            if let used = primary.usedFraction,
               let remaining = primary.remainingFraction {
                print(
                    "Usage: \(percent(used))% used / "
                    + "\(percent(remaining))% remaining"
                )
            }

            if let resetsAt = primary.resetsAt {
                print(
                    "Resets: "
                    + resetsAt.formatted(
                        date: .abbreviated,
                        time: .standard
                    )
                )
            }

            if let credits = snapshot.balances.first(
                where: { $0.kind == .credits }
            ) {
                if credits.isUnlimited {
                    print("Credits: unlimited")
                } else {
                    print(
                        "Credits: "
                        + (decimalString(credits.value)
                            ?? "unavailable")
                    )
                }
            }

            print(
                "Reset credits: "
                + (count(
                    CodexDomainCatalog.resetCreditsID,
                    in: snapshot
                ).map(String.init) ?? "unavailable")
            )

            if let lifetime = count(
                CodexDomainCatalog.lifetimeTokensID,
                in: snapshot
            ) {
                print("Lifetime tokens: \(lifetime.formatted())")
            }

            await client.stop()
        } catch {
            fputs(
                "QuotaView probe failed: "
                    + error.localizedDescription
                    + "\n",
                stderr
            )
            await client.stop()
            Foundation.exit(EXIT_FAILURE)
        }
    }

    private static func riskLabel(_ risk: QuotaRisk) -> String {
        switch risk {
        case .normal: "normal"
        case .warning: "warning"
        case .exhausted: "exhausted"
        case .unknown: "unknown"
        }
    }

    private static func percent(_ fraction: Double) -> Int {
        min(max(Int((fraction * 100).rounded()), 0), 100)
    }

    private static func count(
        _ id: MetricID,
        in snapshot: ProviderSnapshot
    ) -> Int64? {
        guard case .count(let value) = snapshot.currentMetrics.first(
            where: { $0.definitionID == id }
        )?.value else {
            return nil
        }
        return value
    }

    private static func decimalString(
        _ value: MetricValue?
    ) -> String? {
        guard case .decimal(let decimal) = value else {
            return nil
        }
        return NSDecimalNumber(decimal: decimal).stringValue
    }
}
