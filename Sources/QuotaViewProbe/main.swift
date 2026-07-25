import QuotaViewCore
import Foundation

@main
struct QuotaViewProbe {
    static func main() async {
        let timeout = ProcessInfo.processInfo.environment["QUOTAVIEW_TIMEOUT_SECONDS"]
            .flatMap(TimeInterval.init) ?? 45
        let client = CodexAppServerClient(requestTimeoutSeconds: timeout)

        do {
            let snapshot = try await client.fetchSnapshot()
            print("Codex: \(snapshot.availability.displayName)")
            print("Plan: \(snapshot.planType)")
            print("Usage: \(snapshot.usedPercent)% used / \(snapshot.remainingPercent)% remaining")

            if let resetsAt = snapshot.resetsAt {
                print("Resets: \(resetsAt.formatted(date: .abbreviated, time: .standard))")
            }

            if snapshot.unlimitedCredits {
                print("Credits: unlimited")
            } else {
                print("Credits: \(snapshot.creditBalance ?? "unavailable")")
            }

            print("Reset credits: \(snapshot.availableResetCredits)")

            if let lifetimeTokens = snapshot.lifetimeTokens {
                print("Lifetime tokens: \(lifetimeTokens.formatted())")
            }

            await client.stop()
        } catch {
            fputs("QuotaView probe failed: \(error.localizedDescription)\n", stderr)
            await client.stop()
            Foundation.exit(EXIT_FAILURE)
        }
    }
}
