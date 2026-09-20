import CodexBarCore
import Foundation
import Testing
@testable import CodexBar

struct ProxyPoolTests {
    @Test
    func `switching active plugins changes the indicator source and disabled selections fall back`() throws {
        let codex = try #require(ProviderInstanceID(rawValue: "proxy-codex"))
        let grok = try #require(ProviderInstanceID(rawValue: "proxy-xai"))
        let plugins = [codex, grok]
        #expect(PluginIconSelection.resolve(selected: codex, plugins: plugins, hasFirstPartyProviders: false) == codex)
        #expect(PluginIconSelection.resolve(selected: grok, plugins: plugins, hasFirstPartyProviders: false) == grok)
        #expect(PluginIconSelection.resolve(selected: grok, plugins: [codex], hasFirstPartyProviders: false) == codex)
        #expect(PluginIconSelection.resolve(selected: .codex, plugins: plugins, hasFirstPartyProviders: true) == nil)
        #expect(PluginIconSelection.resolve(selected: nil, plugins: [], hasFirstPartyProviders: false) == nil)
    }

    @Test
    func `plugin indicator uses live plugin windows with used and remaining semantics`() {
        let snapshot = UsageSnapshot(
            primary: RateWindow(usedPercent: 96, windowMinutes: nil, resetsAt: nil, resetDescription: nil),
            secondary: RateWindow(usedPercent: 20, windowMinutes: nil, resetsAt: nil, resetDescription: nil),
            updatedAt: Date())
        #expect(PluginIconValues(snapshot: snapshot, showUsed: false).primary == 4)
        #expect(PluginIconValues(snapshot: snapshot, showUsed: true).primary == 96)
        #expect(PluginIconValues(snapshot: snapshot, showUsed: false).secondary == 80)
        #expect(PluginIconValues(snapshot: nil, showUsed: false).primary == nil)
    }

    @Test
    func `expired icon windows are unknown rather than unused capacity`() {
        let snapshot = UsageSnapshot(
            primary: RateWindow(
                usedPercent: 0,
                windowMinutes: nil,
                resetsAt: Date(timeIntervalSince1970: 100),
                resetDescription: nil),
            secondary: nil,
            updatedAt: Date())
        #expect(PluginIconValues(snapshot: snapshot, showUsed: false).primary == nil)
    }

    @Test
    func `pool validates freshness and provider isolation`() throws {
        let json = """
        {"updatedAt":1000,"providers":[{"id":"codex","name":"Codex","accounts":[],
        "windows":[],"activeAccounts":0,"disabledAccounts":0}]}
        """
        let snapshot = try JSONDecoder().decode(ProxyPoolSnapshot.self, from: Data(json.utf8))
        let now = Date(timeIntervalSince1970: 1100)
        #expect(try snapshot.provider("codex", now: now).id == "codex")
        #expect(throws: ProxyPoolError.self) { try snapshot.provider("xai", now: now) }
        #expect(throws: ProxyPoolError.self) {
            try snapshot.provider("codex", now: Date(timeIntervalSince1970: 1181))
        }
    }

    @Test
    func `account controls need a separate token and bridge connections require HTTPS`() throws {
        let token = String(repeating: "a", count: 32)
        let readonly = try ProxyPoolClient(baseURL: "https://bridge.test", readToken: token, controlToken: "")
        #expect(!readonly.canControl)
        let same = try ProxyPoolClient(baseURL: "https://bridge.test", readToken: token, controlToken: token)
        #expect(!same.canControl)
        let writable = try ProxyPoolClient(
            baseURL: "https://bridge.test",
            readToken: token,
            controlToken: String(repeating: "b", count: 32))
        #expect(writable.canControl)
        for base in ["http://bridge.test", "https://user:password@bridge.test", "https://bridge.test?token=bad"] {
            #expect(throws: ProxyPoolError.self) {
                try ProxyPoolClient(baseURL: base, readToken: token, controlToken: "")
            }
        }
        #expect(ProxyPoolProvider.bridgeID(pluginID: "proxy-xai") == "xai")
        #expect(ProxyPoolProvider.bridgeID(pluginID: "proxy-claude") == "claude")
        #expect(ProxyPoolProvider.bridgeID(pluginID: "unrelated-plugin") == nil)
    }
}
