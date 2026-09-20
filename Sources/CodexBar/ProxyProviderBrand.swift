import AppKit
import CodexBarCore

/// Reuse upstream artwork so proxy tabs track brand updates without copied assets.
@MainActor
enum ProxyProviderBrand {
    static func image(for plugin: UserProviderPlugin) -> NSImage? {
        let provider: UsageProvider
        switch plugin.manifest.id.rawValue {
        case "proxy-codex": provider = .codex
        case "proxy-claude": provider = .claude
        case "proxy-antigravity": provider = .antigravity
        case "proxy-xai": provider = .grok
        case "proxy-kimi": provider = .kimi
        default: return nil
        }
        // Callers resize images; leave the built-in provider's cached image untouched.
        return ProviderBrandIcon.image(for: provider)?.copy() as? NSImage
    }
}
