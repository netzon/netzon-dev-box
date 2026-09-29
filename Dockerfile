# syntax=docker/dockerfile:1
# Source Dockerfile is MIT licensed. Downloaded tools retain their own licenses.
# amd64-only (x64 .NET, scc, JAVA_HOME): build with `--platform linux/amd64`, as CI does.
#
# Build targets (`docker build --target <name>`):
#   base  Ubuntu, CLI/network/data tools, Claude Code, Python/uv, Rust, Bun, Node, Playwright + Chromium
#   full  base + Java 21, Android SDK, Flutter, .NET (published as `latest`)
#
# Stages are ordered by how rarely they change: OS packages, then language toolchains, then browsers,
# then (full only) the mobile and .NET SDKs. Claude Code and the small image files come last in both
# targets, so a CLAUDE_VERSION bump re-pulls one small layer instead of the whole image.

# Version pins, in one place. Each stage that uses one re-declares it without a default.
ARG CLAUDE_VERSION=2.1.284
ARG PLAYWRIGHT_VERSION=1.63.0
ARG SCC_VERSION=v4.1.0
ARG DOTNET10_VERSION=10.0.401
ARG DOTNET11_VERSION=11.0.100-rc.1.26425.128

############################################################################################
# os: packages, the runner user, directories and environment shared by every target.
FROM ubuntu:26.04 AS os
RUN test "$(dpkg --print-architecture)" = amd64 \
    || { echo 'This image is amd64-only: build with --platform linux/amd64' >&2; exit 1; }
ARG DEBIAN_FRONTEND=noninteractive

# Keep downloaded .debs so the BuildKit cache mounts below make package-list changes cheap to rebuild
# (Docker's documented pattern). The mounts hold the apt lists too, so nothing apt-related lands in a layer.
RUN rm -f /etc/apt/apt.conf.d/docker-clean \
    && echo 'Binary::apt::APT::Keep-Downloaded-Packages "true";' > /etc/apt/apt.conf.d/keep-cache

# Build tools; the everyday CLI, network and data tools that agents otherwise rebuild in scratch and
# lose on the next restart; bubblewrap and socat for Claude Code's Linux sandbox; and the Chromium
# runtime libraries and fonts from Playwright's ubuntu26.04 dependency list (re-sync when bumping
# Playwright). Xvfb is for headed browser runs. The `cmake`/`sqlite`/`graphviz` set comes from the
# Anthropic-cloud parity review.
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    apt-get update && apt-get install -y --no-install-recommends \
    bash ca-certificates curl git unzip zip wget jq ripgrep xz-utils tar tzdata \
    build-essential cmake pkg-config libssl-dev libsqlite3-dev \
    gh less file tree rsync openssh-client bsdextrautils time procps htop lsof strace nano tmux fzf libcap2-bin \
    bind9-dnsutils iputils-ping netcat-openbsd socat bubblewrap \
    sqlite3 graphviz imagemagick shellcheck fd-find \
    libasound2t64 libatk-bridge2.0-0t64 libatk1.0-0t64 libatspi2.0-0t64 libcairo2 libcups2t64 \
    libdbus-1-3 libdrm2 libgbm1 libglib2.0-0t64 libnspr4 libnss3 libpango-1.0-0 libx11-6 libxcb1 \
    libxcomposite1 libxdamage1 libxext6 libxfixes3 libxkbcommon0 libxrandr2 \
    xvfb xauth libfontconfig1 libfreetype6 fonts-liberation fonts-noto-color-emoji fonts-unifont \
    fonts-ipafont-gothic fonts-wqy-zenhei fonts-tlwg-loma-otf fonts-freefont-ttf xfonts-cyrillic xfonts-scalable \
    fonts-dejavu-core \
    && { command -v fd >/dev/null || ln -s "$(command -v fdfind)" /usr/local/bin/fd; } \
    && groupadd --gid 10001 runner \
    && useradd --uid 10001 --gid 10001 --create-home --shell /bin/bash runner \
    && install -d -o runner -g runner /workspace /opt/playwright /opt/ms-playwright /opt/venv /opt/corepack \
         /cache /cache/bun /cache/npm /cache/uv /cache/gradle /cache/nuget \
    && install -d -m 1777 /tmp/.X11-unix \
    && install -d -m 755 /etc/claude-code /etc/claude-code/CLAUDE.d

