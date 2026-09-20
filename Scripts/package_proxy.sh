#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
# Upstream's ad-hoc packaging disables the Sparkle feed and automatic checks.
# Do not sign this fork through the upstream release workflow.
CODEXBAR_SIGNING=adhoc "$ROOT/Scripts/package_app.sh" release
APP="$ROOT/CodexBar.app"
python3 - "$APP/Contents/Info.plist" <<'PY'
import plistlib, subprocess, sys
from pathlib import Path
p = Path(sys.argv[1])
data = plistlib.loads(p.read_bytes())
assert not data.get('SUFeedURL') and data.get('SUEnableAutomaticChecks') is False
data['ProxyForkCommit'] = subprocess.check_output(['git', 'rev-parse', 'HEAD'], text=True).strip()
data['ProxyForkRepository'] = 'https://github.com/nckrtl/CodexBar'
p.write_bytes(plistlib.dumps(data))
PY
codesign --force --sign - --preserve-metadata=entitlements,requirements,flags "$APP"
codesign --verify --deep --strict "$APP"
echo "Packaged $APP with upstream automatic updates disabled."
