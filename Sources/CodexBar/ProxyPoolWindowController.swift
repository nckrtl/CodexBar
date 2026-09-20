import AppKit
import CodexBarCore
import SwiftUI

@MainActor
@Observable
final class ProxyPoolModel {
    let client: ProxyPoolClient
    let providerID: String
    let onChange: () -> Void
    var provider: ProxyPoolProvider?
    var updatedAt: Date?
    var busy = false
    var error: String?

    init(client: ProxyPoolClient, providerID: String, onChange: @escaping () -> Void) {
        self.client = client
        self.providerID = providerID
        self.onChange = onChange
    }

    func refresh() async {
        guard !self.busy else { return }
        self.busy = true
        defer { self.busy = false }
        do {
            try await self.accept(self.client.fetch())
        } catch {
            self.error = error.localizedDescription
        }
    }

    func setEnabled(_ enabled: Bool, account: ProxyPoolAccount) async {
        guard !self.busy else { return }
        self.busy = true
        defer { self.busy = false }
        do {
            try await self.accept(self.client.setDisabled(!enabled, provider: self.providerID, account: account.id))
            self.onChange()
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func accept(_ snapshot: ProxyPoolSnapshot) throws {
        self.provider = try snapshot.provider(self.providerID)
        self.updatedAt = Date(timeIntervalSince1970: snapshot.updatedAt)
        self.error = nil
    }
}

@MainActor
final class ProxyPoolWindowController: NSObject, NSWindowDelegate {
    static let shared = ProxyPoolWindowController()
    private var windows: [String: NSWindow] = [:]

    func show(plugin: UserProviderPlugin, settings: SettingsStore, store: UsageStore) {
        let config = settings.pluginConfig(plugin.manifest.id)
        let showUsed = settings.usageBarsShowUsed
        let onChange: () -> Void = { [weak store] in
            Task { await store?.refreshUserPlugin(plugin.manifest.id) }
        }
        guard let providerID = ProxyPoolProvider.bridgeID(pluginID: plugin.manifest.id.rawValue) else { return }
        self.windows[providerID]?.close()
        let content: AnyView
        do {
            let client = try ProxyPoolClient(
                baseURL: config?.pluginSettings?["BASE_URL"] ?? "",
                readToken: config?.pluginSecrets?["BRIDGE_TOKEN"] ?? "",
                controlToken: config?.pluginSecrets?["CONTROL_TOKEN"] ?? "")
            let model = ProxyPoolModel(client: client, providerID: providerID, onChange: onChange)
            content = AnyView(ProxyPoolView(model: model, showUsed: showUsed))
        } catch {
            content = AnyView(Text(error.localizedDescription).padding(30))
        }
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 610, height: 700),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false)
        window.title = "\(plugin.manifest.name) · Accounts"
        window.minSize = NSSize(width: 490, height: 400)
        window.delegate = self
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: content)
        window.center()
        self.windows[providerID] = window
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        self.windows = self.windows.filter { $0.value !== window }
        // Removing the hosting view cancels its polling task even though the window is retained during close.
        window.contentView = nil
    }
}

