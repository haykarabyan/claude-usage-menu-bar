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

    /// The usage endpoint rate limits per OAuth token, and that token is shared with Claude Code
    /// itself, so polling has to be sparse. Reports put the allowance at a handful of requests
    /// that refills over a few minutes.
    private static let refreshInterval: TimeInterval = 5 * 60
    /// Backoff after a 429 starts at `refreshInterval` and doubles up to this cap.
    private static let maxBackoff: TimeInterval = 30 * 60

    private var timer: Timer?
    private var consecutiveRateLimits = 0
    /// Automatic refreshes are skipped until this date while backing off from a 429.
    private var retryAt: Date?

    init() {
        refresh()
    }

    /// Refreshes unless a request is in flight, data was fetched within `minimumAge` seconds, or
    /// we're backing off from a rate limit. `force` (the refresh button and the scheduled timer)
    /// skips the last two checks.
    func refresh(ifOlderThan minimumAge: TimeInterval = 0, force: Bool = false) {
        guard !isLoading else { return }
        if !force {
            if let retryAt, Date() < retryAt { return }
            if let lastUpdated, Date().timeIntervalSince(lastUpdated) < minimumAge { return }
        }

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
                consecutiveRateLimits = 0
                retryAt = nil
                scheduleNextRefresh(after: Self.refreshInterval)
            } catch UsageAPI.APIError.rateLimited(let retryAfter) {
                consecutiveRateLimits += 1
                let backoff = min(
                    Self.refreshInterval * pow(2, Double(consecutiveRateLimits - 1)), Self.maxBackoff)
                let delay = max(retryAfter ?? 0, backoff)
                let retryAt = Date().addingTimeInterval(delay)
                self.retryAt = retryAt
                let time = retryAt.formatted(date: .omitted, time: .shortened)
                self.error = "Usage endpoint is rate limiting requests. Retrying at \(time)."
                scheduleNextRefresh(after: delay)
            } catch {
                self.error = error.localizedDescription
                scheduleNextRefresh(after: Self.refreshInterval)
            }
        }
    }

    private func scheduleNextRefresh(after delay: TimeInterval) {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            Task { @MainActor in self?.refresh(force: true) }
        }
    }
}