# Package-manager caches that start empty share the /cache prefix, so a deployment can mount one
# persistent volume (writable by UID 10001) there and restarted sessions install from cache. Caches that
# the build seeds (Corepack's package managers, Flutter's pub cache) stay in the image on purpose: a
# volume mounted over them would hide the seed and make the first use need the network again.
# Claude Code is pinned by CLAUDE_VERSION, so its updater is off.
ENV HOME=/home/runner \
    CARGO_HOME=/home/runner/.cargo \
    RUSTUP_HOME=/home/runner/.rustup \
    FNM_DIR=/home/runner/.fnm \
    BUN_INSTALL=/home/runner/.bun \
    BUN_INSTALL_CACHE_DIR=/cache/bun \
    npm_config_cache=/cache/npm \
    COREPACK_HOME=/opt/corepack \
    COREPACK_ENABLE_DOWNLOAD_PROMPT=0 \
    COREPACK_DEFAULT_TO_LATEST=0 \
    UV_CACHE_DIR=/cache/uv \
    GRADLE_USER_HOME=/cache/gradle \
    NUGET_PACKAGES=/cache/nuget \
    PLAYWRIGHT_BROWSERS_PATH=/opt/ms-playwright \
    NODE_PATH=/opt/playwright/node_modules \
    DISABLE_AUTOUPDATER=1 \
    PATH=/home/runner/.node-bin:/home/runner/.local/bin:/home/runner/.cargo/bin:/home/runner/.fnm:/home/runner/.bun/bin:/opt/venv/bin:/usr/local/bin:/usr/bin:/bin

USER runner
SHELL ["/bin/bash", "-o", "pipefail", "-c"]

############################################################################################
# toolchains: Python, Rust, Bun and Node, all ready to use offline.
FROM os AS toolchains
# Python 3.13 via uv. `python3` resolves to /opt/venv, a default environment with pip and the usual
# data-analysis and image libraries; it sits late on PATH so an activated project venv wins. Pyrefly
# and Ruff are uv tools. Rust is the minimal stable profile. Node is the current LTS through fnm, with
# Corepack's pnpm and yarn downloaded now (so they start offline; COREPACK_DEFAULT_TO_LATEST=0 keeps
# Corepack from consulting the registry outside a project) and TypeScript installed globally. pnpm 12
# fetches its native binary into COREPACK_HOME on first run, so it is run once here. uv's own
# python shims in ~/.local/bin are removed so every `python*` name means the /opt/venv interpreter.
# Build-time caches are cleaned afterwards; `uv cache clean` deletes the directory itself, so the
# /cache mount points are recreated (the smoke test checks they exist and are writable).
RUN set -eux; \
    curl -fsSL https://astral.sh/uv/install.sh -o /tmp/install-uv.sh; \
    UV_NO_MODIFY_PATH=1 sh /tmp/install-uv.sh; \
    uv python install 3.13; \
    uv venv --seed --allow-existing --python 3.13 /opt/venv; \
    uv pip install --python /opt/venv/bin/python \
      pillow numpy pandas scipy matplotlib requests beautifulsoup4 lxml sqlalchemy; \
    uv tool install pyrefly; \
    uv tool install ruff; \
    uv cache clean; mkdir -p "$UV_CACHE_DIR"; \
    rm -f "$HOME"/.local/bin/python "$HOME"/.local/bin/python3 "$HOME"/.local/bin/python3.*; \
    curl -fsSL https://sh.rustup.rs -o /tmp/install-rust.sh; \
    sh /tmp/install-rust.sh -y --no-modify-path --profile minimal; \
    curl -fsSL https://bun.com/install -o /tmp/install-bun.sh; \
    bash /tmp/install-bun.sh; \
    curl -fsSL https://fnm.vercel.app/install -o /tmp/install-fnm.sh; \
    bash /tmp/install-fnm.sh --install-dir "$FNM_DIR" --skip-shell; \
    fnm install --lts; \
    node_binary="$(find "$FNM_DIR/node-versions" -type f -path '*/installation/bin/node' -print -quit)"; \
    test -n "$node_binary"; \
    node_bin_dir="$(dirname "$node_binary")"; \
    export PATH="$node_bin_dir:$PATH"; \
    if ! test -e "$node_bin_dir/corepack"; then npm install -g corepack; fi; \
    npm install -g typescript; \
    mkdir -p "$HOME/.node-bin"; \
    for bin in node npm npx corepack tsc; do ln -s "$node_bin_dir/$bin" "$HOME/.node-bin/$bin"; done; \
    corepack enable --install-directory "$HOME/.node-bin"; \
    corepack install -g pnpm@latest yarn@latest; \
    pnpm --version; \
    npm cache clean --force; mkdir -p "$npm_config_cache"; \
    rm -f /tmp/install-uv.sh /tmp/install-rust.sh /tmp/install-bun.sh /tmp/install-fnm.sh; \
    test "$(command -v python3)" = /opt/venv/bin/python3; \
    python3 --version; python3 -c 'import PIL, numpy, pandas'; pyrefly --version; ruff --version; \
    cargo --version; bun --version; node --version; tsc --version; \
    COREPACK_ENABLE_NETWORK=0 pnpm --version; COREPACK_ENABLE_NETWORK=0 yarn --version

