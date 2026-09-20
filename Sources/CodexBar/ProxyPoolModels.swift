import Foundation

struct ProxyPoolSnapshot: Decodable, Sendable {
    let updatedAt: Double
    let providers: [ProxyPoolProvider]

    func provider(_ id: String, now: Date = Date()) throws -> ProxyPoolProvider {
        guard self.updatedAt.isFinite,
              (-30...180).contains(now.timeIntervalSince1970 - self.updatedAt)
        else {
            throw ProxyPoolError.stale
        }
        guard let provider = self.providers.first(where: { $0.id == id }) else {
            throw ProxyPoolError.providerMissing
        }
        return provider
    }
}

struct ProxyPoolProvider: Decodable, Sendable {
    let id: String
    let name: String
    let accounts: [ProxyPoolAccount]
    let windows: [ProxyPoolWindow]
    let activeAccounts: Int
    let disabledAccounts: Int

    static func bridgeID(pluginID: String) -> String? {
        switch pluginID {
        case "proxy-codex": "codex"
        case "proxy-claude": "claude"
        case "proxy-antigravity": "antigravity"
        case "proxy-xai": "xai"
        case "proxy-kimi": "kimi"
        default: nil
        }
    }
}

struct ProxyPoolAccount: Decodable, Identifiable, Sendable {
    let id: String
    let label: String?
    let plan: String
    let disabled: Bool
    let unavailable: Bool
    let credentialCount: Int?
    let windows: [ProxyPoolWindow]
    let error: String?

    var displayName: String {
        self.label ?? "Account \(self.id.prefix(8))"
    }
}

struct ProxyPoolWindow: Decodable, Identifiable, Sendable {
    let id: String
    let title: String
    let usedPercent: Double
    let resetAt: Double?
    let coveredAccounts: Int?
    let totalAccounts: Int?
    let basis: String?

    func validPercent(now: Date = Date()) -> Double? {
        guard self.usedPercent.isFinite, (0...100).contains(self.usedPercent),
              self.resetAt.map({ $0.isFinite && $0 > now.timeIntervalSince1970 }) ?? true else { return nil }
        return self.usedPercent
    }
}

enum ProxyPoolError: LocalizedError {
    case configuration, stale, providerMissing, unauthorized, busy, server, invalidResponse, unconfirmed

    var errorDescription: String? {
        switch self {
        case .configuration: "Configure the HTTPS bridge URL and tokens in Settings → Plugins."
        case .stale: "Quota data is stale. Check the bridge collector on Beast."
        case .providerMissing: "This provider is not available in the bridge snapshot."
        case .unauthorized: "The bridge rejected the token. Check the plugin settings."
        case .busy: "The bridge is collecting quotas. Try again shortly."
        case .server: "The bridge request failed. Refresh to verify the current account state."
        case .invalidResponse: "The bridge returned an invalid response."
        case .unconfirmed: "The requested account state was not confirmed. Refresh before trying again."
        }
    }
}
