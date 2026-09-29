# Netzon Dev Box: restarts and caches

- The image survives a restart. The scratchpad, `/tmp` and the `/workspace` checkout do not: commit and push anything worth keeping, and never build tooling in scratch that the image already provides.
- Package-manager caches live under `/cache`: `/cache/bun` (`BUN_INSTALL_CACHE_DIR`), `/cache/npm` (`npm_config_cache`), `/cache/uv` (`UV_CACHE_DIR`), `/cache/gradle` (`GRADLE_USER_HOME`) and `/cache/nuget` (`NUGET_PACKAGES`). The deployment may mount a persistent volume there, in which case the first install after a restart is served from cache. Do not keep anything else there.
