#!/usr/bin/env bash
set -Eeuo pipefail
trap 'echo "FAIL line $LINENO: $BASH_COMMAND" >&2' ERR
for tool in claude git python3 uv pyrefly flutter dart sdkmanager java javac rustc cargo fnm node npm bun scc jq rg zip unzip wget dotnet playwright xvfb-run chromium-gpu-check; do
  command -v "$tool" >/dev/null || { echo "Missing: $tool" >&2; exit 1; }
done
[[ "$(id -un)" == runner ]]
[[ -w /workspace ]]
[[ -d "$ANDROID_HOME/platforms/android-36" ]]
[[ -d "$ANDROID_HOME/build-tools/36.0.0" ]]
[[ -x "$ANDROID_HOME/platform-tools/adb" ]]
[[ -w "$PLAYWRIGHT_BROWSERS_PATH" ]]
[[ -r /etc/claude-code/CLAUDE.md ]]
claude --version
python3 -c 'print("Python OK")'
uv --version
pyrefly --version
flutter --version
rustc --version
cargo --version
fnm --version
node --version
npm --version
bun --version
scc --version
jq --version
rg --version
sdkmanager --version
java -version
zip -v >/dev/null
unzip -v >/dev/null
wget --version >/dev/null
dotnet --list-sdks
dotnet --list-sdks | grep -Fq '10.0.401 ['
dotnet --list-sdks | grep -Fq '11.0.100-rc.1.26425.128 ['
tmp="$(mktemp -d)"
trap 'rm -rf -- "$tmp"' EXIT
printf '{"sdk":{"version":"10.0.401","rollForward":"disable"}}\n' > "$tmp/global.json"
( cd "$tmp" && [[ "$(dotnet --version)" == 10.0.401 ]] )
printf '{"sdk":{"version":"11.0.100-rc.1.26425.128","allowPrerelease":true,"rollForward":"disable"}}\n' > "$tmp/global.json"
( cd "$tmp" && [[ "$(dotnet --version)" == 11.0.100-rc.1.26425.128 ]] )
[[ "$(playwright --version)" == 'Version 1.63.0' ]]
[[ -L "$HOME/.cache/ms-playwright" ]]
# Ad-hoc scripts outside any project reach the preinstalled Playwright without an npm install.
( cd "$tmp" && [[ "$(npx --no-install playwright --version)" == 'Version 1.63.0' ]] )
chrome="$(cd "$tmp" && node -p "require('playwright').chromium.executablePath()")"
[[ -x "$chrome" ]]
( cd "$tmp" && node -e "require('@playwright/test')" )
printf "import { chromium } from '/opt/playwright/node_modules/playwright/index.mjs';\nconsole.log(chromium.executablePath());\n" > "$tmp/probe.mjs"
[[ "$(node "$tmp/probe.mjs")" == "$chrome" ]]
chromium-gpu-check
xvfb-run -a chromium-gpu-check --headed
echo 'PASS: toolchain is available to the non-root user'
