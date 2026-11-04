import Foundation

/// A rolling rate-limit window as reported by the usage endpoint.
struct UsageWindow: Decodable, Equatable {
    /// Percent of the window's allowance used, 0–100.
    let utilization: Double
    let resetsAt: Date?
}

struct ExtraUsage: Decodable, Equatable {
    let isEnabled: Bool
    let utilization: Double?
}

struct UsageResponse: Decodable, Equatable {
    let fiveHour: UsageWindow?
    let sevenDay: UsageWindow?
    let sevenDayOpus: UsageWindow?
    let sevenDaySonnet: UsageWindow?
    let extraUsage: ExtraUsage?
}

/// Client for the same endpoint Claude Code's `/usage` command and claude.ai's
/// Settings → Usage page read from.
enum UsageAPI {
    static let endpoint = URL(string: "https://api.anthropic.com/api/oauth/usage")!

    enum APIError: LocalizedError {
        case unauthorized
        /// `retryAfter` is the server's `Retry-After` hint, when it sends a useful one.
        case rateLimited(retryAfter: TimeInterval?)
        case http(Int)

        var errorDescription: String? {
            switch self {
            case .unauthorized:
                "Claude Code login expired. Run `claude` in Terminal to refresh it."
            case .rateLimited:
                "Usage endpoint is rate limiting requests."
            case .http(let code):
                "Usage request failed (HTTP \(code))."
            }
        }
    }

    static func fetch(token: String) async throws -> UsageResponse {
        var request = URLRequest(url: endpoint, timeoutInterval: 20)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("claude-usage-menu-bar/1.0", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            switch http.statusCode {
            case 401, 403: throw APIError.unauthorized
            case 429:
                // The endpoint often sends `retry-after: 0`, which isn't a usable hint.
                let retryAfter = http.value(forHTTPHeaderField: "Retry-After").flatMap(TimeInterval.init)
                throw APIError.rateLimited(retryAfter: retryAfter.flatMap { $0 > 0 ? $0 : nil })
            default: throw APIError.http(http.statusCode)
            }
        }
        return try decoder.decode(UsageResponse.self, from: data)
    }

    static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let string = try container.decode(String.self)
            guard let date = parseDate(string) else {
                throw DecodingError.dataCorruptedError(
                    in: container, debugDescription: "Invalid date: \(string)")
            }
            return date
        }
        return decoder
    }()

    /// Parses ISO 8601 timestamps such as `2026-11-02T02:00:00.782778+00:00`.
    /// `ISO8601DateFormatter` only understands millisecond precision, so the
    /// fractional part is dropped before parsing.
    static func parseDate(_ string: String) -> Date? {
        let trimmed = string.replacingOccurrences(
            of: #"\.\d+"#, with: "", options: .regularExpression)
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: trimmed)
    }
}
