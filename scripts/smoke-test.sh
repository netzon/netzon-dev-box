#!/usr/bin/env bash
set -Eeuo pipefail
for tool in claude git python3 uv pyrefly flutter dart sdkmanager java javac rustc cargo fnm node npm bun scc jq rg zip unzip wget dotnet; do
  command -v "$tool" >/dev/null || { echo "Missing: $tool" >&2; exit 1; }
done
[[ "$(id -un)" == runner ]]
[[ -w /workspace ]]
[[ -d "$ANDROID_HOME/platforms/android-36" ]]
[[ -d "$ANDROID_HOME/build-tools/36.0.0" ]]
[[ -x "$ANDROID_HOME/platform-tools/adb" ]]
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
echo 'PASS: toolchain is available to the non-root user'