############################################################################################
# browsers: Playwright with Chromium, plus scc. This is the last stage shared by both targets.
FROM toolchains AS browsers
ARG PLAYWRIGHT_VERSION
# playwright and @playwright/test live in /opt/playwright so scripts anywhere can load them without an
# npm install: require() through NODE_PATH, ESM through the absolute path. `playwright` is on PATH, and
# linked into npm's global bin so `npx playwright` from any directory uses this version offline.
# Chromium and Chrome Headless Shell go in the runner-writable browser directory, so projects pinned to
# another Playwright version can `npx playwright install chromium` without root. ~/.cache/ms-playwright
# points there too, for environments that drop PLAYWRIGHT_BROWSERS_PATH.
USER runner
RUN set -eux; \
    cd /opt/playwright; \
    printf '{"name":"dev-box-playwright","private":true}\n' > package.json; \
    npm install --save-exact "playwright@${PLAYWRIGHT_VERSION}" "@playwright/test@${PLAYWRIGHT_VERSION}"; \
    ln -s /opt/playwright/node_modules/.bin/playwright "$HOME/.node-bin/playwright"; \
    ln -s /opt/playwright/node_modules/.bin/playwright "$(npm prefix -g)/bin/playwright"; \
    mkdir -p "$HOME/.cache"; \
    ln -s "$PLAYWRIGHT_BROWSERS_PATH" "$HOME/.cache/ms-playwright"; \
    playwright install chromium; \
    bins="$(find "$PLAYWRIGHT_BROWSERS_PATH" -type f \( -name chrome -o -name chrome-headless-shell \))"; \
    test "$(wc -l <<< "$bins")" -eq 2; \
    if ldd $bins | grep 'not found'; then exit 1; fi; \
    npm cache clean --force; mkdir -p "$npm_config_cache"; \
    playwright --version

USER root
ARG SCC_VERSION
RUN set -eux; \
    asset='scc_Linux_x86_64.tar.gz'; \
    release="https://github.com/boyter/scc/releases/download/${SCC_VERSION}"; \
    curl -fsSL "$release/$asset" -o /tmp/scc.tar.gz; \
    curl -fsSL "$release/checksums.txt" -o /tmp/scc-checksums; \
    expected="$(awk -v file="$asset" '$2 == file || $2 == "*"file {print $1}' /tmp/scc-checksums)"; \
    test -n "$expected"; \
    echo "$expected  /tmp/scc.tar.gz" | sha256sum -c -; \
    mkdir -p /tmp/scc-extract; \
    tar -xzf /tmp/scc.tar.gz -C /tmp/scc-extract; \
    binary="$(find /tmp/scc-extract -type f -name scc -print -quit)"; \
    test -n "$binary"; \
    install -m 755 "$binary" /usr/local/bin/scc; \
    rm -rf /tmp/scc.tar.gz /tmp/scc-checksums /tmp/scc-extract

############################################################################################
# sdks (full only): Java, Android SDK, Flutter and .NET.
FROM browsers AS sdks
USER root
ARG DEBIAN_FRONTEND=noninteractive
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    apt-get update && apt-get install -y --no-install-recommends \
    openjdk-21-jdk-headless libicu78 libgssapi-krb5-2 zlib1g libunwind8 libbrotli1 \
    && install -d -o runner -g runner /opt/android-sdk /opt/flutter /home/runner/dotnet
# The .NET first-run step neither generates a dev certificate nor edits PATH, so `dotnet` starts clean.
ENV JAVA_HOME=/usr/lib/jvm/java-21-openjdk-amd64 \
    ANDROID_HOME=/opt/android-sdk \
    ANDROID_SDK_ROOT=/opt/android-sdk \
    DOTNET_ROOT=/home/runner/dotnet \
    DOTNET_CLI_HOME=/home/runner \
    DOTNET_CLI_TELEMETRY_OPTOUT=1 \
    DOTNET_NOLOGO=1 \
    DOTNET_GENERATE_ASPNET_CERTIFICATE=0 \
    DOTNET_ADD_GLOBAL_TOOLS_TO_PATH=0 \
    PATH=/home/runner/dotnet:/opt/flutter/bin:/opt/android-sdk/cmdline-tools/latest/bin:/opt/android-sdk/platform-tools:${PATH}
USER runner

