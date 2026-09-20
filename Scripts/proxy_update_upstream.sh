#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ $# -ne 1 || "$1" != v[0-9]* ]]; then
  echo "Usage: Scripts/proxy_update_upstream.sh v0.62.0" >&2
  exit 1
fi
[[ "$(git branch --show-current)" == proxy ]] || { echo "Switch to branch proxy first." >&2; exit 1; }
[[ -z "$(git status --porcelain)" ]] || { echo "Commit or stash local changes first." >&2; exit 1; }
[[ "$(git remote get-url upstream)" == https://github.com/steipete/CodexBar.git ]] || {
  echo "Expected the official upstream remote." >&2; exit 1;
}
git fetch upstream --tags
target=$(git rev-parse --verify "refs/tags/$1^{commit}")
git merge --no-edit "$target"
make check
make test
echo "Upstream merged and checked. Review changes, run Scripts/package_proxy.sh, then install and push."
