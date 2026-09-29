#!/usr/bin/env bash
# Usage: smoke-test.sh [base|full]   (default: full). Runs inside the image as the runner user.
set -Eeuo pipefail
trap 'echo "FAIL line $LINENO: $BASH_COMMAND" >&2' ERR
target="${1:-full}"
[[ "$target" == base || "$target" == full ]] || { echo "usage: $0 [base|full]" >&2; exit 2; }

# --- Tools present in both targets ---------------------------------------------------------------
for tool in claude git curl wget zip unzip jq rg fd fzf tree less file column time ps htop lsof strace \
    tmux nano rsync ssh scp gh shellcheck scc sqlite3 dot magick dig ping nc socat bwrap \
    gcc make cmake pkg-config \
    python3 pip uv uvx pyrefly ruff rustc cargo fnm node npm npx corepack pnpm yarn tsc bun \
    playwright xvfb-run chromium-gpu-check; do
  command -v "$tool" >/dev/null || { echo "Missing: $tool" >&2; exit 1; }
done
[[ "$(id -un)" == runner ]]
[[ -w /workspace ]]
[[ -w "$PLAYWRIGHT_BROWSERS_PATH" ]]
[[ -r /etc/claude-code/CLAUDE.md ]]
grep -q '<!-- 10-browser-testing.md -->' /etc/claude-code/CLAUDE.md
grep -q '<!-- 20-toolchain.md -->' /etc/claude-code/CLAUDE.md
grep -q '<!-- 30-caches.md -->' /etc/claude-code/CLAUDE.md
grep -q 'chromium.launch' /etc/claude-code/CLAUDE.md
[[ "$DISABLE_AUTOUPDATER" == 1 ]]

# Package-manager caches share the mountable /cache prefix and are writable by runner.
for dir in bun npm uv gradle nuget; do [[ -d "/cache/$dir" && -w "/cache/$dir" ]]; done
[[ "$BUN_INSTALL_CACHE_DIR" == /cache/bun ]]
[[ "$npm_config_cache" == /cache/npm ]]
[[ "$UV_CACHE_DIR" == /cache/uv ]]
[[ "$GRADLE_USER_HOME" == /cache/gradle ]]
[[ "$NUGET_PACKAGES" == /cache/nuget ]]
[[ "$COREPACK_HOME" == /opt/corepack && -w /opt/corepack ]]

claude --version
git --version
gh --version
jq --version
rg --version
fd --version
fzf --version
tree --version
column --version
shellcheck --version
scc --version
sqlite3 -version
dot -V
magick -version
tmux -V
rsync --version >/dev/null
ssh -V
zip -v >/dev/null
unzip -v >/dev/null
wget --version >/dev/null
cmake --version >/dev/null
bwrap --version
socat -V >/dev/null

# Python: python3 is the /opt/venv interpreter with the data-analysis and image libraries.
[[ "$(command -v python3)" == /opt/venv/bin/python3 ]]
[[ "$(command -v python)" == /opt/venv/bin/python ]]
python3 --version
python3 -m pip --version
python3 -c 'import PIL, numpy, pandas, scipy, matplotlib, requests, bs4, lxml, sqlalchemy; print("Python packages OK")'
uv --version
ruff --version
pyrefly --version

# Rust and JavaScript toolchains.
rustc --version
cargo --version
fnm --version
node --version
npm --version
tsc --version
bun --version

tmp="$(mktemp -d)"
trap 'rm -rf -- "$tmp"' EXIT
# pnpm and yarn resolve through Corepack from the image without a download.
( cd "$tmp" && COREPACK_ENABLE_NETWORK=0 pnpm --version && COREPACK_ENABLE_NETWORK=0 yarn --version )

# Playwright: pinned version, browsers in place, reachable from ad-hoc scripts without an npm install.
[[ "$(playwright --version)" == 'Version 1.63.0' ]]
[[ -L "$HOME/.cache/ms-playwright" ]]
( cd "$tmp" && [[ "$(npx --no-install playwright --version)" == 'Version 1.63.0' ]] )
chrome="$(cd "$tmp" && node -p "require('playwright').chromium.executablePath()")"
[[ -x "$chrome" ]]
( cd "$tmp" && node -e "require('@playwright/test')" )
printf "import { chromium } from '/opt/playwright/node_modules/playwright/index.mjs';\nconsole.log(chromium.executablePath());\n" > "$tmp/probe.mjs"
[[ "$(node "$tmp/probe.mjs")" == "$chrome" ]]
chromium-gpu-check
xvfb-run -a chromium-gpu-check --headed

# --- Target-specific checks ----------------------------------------------------------------------
if [[ "$target" == base ]]; then
  for tool in flutter dart sdkmanager java dotnet; do
    ! command -v "$tool" >/dev/null || { echo "base image unexpectedly contains: $tool" >&2; exit 1; }
  done
  if grep -q '<!-- 40-mobile-dotnet.md -->' /etc/claude-code/CLAUDE.md; then
    echo 'base image unexpectedly contains the full-image CLAUDE.md fragment' >&2; exit 1
  fi
else
  for tool in flutter dart sdkmanager adb java javac dotnet; do
    command -v "$tool" >/dev/null || { echo "Missing: $tool" >&2; exit 1; }
  done
  grep -q '<!-- 40-mobile-dotnet.md -->' /etc/claude-code/CLAUDE.md
  [[ -d "$ANDROID_HOME/platforms/android-36" ]]
  [[ -d "$ANDROID_HOME/build-tools/36.0.0" ]]
  [[ -x "$ANDROID_HOME/platform-tools/adb" ]]
  [[ -d "$JAVA_HOME" ]]
  flutter --version
  sdkmanager --version
  java -version
  dotnet --list-sdks
  dotnet --list-sdks | grep -Fq '10.0.401 ['
  dotnet --list-sdks | grep -Fq '11.0.100-rc.1.26425.128 ['
  printf '{"sdk":{"version":"10.0.401","rollForward":"disable"}}\n' > "$tmp/global.json"
  ( cd "$tmp" && [[ "$(dotnet --version)" == 10.0.401 ]] )
  printf '{"sdk":{"version":"11.0.100-rc.1.26425.128","allowPrerelease":true,"rollForward":"disable"}}\n' > "$tmp/global.json"
  ( cd "$tmp" && [[ "$(dotnet --version)" == 11.0.100-rc.1.26425.128 ]] )
fi
echo "PASS: $target toolchain is available to the non-root user"
