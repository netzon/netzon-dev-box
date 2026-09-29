# Netzon Dev Box: browser testing notes

- Playwright 1.63.0 (`playwright` and `@playwright/test` in `/opt/playwright`), Chromium and Chrome Headless Shell (in `$PLAYWRIGHT_BROWSERS_PATH` = `/opt/ms-playwright`, also reachable as `~/.cache/ms-playwright`), and all their system libraries, fonts and Xvfb are part of the image. They survive session resumes and container restarts. The scratchpad and `/tmp` do not, so never rebuild a browser setup there. Scratch scripts need no `npm i playwright` or `npx playwright install`, and nothing ever needs `apt-get download`, `LD_LIBRARY_PATH`, `FONTCONFIG_FILE`, `--with-deps` or `install-deps` (there is no sudo, and none is needed).
- Ad-hoc scripts work from any directory with no install:
  - ESM: `import { chromium } from '/opt/playwright/node_modules/playwright/index.mjs';` (a bare `'playwright'` import only resolves inside a project that depends on it)
  - CommonJS: `const { chromium } = require('playwright');` (`NODE_PATH` points at `/opt/playwright/node_modules`; `@playwright/test` works too)
  - CLI: `playwright screenshot …`, `npx playwright …`
- A project with its own Playwright dependency uses that copy. If its version differs from 1.63.0, run `npx playwright install chromium` in the project (browser download only, no root).
- There is no GPU. Chromium renders in software with its bundled SwiftShader. WebGL/WebGL2 works with default launch options. WebGPU needs these launch args, from a secure context (`http://localhost`/`127.0.0.1`, `https` or `file://`). `about:blank`, `data:` URLs and `page.setContent()` are not secure, so `navigator.gpu` is undefined there:
  ```js
  chromium.launch({ args: ['--enable-unsafe-webgpu', '--enable-features=Vulkan,CDPScreenshotNewSurface', '--use-vulkan=swiftshader', '--use-angle=swiftshader'] })
  ```
  Use all four; they're also fine for WebGL-only pages. With no flags `requestAdapter()` returns null. With only some of them (e.g. just `--enable-unsafe-webgpu`) the first WebGPU draw crashes the GPU process, which also blanks WebGL canvases in screenshots. Chromium keeps only the last `--enable-features` switch, so put any extra features in that same comma-separated value; a second `--enable-features` would silently drop `Vulkan`.
- `chromium-gpu-check` checks that WebGL2, WebGPU and screenshots work (headless). For headed runs use `xvfb-run -a <command>`.
- Software rendering is slow (about 12 fps at 1280x720 and 2 fps at 4K for a full-screen shader on 2 vCPUs). For animation screenshots, keep `deviceScaleFactor: 1` and the viewport as small as the task allows, wait for an app-specific ready signal or a set number of `requestAnimationFrame` ticks rather than fixed sleeps, and use `page.clock` to freeze or step animation time for deterministic frames.
