# CLIProxyAPI fork

Repository: https://github.com/nckrtl/CodexBar. Custom branch: `proxy`.
Initial base: upstream `v0.62.0`. `origin` is the fork; `upstream` is
https://github.com/steipete/CodexBar.git. The inherited `main` has no custom commits.

## Scope and boundaries

Keep provider collection, deduplication, pooling and account control on Beast in
https://github.com/nckrtl/proxy-cli-usage. Do not copy those rules into Swift or
replace upstream's provider registry. All built-in providers, including Cursor, remain available in Settings. Enabling one
alongside proxy plugins uses the upstream authentication and UI. The merged indicator
follows either kind of selected tab; installation must preserve enabled built-ins.
The existing four JavaScript plugins remain
ordinary CodexBar providers and can run in the official app without account controls.

Additions are isolated in `ProxyPool*.swift` and
`StatusItemController+PluginIcon.swift`. Small call sites connect them to the unified
icon renderer and plugin cards/settings. Keep these call sites small when merging.
The generic plugin icon change can be carried or upstreamed independently of the
private bridge UI.

The plugin icon follows the selected enabled plugin, respects used/remaining mode,
and reads that plugin's primary/secondary windows. Expired windows are unknown.
The account window displays each named pool and account window independently.
Disabled accounts stay visible but do not contribute capacity; they are not probed.
Failed refreshes show a visible warning and disable controls until a fresh read.

The native client uses the selected plugin's HTTPS `BASE_URL`, `BRIDGE_TOKEN` and
optional distinct `CONTROL_TOKEN`. It sends credentials only to that configured
origin and refuses redirects. No provider credentials or Beast management key are
stored on the Mac. Control responses must confirm the requested state. A timeout
may happen after a server change; refresh before retrying. Duplicate credentials
for one subscription are managed as a group.

## Updating upstream

Use Homebrew Python 3.14 first on PATH (the upstream test runner requires `waitid`).
Start from a clean `proxy` checkout, then:

```sh
Scripts/proxy_update_upstream.sh vX.Y.Z
Scripts/package_proxy.sh
```

The update script fetches official tags, merges the chosen release, and runs the
upstream checks/tests. It stops on conflicts; resolve them normally or use
`git merge --abort`. It does not force-push, publish a release, or replace the app.
After reviewing and checking the new bundle, push `proxy`. Use merge commits to
preserve upstream ancestry rather than copying source files between repositories.

Manual acceptance: with proxy plugins and optionally a built-in provider such as Cursor enabled, switch tabs, close
the menu and verify the status-bar fill follows each selected pool; check 0%, 100%,
and missing data with fixtures. Open **Accounts and pool…**, check named windows,
reset times, labels, disabled accounts, refresh and failures. Test account writes
with fake credentials in unit tests; use an idempotent real-account request for
live transport proof rather than disrupting a working subscription.

## Packaging, installing and rollback

`Scripts/package_proxy.sh` wraps upstream's existing packaging script and forces
ad-hoc signing, which disables the official Sparkle feed and update checks. It
adds the fork commit to Info.plist and verifies the resulting signature. This
avoids an automatic update silently replacing the custom build. Upstream's signing,
release and publishing workflows are not used for this fork.

Keep the same bundle ID/config paths so the existing plugin approvals and settings
remain available. Quit CodexBar before changing its plugin config or replacing the
bundle. Back up `/Applications/CodexBar.app` and the config first, copy the new bundle,
and restart. Rollback restores the previous bundle and config. Backend read endpoints
remain compatible with the official app. Local builds are ad-hoc signed, not notarized
public releases; a public distribution would need its own signing/update channel.
