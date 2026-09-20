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
    private func selectedMenuBarPlugin() -> UserProviderPlugin? {
        guard self.shouldMergeIcons else { return nil }
        let plugins = self.topLevelUserProviderPlugins()
        let selected = PluginIconSelection.resolve(
            selected: self.selectedMenuProvider,
            plugins: plugins.map(\.manifest.id),
            hasFirstPartyProviders: !self.store.enabledFirstPartyProvidersForDisplay().isEmpty)
        return plugins.first { $0.manifest.id == selected }
    }

    func userPluginIconObservationSignature() -> String? {
        guard let plugin = self.selectedMenuBarPlugin() else { return nil }
        let values = PluginIconValues(
            snapshot: self.store.snapshots[plugin.manifest.id], showUsed: self.settings.usageBarsShowUsed)
        return [
            "plugin=\(plugin.manifest.id.rawValue)",
            "primary=\(String(describing: values.primary))",
            "secondary=\(String(describing: values.secondary))",
            "error=\(self.store.errors[plugin.manifest.id] != nil)",
            "showUsed=\(self.settings.usageBarsShowUsed)",
            "showPercent=\(self.settings.menuBarShowsBrandIconWithPercent)",
        ].joined(separator: "|")
    }

    func userPluginMenuBarContent() -> (image: NSImage, title: String?, label: String)? {
        guard let plugin = self.selectedMenuBarPlugin() else { return nil }
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
