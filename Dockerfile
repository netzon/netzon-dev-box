# syntax=docker/dockerfile:1
# Source Dockerfile is MIT licensed. Downloaded tools retain their own licenses.
FROM --platform=linux/amd64 ubuntu:26.04

ARG DEBIAN_FRONTEND=noninteractive
ARG CLAUDE_VERSION=2.1.284
ARG DOTNET10_VERSION=10.0.401
ARG DOTNET11_VERSION=11.0.100-rc.1.26425.128
ARG SCC_VERSION=v4.1.0
ARG ACCEPT_ANDROID_LICENSES=0

RUN apt-get update && apt-get install -y --no-install-recommends \
    bash ca-certificates curl git unzip zip wget jq ripgrep \
    xz-utils tar build-essential pkg-config libssl-dev \
    openjdk-21-jdk-headless libicu78 libgssapi-krb5-2 \
    zlib1g libunwind8 libbrotli1 tzdata \
    && rm -rf /var/lib/apt/lists/* \
    && groupadd --gid 10001 runner \
    && useradd --uid 10001 --gid 10001 --create-home --shell /bin/bash runner \
    && mkdir -p /workspace /opt/android-sdk /opt/flutter /home/runner/dotnet \
    && chown -R runner:runner /workspace /opt/android-sdk /opt/flutter /home/runner/dotnet

ENV HOME=/home/runner \
    JAVA_HOME=/usr/lib/jvm/java-21-openjdk-amd64 \
    ANDROID_HOME=/opt/android-sdk \
    ANDROID_SDK_ROOT=/opt/android-sdk \
    CARGO_HOME=/home/runner/.cargo \
    RUSTUP_HOME=/home/runner/.rustup \
    FNM_DIR=/home/runner/.fnm \
    BUN_INSTALL=/home/runner/.bun \
    DOTNET_ROOT=/home/runner/dotnet \
    DOTNET_CLI_HOME=/home/runner \
    DOTNET_CLI_TELEMETRY_OPTOUT=1 \
    DOTNET_NOLOGO=1 \
    PATH=/home/runner/dotnet:/home/runner/.node-bin:/home/runner/.local/bin:/home/runner/.cargo/bin:/home/runner/.fnm:/home/runner/.bun/bin:/opt/flutter/bin:/opt/android-sdk/cmdline-tools/latest/bin:/opt/android-sdk/platform-tools:/usr/local/bin:/usr/bin:/bin

USER runner
SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# Native Claude Code is installed from its public installer; no credentials are baked in.
RUN set -eux; \
    curl -fsSL https://claude.ai/install.sh -o /tmp/install-claude.sh; \
    bash /tmp/install-claude.sh "$CLAUDE_VERSION"; \
    rm -f /tmp/install-claude.sh; \
    claude --version

# Python (via uv), Pyrefly, Rust/Cargo, Bun, fnm, and Node LTS.
RUN set -eux; \
    curl -fsSL https://astral.sh/uv/install.sh -o /tmp/install-uv.sh; \
    UV_NO_MODIFY_PATH=1 sh /tmp/install-uv.sh; \
    uv python install 3.13; \
    ln -s "$(uv python find 3.13)" "$HOME/.local/bin/python3"; \
    uv tool install pyrefly; \
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
    mkdir -p "$HOME/.node-bin"; \
    for bin in node npm npx corepack; do \
      if test -e "$node_bin_dir/$bin"; then ln -s "$node_bin_dir/$bin" "$HOME/.node-bin/$bin"; fi; \
    done; \
    rm -f /tmp/install-uv.sh /tmp/install-rust.sh /tmp/install-bun.sh /tmp/install-fnm.sh; \
    python3 --version; pyrefly --version; cargo --version; bun --version; node --version

# License acceptance is explicit. Review Google's terms before setting the build arg.
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
RUN set -eux; \
    curl -fsSL https://dot.net/v1/dotnet-install.sh -o /tmp/dotnet-install.sh; \
    bash /tmp/dotnet-install.sh --version "$DOTNET10_VERSION" --architecture x64 --install-dir "$DOTNET_ROOT" --no-path; \
    curl -fsSL --retry 3 "https://builds.dotnet.microsoft.com/dotnet/Sdk/${DOTNET11_VERSION}/dotnet-sdk-${DOTNET11_VERSION}-linux-x64.tar.gz" -o /tmp/dotnet11.tar.gz; \
    echo '608518577aab9db33db92ebd74f0fc9bfbcc7b3d473619f4731aca2edba80af6c571a38d5be6994862fc4679f6f3d13db767712fcb6f70a7683974a18824a0cc  /tmp/dotnet11.tar.gz' | sha512sum -c -; \
    tar -xzf /tmp/dotnet11.tar.gz -C "$DOTNET_ROOT"; \
    rm -f /tmp/dotnet-install.sh /tmp/dotnet11.tar.gz; \
    dotnet --list-sdks | grep -F "${DOTNET10_VERSION} ["; \
    dotnet --list-sdks | grep -F "${DOTNET11_VERSION} ["

USER root
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

USER runner
WORKDIR /workspace
ENTRYPOINT ["claude"]
