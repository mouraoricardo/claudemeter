# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

ClaudeMeter is a local dashboard for monitoring Claude Code API usage and rate limits. It polls the Anthropic API every 60 seconds and displays the 5-hour and 7-day unified token budgets in a browser at `http://localhost:7842`.

Primary target platform is Windows, but `server.py` is cross-platform Python.

## Running locally (Linux/WSL/Mac)

```bash
# Install dependencies
pip install -r requirements.txt
# or, using the existing .venv:
source .venv/bin/activate

# Start the server
python server.py

# Open in browser
xdg-open http://localhost:7842   # Linux
open http://localhost:7842        # Mac
```

On Windows, users double-click `start.bat` instead.

## Architecture

The project has two files that matter: `server.py` and `dashboard.html`.

**`server.py`** — Flask backend with three routes:
- `GET /` — serves `dashboard.html` as a static file
- `GET /api/usage` — returns the cached rate-limit headers as JSON
- `GET /api/status` — returns poll metadata (last poll time, error, count, interval)

A daemon thread (`background_poller`) runs from startup, calling `poll_usage()` every 60 seconds. `poll_usage()` reads the Claude OAuth token fresh from `~/.claude/.credentials.json` on every cycle, makes a minimal 1-token POST to `https://api.anthropic.com/v1/messages` using `claude-haiku-4-5-20251001` with the `anthropic-beta: claude-code-20250219` header, then stores the rate-limit response headers in the `_cache` dict. The cache is protected by `threading.Lock()`.

The rate-limit headers captured are:
- `anthropic-ratelimit-unified-5h-{remaining,limit,utilization,reset}`
- `anthropic-ratelimit-unified-7d-{remaining,limit,utilization,reset}`

**`dashboard.html`** — Self-contained single-page app. No build step, no bundler. Uses Chart.js 4 via CDN for doughnut gauges. Polls `/api/usage` and `/api/status` in parallel every 60 seconds. Renders two cards (5h Session, 7d) with utilization percentage in the gauge center, remaining/limit token counts, and a countdown to budget reset (computed client-side from the reset timestamp header).

Color thresholds: green < 50%, amber 50–80%, red ≥ 80%.

## Windows deployment

- **`start.bat`** — checks Python ≥ 3.8, installs deps if missing, skips launch if port 7842 is already bound, starts `server.py` hidden via `pythonw.exe` or a VBScript fallback, waits up to 15 s for the server to respond, then opens the browser.
- **`start_portable.bat`** — template launcher used inside the portable distribution (references `.\python\python.exe` and `.\lib\` instead of system Python).
- **`build.bat`** — downloads Python 3.12 embeddable zip (~12 MB), bootstraps pip into it, installs Flask and requests into a local `lib\` folder, copies source files, and zips everything into `claudemeter-portable.zip`. The portable build avoids PyInstaller to sidestep antivirus false positives.

## Credentials

The server reads `%USERPROFILE%\.claude\.credentials.json` (resolved cross-platform via `Path.home() / ".claude" / ".credentials.json"`). The token is at `data["claudeAiOauth"]["accessToken"]`. This file is created by the Claude Code CLI and must exist on any machine running the server.

## Dependencies

```
flask==3.1.3
requests==2.34.0
```

No linting config, no test suite.
