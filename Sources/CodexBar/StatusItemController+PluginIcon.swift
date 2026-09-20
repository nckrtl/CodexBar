import AppKit
import CodexBarCore

/// Generic plugin support kept separate from first-party icon selection.
struct PluginIconValues: Equatable {
    let primary: Double?
    let secondary: Double?

    init(snapshot: UsageSnapshot?, showUsed: Bool, now: Date = Date()) {
        func percent(_ window: RateWindow?) -> Double? {
            guard let window, window.usedPercent.isFinite,
                  window.resetsAt.map({ $0 > now }) ?? true else { return nil }
            let used = min(100, max(0, window.usedPercent))
            return showUsed ? used : 100 - used
        }
        self.primary = percent(snapshot?.primary)
        self.secondary = percent(snapshot?.secondary)
    }
}

enum PluginIconSelection {
    static func resolve(
        selected: ProviderInstanceID?,
        plugins: [ProviderInstanceID],
        hasFirstPartyProviders: Bool) -> ProviderInstanceID?
    {
        if let selected, plugins.contains(selected) { return selected }
        return hasFirstPartyProviders ? nil : plugins.first
    }
}

extension StatusItemController {
    func userPluginMenuBarContent() -> (image: NSImage, title: String?, label: String)? {
        guard self.shouldMergeIcons else { return nil }
        let plugins = self.topLevelUserProviderPlugins()
        let selected = PluginIconSelection.resolve(
            selected: self.selectedMenuProvider,
            plugins: plugins.map(\.manifest.id),
            hasFirstPartyProviders: !self.store.enabledFirstPartyProvidersForDisplay().isEmpty)
        let plugin = plugins.first { $0.manifest.id == selected }
        guard let plugin else { return nil }
        let snapshot = self.store.snapshots[plugin.manifest.id]
        let values = PluginIconValues(snapshot: snapshot, showUsed: self.settings.usageBarsShowUsed)
        let stale = self.store.errors[plugin.manifest.id] != nil || snapshot == nil
        let image = IconRenderer.makeIcon(
            primaryRemaining: values.primary,
            weeklyRemaining: values.secondary,
            creditsRemaining: nil,
            stale: stale,
            style: .codex,
            hideCritters: true)
        let percent = values.primary.map { "\(Int($0.rounded()))%" }
        let title = self.settings.menuBarShowsBrandIconWithPercent ? (percent ?? "—") : nil
        let direction = self.settings.usageBarsShowUsed ? "used" : "remaining"
        let label = "\(plugin.manifest.name): \(percent ?? "Unavailable") \(direction)\(stale ? ", stale" : "")"
        return (image, title, label)
    }
}