private struct ProxyPoolView: View {
    @State var model: ProxyPoolModel
    let showUsed: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(self.model.provider?.name ?? "Provider pool").font(.title2.bold())
                    if let provider = self.model.provider {
                        Text("\(provider.activeAccounts) enabled · \(provider.disabledAccounts) disabled")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                if self.model.busy { ProgressView().controlSize(.small) }
                Button("Refresh", systemImage: "arrow.clockwise") { Task { await self.model.refresh() } }
                    .disabled(self.model.busy)
            }.padding(20)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if let error = self.model.error {
                        Label(error, systemImage: "exclamationmark.triangle")
                            .font(.callout).foregroundStyle(.red).textSelection(.enabled)
                        Text("Previously fetched values may be out of date.").font(.caption).foregroundStyle(.secondary)
                    }
                    if let provider = self.model.provider {
                        GroupBox("Combined pool") {
                            VStack(alignment: .leading, spacing: 12) {
                                if provider.windows
                                    .isEmpty { Text("No current quota available").foregroundStyle(.secondary) }
                                ForEach(provider.windows) { window in
                                    ProxyPoolQuotaRow(window: window, showUsed: self.showUsed)
                                }
                            }.padding(8).frame(maxWidth: .infinity, alignment: .leading)
                        }
                        Text("Accounts").font(.headline)
                        if !self.model.client.canControl {
                            Text("Read-only. Add an Account control token in Settings → Plugins to enable switches.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        ForEach(provider.accounts) { account in
                            self.accountCard(account)
                        }
                    }
                }.padding(20)
            }
            Divider()
            HStack {
                Text("CLIProxyAPI · Beast")
                Spacer()
                if let date = self.model.updatedAt {
                    Text("Collected \(date.formatted(date: .omitted, time: .standard))")
                }
            }.font(.caption).foregroundStyle(.secondary).padding(12)
        }
        .task {
            await self.model.refresh()
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(30)) } catch { return }
                await self.model.refresh()
            }
        }
    }

    private func accountCard(_ account: ProxyPoolAccount) -> some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(account.displayName).font(.headline).textSelection(.enabled)
                        Text(self.accountSubtitle(account)).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Toggle("Enabled", isOn: Binding(
                        get: { !account.disabled },
                        set: { enabled in Task { await self.model.setEnabled(enabled, account: account) } }))
                        .toggleStyle(.switch)
                        .disabled(self.model.busy || !self.model.client.canControl || self.model.error != nil)
                        .accessibilityLabel("Enable \(account.displayName)")
                }
                if account.disabled {
                    Text("Excluded from pool. Quota is not fetched while disabled.")
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    if let error = account.error {
                        Label(error, systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.orange)
                    }
                    if account.unavailable {
                        Text("Temporarily unavailable or cooling down").font(.caption).foregroundStyle(.orange)
                    }
                    ForEach(account.windows) { window in
                        ProxyPoolQuotaRow(window: window, showUsed: self.showUsed)
                    }
                    if account.windows.isEmpty, account.error == nil {
                        Text("Quota unavailable").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }.padding(8).frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func accountSubtitle(_ account: ProxyPoolAccount) -> String {
        let credentials = account.credentialCount ?? 1
        let plan = account.plan.isEmpty ? "Plan not reported" : account.plan.capitalized
        return credentials > 1 ? "\(plan) · Switch applies to all \(credentials) credentials" : plan
    }
}

private struct ProxyPoolQuotaRow: View {
    let window: ProxyPoolWindow
    let showUsed: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(self.window.title).font(.callout)
                Spacer()
                if let used = self.window.validPercent() {
                    Text("\(Int((self.showUsed ? used : 100 - used).rounded()))% \(self.showUsed ? "used" : "left")")
                        .font(.callout.monospacedDigit())
                } else {
                    Text("Awaiting refresh").font(.caption).foregroundStyle(.secondary)
                }
            }
            if let used = self.window.validPercent() {
                UsageProgressBar(
                    percent: self.showUsed ? used : 100 - used,
                    tint: used >= 90 ? .orange : .accentColor,
                    accessibilityLabel: "\(self.window.title) quota")
            }
            HStack {
                if let basis = self.window.basis {
                    Text(basis)
                }
                if let covered = self.window.coveredAccounts, let total = self.window.totalAccounts {
                    Text("\(covered)/\(total) checked")
                }
                Spacer()
                if let reset = self.window.resetAt, reset.isFinite {
                    let prefix = (self.window.totalAccounts ?? 1) > 1 ? "Next account reset" : "Resets"
                    let date = Date(timeIntervalSince1970: reset).formatted(date: .abbreviated, time: .shortened)
                    Text("\(prefix) \(date)")
                }
            }.font(.caption2).foregroundStyle(.secondary)
        }
    }
}

extension StatusItemController {
    func proxyPoolAction(for plugin: UserProviderPlugin, menu: NSMenu) -> (() -> Void)? {
        guard ProxyPoolProvider.bridgeID(pluginID: plugin.manifest.id.rawValue) != nil else { return nil }
        return { [weak self, weak menu] in
            guard let self else { return }
            menu?.cancelTracking()
            ProxyPoolWindowController.shared.show(plugin: plugin, settings: self.settings, store: self.store)
        }
    }
}
