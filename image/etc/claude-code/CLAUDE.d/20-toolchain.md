# Netzon Dev Box: preinstalled tools

Everything below is part of the image and survives session resumes and container restarts. Never install or rebuild it in the scratchpad, `/tmp` or a project. There is no `sudo` and nothing needs it.

- CLI: `gh`, `jq`, `rg`, `fd`, `fzf`, `tree`, `less`, `file`, `column`, `time`, `ps`, `htop`, `lsof`, `strace`, `tmux`, `nano`, `rsync`, `ssh`/`scp`, `shellcheck`, `scc`, `sqlite3`, `dot` (Graphviz), ImageMagick 7 (`magick`), `dig`, `ping`, `nc`, `socat`, `bwrap`.
- Build: `gcc`/`g++`, `make`, `cmake`, `pkg-config`, OpenSSL and SQLite headers.
- Python: `python3` is Python 3.13 in `/opt/venv` with Pillow, NumPy, pandas, SciPy, Matplotlib, Requests, Beautiful Soup, lxml, SQLAlchemy and `pip`, so data analysis and image work need no install. `uv`, `uvx`, `ruff` and `pyrefly` are on `PATH`. A project's own virtualenv (`uv sync`, `uv run`, `source .venv/bin/activate`) takes precedence when used.
- JavaScript/TypeScript: Node LTS (`node`, `npm`, `npx`), `pnpm` and `yarn` through Corepack (already cached, so they start offline; a project's `packageManager` field can select another version), `tsc`, Bun, and Playwright with Chromium (see the browser notes).
- Rust: `rustc`, `cargo` (stable, minimal profile).
- `bwrap` and `socat` are what Claude Code's Linux sandbox uses. Whether it can run depends on the container runtime allowing unprivileged user namespaces, which is a deployment setting.
