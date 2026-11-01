import Foundation

/// Reads the OAuth credentials that Claude Code stores after `claude` login.
///
/// Claude Code writes them to the login keychain via `/usr/bin/security`, so reading them
/// back through the same tool avoids a keychain access prompt for this app.
struct Credentials {
    let accessToken: String
    let subscriptionType: String?
    let expiresAt: Date?

    enum LoadError: LocalizedError {
        case notFound
        case malformed

        var errorDescription: String? {
            switch self {
            case .notFound: "Claude Code login not found. Run `claude` in Terminal and sign in."
            case .malformed: "Couldn't read the Claude Code credentials."
            }
        }
    }

    static let keychainService = "Claude Code-credentials"

    static func load() throws -> Credentials {
        if let data = readKeychain() ?? readFile() {
            return try parse(data)
        }
        throw LoadError.notFound
    }

    private static func parse(_ data: Data) throws -> Credentials {
        guard
            let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let oauth = root["claudeAiOauth"] as? [String: Any],
            let token = oauth["accessToken"] as? String, !token.isEmpty
        else { throw LoadError.malformed }

        let expiresAt = (oauth["expiresAt"] as? Double).map { Date(timeIntervalSince1970: $0 / 1000) }
        return Credentials(
            accessToken: token,
            subscriptionType: oauth["subscriptionType"] as? String,
            expiresAt: expiresAt
        )
    }

    private static func readKeychain() -> Data? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        process.arguments = ["find-generic-password", "-s", keychainService, "-w"]
        let stdout = Pipe()
        process.standardOutput = stdout
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return nil
        }
        let data = stdout.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0, !data.isEmpty else { return nil }
        return data
    }

    /// Fallback for setups where Claude Code keeps credentials on disk instead of the keychain.
    private static func readFile() -> Data? {
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/.credentials.json")
        return try? Data(contentsOf: url)
    }
}