# License acceptance is explicit. Review Google's terms before setting the build arg.
ARG ACCEPT_ANDROID_LICENSES=0
RUN test "$ACCEPT_ANDROID_LICENSES" = 1
RUN set -eux; \
    curl -fsSL https://dl.google.com/android/repository/commandlinetools-linux-15859902_latest.zip -o /tmp/android.zip; \
    echo '4e4c464f145a7512b57d088ac6c278c03c9eea610886b35a5e0804e74eedf583  /tmp/android.zip' | sha256sum -c -; \
    unzip -q /tmp/android.zip -d /tmp/android-cli; \
    mkdir -p "$ANDROID_HOME/cmdline-tools/latest"; \
    cp -a /tmp/android-cli/cmdline-tools/. "$ANDROID_HOME/cmdline-tools/latest/"; \
    rm -rf /tmp/android.zip /tmp/android-cli; \
    (set +o pipefail; yes | sdkmanager --sdk_root="$ANDROID_HOME" --licenses >/dev/null); \
    sdkmanager --sdk_root="$ANDROID_HOME" 'platform-tools' 'platforms;android-36' 'build-tools;36.0.0'; \
    test -d "$ANDROID_HOME/platforms/android-36"

RUN set -eux; \
    git clone --depth 1 --branch stable https://github.com/flutter/flutter.git /opt/flutter; \
    flutter config --no-analytics; \
    flutter config --android-sdk "$ANDROID_HOME"; \
    flutter precache --android; \
    flutter --version

# .NET 10 and the specified .NET 11 release candidate share one private install root.
# The .NET 11 archive is checked against Microsoft's published SHA-512 digest.
ARG DOTNET10_VERSION
ARG DOTNET11_VERSION
RUN set -eux; \
    curl -fsSL https://dot.net/v1/dotnet-install.sh -o /tmp/dotnet-install.sh; \
    bash /tmp/dotnet-install.sh --version "$DOTNET10_VERSION" --architecture x64 --install-dir "$DOTNET_ROOT" --no-path; \
    curl -fsSL --retry 3 "https://builds.dotnet.microsoft.com/dotnet/Sdk/${DOTNET11_VERSION}/dotnet-sdk-${DOTNET11_VERSION}-linux-x64.tar.gz" -o /tmp/dotnet11.tar.gz; \
    echo '608518577aab9db33db92ebd74f0fc9bfbcc7b3d473619f4731aca2edba80af6c571a38d5be6994862fc4679f6f3d13db767712fcb6f70a7683974a18824a0cc  /tmp/dotnet11.tar.gz' | sha512sum -c -; \
    tar -xzf /tmp/dotnet11.tar.gz -C "$DOTNET_ROOT"; \
    rm -f /tmp/dotnet-install.sh /tmp/dotnet11.tar.gz; \
    dotnet --list-sdks | grep -F "${DOTNET10_VERSION} ["; \
    dotnet --list-sdks | grep -F "${DOTNET11_VERSION} ["

############################################################################################
# Final targets. The tail is repeated in both so that Claude Code and the image files, which change
# most often, are the last layers of each. Keep the two tails identical apart from the fragment set.
#
# /etc/claude-code and CLAUDE.d were created with mode 755 in the os stage: COPY --chmod gives the
# directories it creates the file's mode (moby/buildkit#5943), and a 0644 directory hides CLAUDE.md
# from the runner user. /etc/claude-code/managed-settings.json is the matching hook for organisation-
# wide Claude Code settings; the image deliberately ships none (the session runtime supplies its own).

FROM browsers AS base
USER root
COPY --chmod=755 image/usr/local/bin/ /usr/local/bin/
COPY --chmod=644 image/etc/claude-code/CLAUDE.d/ /etc/claude-code/CLAUDE.d/
RUN claude-md-assemble
USER runner
ARG CLAUDE_VERSION
# Native Claude Code is installed from its public installer; no credentials are baked in.
RUN set -eux; \
    curl -fsSL https://claude.ai/install.sh -o /tmp/install-claude.sh; \
    bash /tmp/install-claude.sh "$CLAUDE_VERSION"; \
    rm -f /tmp/install-claude.sh; \
    claude --version
WORKDIR /workspace
ENTRYPOINT ["claude"]

FROM sdks AS full
USER root
COPY --chmod=755 image/usr/local/bin/ /usr/local/bin/
COPY --chmod=644 image/etc/claude-code/CLAUDE.d/ /etc/claude-code/CLAUDE.d/
COPY --chmod=644 image/etc/claude-code/CLAUDE.full.d/ /etc/claude-code/CLAUDE.d/
RUN claude-md-assemble
USER runner
ARG CLAUDE_VERSION
# Native Claude Code is installed from its public installer; no credentials are baked in.
RUN set -eux; \
    curl -fsSL https://claude.ai/install.sh -o /tmp/install-claude.sh; \
    bash /tmp/install-claude.sh "$CLAUDE_VERSION"; \
    rm -f /tmp/install-claude.sh; \
    claude --version
WORKDIR /workspace
ENTRYPOINT ["claude"]
