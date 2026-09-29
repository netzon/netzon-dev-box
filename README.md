# Netzon Dev Box

Public, Linux/amd64 development container for Claude Code sessions and interactive development. This repository builds **from Ubuntu 26.04 on the first build**; it does not inherit a private image or contain tenant configuration, work orders, tokens, or Git credentials.

## Two targets

The Dockerfile has two build targets, published as separate tags from the same source:

| Target | Tag | Contents |
| --- | --- | --- |
| `base` | `dev-box:base` | Ubuntu 26.04, CLI/network/data tools, Claude Code, Python 3.13 via uv, Rust, Bun, Node LTS, Playwright with Chromium |
| `full` | `dev-box:full` and `dev-box:latest` | `base` plus Java 21, Android SDK, Flutter stable, .NET SDK 10 and 11 RC |

Web and backend sessions never touch the mobile or .NET SDKs, which are about half of the full image, so pointing those environments at `base` roughly halves the pull on a new node. Both targets share every layer up to the SDK stages, and Claude Code plus the small image files are the last layers of each, so a `CLAUDE_VERSION` bump re-pulls one small layer rather than the whole image.

## Included

Everything runs as the non-root `runner` user (UID/GID 10001); `/workspace` is writable and the image entrypoint is `claude`.

- **Claude Code** (default 2.1.284, pinned; `DISABLE_AUTOUPDATER=1`).
- **CLI tools:** `gh`, `jq`, `ripgrep`, `fd`, `fzf`, `tree`, `less`, `file`, `column`, `time`, `procps`, `htop`, `lsof`, `strace`, `tmux`, `nano`, `rsync`, `openssh-client`, `shellcheck`, `scc`, `sqlite3`, Graphviz, ImageMagick 7, `zip`/`unzip`, `wget`, `curl`, `xz`.
- **Network:** `dig` (bind9-dnsutils), `ping`, `nc` (netcat-openbsd), `socat`; `bubblewrap` and `socat` are what Claude Code's Linux sandbox uses (running it also needs the container runtime to allow unprivileged user namespaces, a deployment setting).
- **Build:** `build-essential`, `cmake`, `pkg-config`, OpenSSL and SQLite headers.
- **Python:** 3.13 via uv. `python3` resolves to `/opt/venv`, a default environment with `pip`, Pillow, NumPy, pandas, SciPy, Matplotlib, Requests, Beautiful Soup, lxml and SQLAlchemy. It sits late on `PATH`, so an activated project virtualenv wins. `uv`, `uvx`, `ruff` and `pyrefly` are installed as tools.
- **JavaScript/TypeScript:** Node LTS via fnm, `npm`, `npx`, Corepack with `pnpm` and `yarn` already downloaded (they start offline; a project's `packageManager` field can select another version), `tsc`, Bun.
- **Rust:** stable, minimal profile.
- **Browsers:** Playwright 1.63.0 and `@playwright/test` with Chromium and Chrome Headless Shell, their system libraries, fonts and Xvfb (see below).
- **Full only:** Java 21, Android SDK command-line tools / API 36 / build-tools 36.0.0 / platform-tools, Flutter stable with Android artifacts precached, .NET SDK 10.0.401 and 11.0.100-rc.1.26425.128.

The Android installation does **not** include Android Studio, an emulator, an NDK, or a connected device. No environment secret or Docker socket is mounted by this image; those are deployment decisions outside this repository. A large image and substantial CI disk usage are expected; test runner capacity before relying on hosted CI.

Deliberately left out: JupyterLab (heavy and interactive; `uv pip install jupyterlab` into `/opt/venv` works when needed), `fuse3` (needs `/dev/fuse` passed into the container), a second Node line and `flutter precache --web` (add them downstream if a project needs them).

## Restarts

A session may be restarted into a fresh container at any time. What survives is the image and, if the deployment mounts one, the `/cache` volume. The scratchpad, `/tmp` and the `/workspace` checkout do not survive, so anything worth keeping must be committed and pushed. The managed `CLAUDE.md` tells agents this, and lists what is preinstalled so they stop rebuilding tools in scratch on every restart.

## Caches

Package-manager caches that start empty share one prefix, created empty and `runner`-owned in the image:

| Variable | Value |
| --- | --- |
| `BUN_INSTALL_CACHE_DIR` | `/cache/bun` |
| `npm_config_cache` | `/cache/npm` |
| `UV_CACHE_DIR` | `/cache/uv` |
| `GRADLE_USER_HOME` | `/cache/gradle` |
| `NUGET_PACKAGES` | `/cache/nuget` |

With nothing mounted this behaves like any other directory. When the deployment mounts a persistent volume at `/cache` (per node or per tenant, writable by UID 10001), the first `bun install`, `npm ci`, `uv sync`, Gradle or NuGet restore after a restart is served from cache instead of the registry. No application data is in the image; the cache fills from whatever sessions install.

Caches that the build seeds stay inside the image on purpose: Corepack's package managers (`COREPACK_HOME=/opt/corepack`) and Flutter's pub cache (`$HOME/.pub-cache`). A volume mounted over them would hide the seed and make the first `pnpm`, `yarn` or `flutter` call need the network again. `CARGO_HOME` also stays in `$HOME` because it holds binaries.

## Managed CLAUDE.md

`/etc/claude-code/CLAUDE.md` is Claude Code's managed policy file: root-owned and read-only for the agent. It is assembled at build time from fragments in `/etc/claude-code/CLAUDE.d/`, in name order, by `claude-md-assemble`:

- `10-browser-testing.md`: the Playwright, WebGL and WebGPU notes below.
- `20-toolchain.md`: what is preinstalled, so agents do not install it again.
- `30-caches.md`: the `/cache` prefix and what does not survive a restart.
- `40-mobile-dotnet.md` (full image only): the mobile and .NET SDKs.

The repository stays generic. To add organisation- or team-specific guidance without editing this repository, either build a downstream image:

```dockerfile
FROM <namespace>/dev-box:base
USER root
COPY --chmod=644 90-team.md /etc/claude-code/CLAUDE.d/
RUN claude-md-assemble
USER runner
```

or bind-mount a file read-only over `/etc/claude-code/CLAUDE.md` at deployment time, with no image change. `/etc/claude-code/managed-settings.json` is the matching hook for organisation-wide Claude Code settings; the image only guarantees the directory exists and intentionally ships no settings file, because the session runtime supplies its own.

## Browser testing without a GPU

Everything Playwright needs is baked into the image, so it is still there when a session resumes in a fresh container (unlike the scratchpad or `/tmp`):

- `playwright` and `@playwright/test` are installed in `/opt/playwright`. Scripts in any directory can load them without an install: `require('playwright')` works through `NODE_PATH`, and ESM uses `import { chromium } from '/opt/playwright/node_modules/playwright/index.mjs'`. A bare ESM `'playwright'` import only resolves inside a project that depends on it. `playwright` is on `PATH`, and `npx playwright` resolves to it from any directory without network access.
- The browsers live in `PLAYWRIGHT_BROWSERS_PATH=/opt/ms-playwright`, which `runner` can write to. `~/.cache/ms-playwright` links there for environments that drop the variable. A project pinned to another Playwright version only needs `npx playwright install chromium`.
- The system dependencies are already installed, so `--with-deps` / `install-deps` (which need root) are never required.

A project-level `node_modules` always takes precedence. A root-level `/node_modules` would make bare ESM imports work everywhere, but it is deliberately not used: npm treats the nearest ancestor containing `node_modules` as the project root, so `npm install` in any folder without a `package.json` would try to install into `/`.

The image expects no GPU. Chromium renders in software with its bundled SwiftShader:

- **WebGL / WebGL2** works with Playwright's default launch options.
- **WebGPU** needs a secure context (`http://localhost`, `127.0.0.1`, `https` or `file://`; not `about:blank`, `data:` or `page.setContent()`) and these launch args:
  ```js
  chromium.launch({ args: ['--enable-unsafe-webgpu', '--enable-features=Vulkan,CDPScreenshotNewSurface', '--use-vulkan=swiftshader', '--use-angle=swiftshader'] })
  ```
  `CDPScreenshotNewSurface` is repeated because Playwright enables it itself and Chromium keeps only the last `--enable-features`. With only some of these flags, the first WebGPU draw crashes the GPU process.
- `chromium-gpu-check` draws with WebGL2 and WebGPU in headless shell and new headless, then checks the pixels in a Playwright screenshot. `xvfb-run -a chromium-gpu-check --headed` does the same headed. The smoke test runs both.

Software rendering is correct but slow. On 2 vCPUs a full-screen animated shader runs at about 12 fps at 1280x720, 8 fps at 1080p and 2 fps at 4K. That is fine for functional tests and screenshots, but not for performance measurements. Mesa's lavapipe/llvmpipe was also tested: it was only faster at small sizes, and WebGPU canvases did not present with it, so it is not included. Real GPU performance testing needs a GPU host with passthrough, such as the NVIDIA Container Toolkit with `--gpus all`. That is a deployment decision outside this image.

## Build and test locally

The `base` target needs no build arguments:

```bash
docker build --platform linux/amd64 --target base -t dev-box:base .
docker run --rm --entrypoint bash dev-box:base -c "$(cat scripts/smoke-test.sh)" smoke-test base
```

For `full`, review Google's Android SDK license terms first. Building intentionally requires explicit acceptance:

```bash
docker build --platform linux/amd64 --target full --build-arg ACCEPT_ANDROID_LICENSES=1 -t dev-box:full .
docker run --rm --entrypoint bash dev-box:full -c "$(cat scripts/smoke-test.sh)" smoke-test full
docker run --rm -it --entrypoint bash dev-box:full
```

`--platform linux/amd64` is required: the image installs x64-only tools, and the Dockerfile stops at its first step on any other architecture. The apt steps use BuildKit cache mounts, so re-running a build after a package-list change does not re-download every `.deb`.

Do not put secrets in Docker build arguments, the repository, or the image. This image is a **toolbox**, not an orchestrator: supply credentials or one-time work orders only through your deployment system, and do not mount the Docker daemon socket into untrusted sessions.

## Docker Hub publication

The workflow builds both targets and smoke-tests each before publishing anything. Pull requests only test. Pushes to `main` publish `latest`, `full` and `base`; `v*` tags publish `<tag>`, `<tag>-full` and `<tag>-base`; every publish (including manual dispatch) also pushes immutable `sha-...` (full) and `base-sha-...` tags. It uses the organization secrets `DOCKER_HUB_USERNAME` and `DOCKER_HUB_ACCESS_TOKEN`. Ensure the repository has access to both and that the token can push to the target Docker Hub namespace. By default the namespace is the Docker Hub username; if publishing to an organization namespace, set the GitHub Actions **repository variable** `DOCKER_HUB_NAMESPACE` to that namespace. Create the `dev-box` repository in Docker Hub if your account does not automatically create repositories on first push.

The workflow passes `ACCEPT_ANDROID_LICENSES=1` to the `full` build on every CI run. A maintainer must review the relevant Android SDK terms **before enabling CI**. No secret value is embedded in the repository. Blacksmith's builder keeps Docker layers and BuildKit cache mounts between runs, so after a Claude Code bump only the last stage of each target is rebuilt. Runners may require more free disk space than the default allocation; if builds fail for lack of disk, use a larger runner rather than deleting unrelated runner data.

## Versions and maintenance

Version pins live in the `ARG` block at the top of the Dockerfile. .NET 10.0.401 and .NET 11 RC1 are installed side by side in `/home/runner/dotnet`. Without a `global.json`, the latest installed SDK may be selected; pin `global.json` in projects requiring .NET 10. The .NET 11 tarball is checked against Microsoft's SHA-512; the Android tools ZIP is checked against its published SHA-256; scc is checked against its release checksums. Playwright is pinned by `PLAYWRIGHT_VERSION`, which also fixes the Chromium revision. The Chromium library list in the first apt step is copied from that release's `ubuntu26.04` dependency table, so re-sync it when bumping (the build fails if either Chromium binary has an unresolved library). Other network installers, the Python packages, Corepack's `pnpm@latest`/`yarn@latest`, Flutter `stable` and Node `--lts` are not fully version-pinned: rebuilding later can change those components. Review upstream licenses, hashes, security advisories, and image contents before production publication. For a reproducible release, pin every remaining installer and artifact to immutable versions/digests.

The workflow does not grant anyone access to a Claude environment, create sessions, or implement session cleanup. Operators must supply isolation, egress restrictions, resource limits, credential handling, and retention policies separately.

## Licensing

**Only the original source files in this repository are MIT licensed.** The image downloads third-party software, including Claude Code, Android SDK, Flutter, .NET, Rust, Node, Playwright and Chromium, and other packages; each has its own terms. The MIT license does not relicense those binaries. Before publishing a public Docker Hub image, have the appropriate owner review the third-party redistribution and Android license terms. If public redistribution of a component is not authorized, publish only the Dockerfile and build the image privately.
