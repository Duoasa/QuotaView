import Foundation

/// Drives the next entry transition using the same monotonic clock as the store.
@MainActor
final class MultitaskEntryScheduler {
    private(set) var deadline: TimeInterval?
    private var task: Task<Void, Never>?

    func cancel() {
        task?.cancel()
        task = nil
        deadline = nil
    }

    func schedule(_ next: TimeInterval?, onFire: @escaping (TimeInterval) -> Void) {
        guard next != deadline else { return }
        cancel()
        guard let next else { return }
        deadline = next
        task = Task { [weak self] in
            let delay = max(0, next - ProcessInfo.processInfo.systemUptime)
            do { try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000)) }
            catch { return }
            guard let self, !Task.isCancelled, self.deadline == next else { return }
            self.deadline = nil
            self.task = nil
            onFire(ProcessInfo.processInfo.systemUptime)
        }
    }
}
