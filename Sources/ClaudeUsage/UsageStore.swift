import Foundation
import Observation

@MainActor
@Observable
final class UsageStore {
    private(set) var usage: UsageResponse?
    private(set) var plan: String?
    private(set) var error: String?
    private(set) var lastUpdated: Date?
    private(set) var isLoading = false

    private static let refreshInterval: TimeInterval = 60
    private var timer: Timer?

    init() {
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: Self.refreshInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    /// Refreshes unless a request is in flight or data was fetched within `minimumAge` seconds.
    func refresh(ifOlderThan minimumAge: TimeInterval = 0) {
        guard !isLoading else { return }
        if let lastUpdated, Date().timeIntervalSince(lastUpdated) < minimumAge { return }

        isLoading = true
        Task {
            defer { isLoading = false }
            do {
                // Re-read every time: Claude Code rotates the token whenever it refreshes it.
                let credentials = try await Task.detached { try Credentials.load() }.value
                let usage = try await UsageAPI.fetch(token: credentials.accessToken)
                self.usage = usage
                self.plan = credentials.subscriptionType
                self.lastUpdated = Date()
                self.error = nil
            } catch {
                self.error = error.localizedDescription
            }
        }
    }
}
