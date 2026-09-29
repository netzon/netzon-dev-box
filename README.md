# Netzon Dev Box

Public, Linux/amd64 development container for Claude Code sessions and interactive development. This repository builds **from Ubuntu 26.04 on the first build**; it does not inherit a private image or contain tenant configuration, work orders, tokens, or Git credentials.

## Included

Claude Code (default 2.1.284), Python 3.13 via uv, Pyrefly, Flutter stable, Android SDK command-line tools / API 36 / build-tools 36.0.0, Java 21, Rust/Cargo, fnm with Node LTS, Bun, scc, jq, ripgrep, zip, unzip, wget, and .NET SDK 10.0.401 plus 11.0.100-rc.1.26425.128. Builds run as non-root `runner` (UID/GID 10001); `/workspace` is writable. The image entrypoint is `claude`.

The Android installation does **not** include Android Studio, an emulator, an NDK, or a connected device. No environment secret or Docker socket is mounted by this image; those are deployment decisions outside this repository. A large image and substantial CI disk usage are expected; test runner capacity before relying on hosted CI.

## Build and test locally

Review Google's Android SDK license terms first. Building intentionally requires explicit acceptance:

```bash
docker build --platform linux/amd64 --build-arg ACCEPT_ANDROID_LICENSES=1 -t dev-box:local .
docker run --rm --entrypoint bash dev-box:local -s < scripts/smoke-test.sh
docker run --rm -it --entrypoint bash dev-box:local
```

Do not put secrets in Docker build arguments, the repository, or the image. This image is a **toolbox**, not an orchestrator: supply credentials or one-time work orders only through your deployment system, and do not mount the Docker daemon socket into untrusted sessions.

## Docker Hub publication

The workflow builds and smoke-tests first. Pull requests only test; pushes to `main` publish `latest` and a `sha-...` tag; `v*` tags publish the version tag and a `sha-...` tag. Manual dispatch publishes a `sha-...` tag. It uses the organization secrets `DOCKER_HUB_USERNAME` and `DOCKER_HUB_ACCESS_TOKEN`. Ensure the repository has access to both and that the token can push to the target Docker Hub namespace. By default the namespace is the Docker Hub username; if publishing to an organization namespace, set the GitHub Actions **repository variable** `DOCKER_HUB_NAMESPACE` to that namespace. Create the `dev-box` repository in Docker Hub if your account does not automatically create repositories on first push.

The workflow passes `ACCEPT_ANDROID_LICENSES=1` on every CI build. A maintainer must review the relevant Android SDK terms **before enabling CI**. No secret value is embedded in the repository. GitHub-hosted runners may require more free disk space than the default allocation; if builds fail for lack of disk, use a larger runner or split the image rather than deleting unrelated runner data.

## Versions and maintenance

.NET 10.0.401 and .NET 11 RC1 are installed side by side in `/home/runner/dotnet`. Without a `global.json`, the latest installed SDK may be selected; pin `global.json` in projects requiring .NET 10. The .NET 11 tarball is checked against Microsoft's SHA-512; the Android tools ZIP is checked against its published SHA-256; scc is checked against its release checksums. Other network installers and Flutter `stable` / Node `--lts` are not fully version-pinned: rebuilding later can change those components. Review upstream licenses, hashes, security advisories, and image contents before production publication. For a reproducible release, pin every remaining installer and artifact to immutable versions/digests.

The workflow does not grant anyone access to a Claude environment, create sessions, or implement session cleanup. Operators must supply isolation, egress restrictions, resource limits, credential handling, and retention policies separately.

## Licensing

**Only the original source files in this repository are MIT licensed.** The image downloads third-party software, including Claude Code, Android SDK, Flutter, .NET, Rust, Node, and other packages; each has its own terms. The MIT license does not relicense those binaries. Before publishing a public Docker Hub image, have the appropriate owner review the third-party redistribution and Android license terms. If public redistribution of a component is not authorized, publish only the Dockerfile and build the image privately.
