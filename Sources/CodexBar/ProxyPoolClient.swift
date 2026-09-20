import Foundation

/// Never follow a redirect with a bridge credential or use browser cookies.
private final class ProxyPoolSessionDelegate: NSObject, URLSessionTaskDelegate {
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void)
    {
        completionHandler(nil)
    }
}

struct ProxyPoolClient: Sendable {
    let baseURL: URL
    let readToken: String
    let controlToken: String

    init(baseURL: String, readToken: String, controlToken: String) throws {
        guard let url = URL(string: baseURL), url.scheme == "https", url.host != nil,
              url.user == nil, url.password == nil, url.query == nil, url.fragment == nil,
              readToken.count >= 32 else { throw ProxyPoolError.configuration }
        self.baseURL = url
        self.readToken = readToken
        self.controlToken = controlToken
    }

    var canControl: Bool {
        self.controlToken.count >= 32 && self.controlToken != self.readToken
    }

    func fetch() async throws -> ProxyPoolSnapshot {
        try await self.request(path: "api/v1/usage", token: self.readToken)
    }

    func setDisabled(_ disabled: Bool, provider: String, account: String) async throws -> ProxyPoolSnapshot {
        guard self.canControl, ["codex", "antigravity", "xai", "kimi"].contains(provider),
              account.range(of: "^[a-f0-9]{16}$", options: .regularExpression) != nil
        else {
            throw ProxyPoolError.configuration
        }
        let snapshot = try await self.request(
            path: "api/v1/providers/\(provider)/accounts/\(account)",
            token: self.controlToken,
            body: JSONEncoder().encode(AccountState(disabled: disabled)))
        let confirmed = try snapshot.provider(provider).accounts.first { $0.id == account }
        guard confirmed?.disabled == disabled else { throw ProxyPoolError.unconfirmed }
        return snapshot
    }

    private struct AccountState: Encodable { let disabled: Bool }

    private func request(path: String, token: String, body: Data? = nil) async throws -> ProxyPoolSnapshot {
        var request = URLRequest(url: self.baseURL.appendingPathComponent(path))
        request.httpMethod = body == nil ? "GET" : "PUT"
        request.httpBody = body
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = body == nil ? 20 : 120
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        configuration.urlCredentialStorage = nil
        configuration.urlCache = nil
        let session = URLSession(configuration: configuration, delegate: ProxyPoolSessionDelegate(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse else { throw ProxyPoolError.invalidResponse }
        switch response.statusCode {
        case 200: break
        case 401, 403: throw ProxyPoolError.unauthorized
        case 409: throw ProxyPoolError.busy
        default: throw ProxyPoolError.server
        }
        guard let snapshot = try? JSONDecoder().decode(ProxyPoolSnapshot.self, from: data) else {
            throw ProxyPoolError.invalidResponse
        }
        return snapshot
    }
}
