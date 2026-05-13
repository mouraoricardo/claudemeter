import json
import threading
import time
from collections import deque
from datetime import datetime, timezone
from pathlib import Path
from typing import Optional

import requests
from flask import Flask, jsonify, send_file

app = Flask(__name__)

CREDENTIALS_PATH = Path.home() / ".claude" / ".credentials.json"
API_URL = "https://api.anthropic.com/v1/messages"
POLL_INTERVAL = 60
HISTORY_SECONDS = 24 * 3600

RATE_LIMIT_HEADERS = [
    "anthropic-ratelimit-unified-5h-remaining",
    "anthropic-ratelimit-unified-5h-limit",
    "anthropic-ratelimit-unified-5h-utilization",
    "anthropic-ratelimit-unified-7d-remaining",
    "anthropic-ratelimit-unified-7d-limit",
    "anthropic-ratelimit-unified-7d-utilization",
    "anthropic-ratelimit-unified-5h-reset",
    "anthropic-ratelimit-unified-7d-reset",
]

_cache = {
    "usage": {},
    "last_poll": None,
    "last_error": None,
    "poll_count": 0,
}
_history: deque = deque()           # entries: {ts, pct_5h, pct_7d}
_notified = {"5h": False, "7d": False}
_lock = threading.Lock()


def load_token() -> str:
    if not CREDENTIALS_PATH.exists():
        raise FileNotFoundError(f"Credentials not found: {CREDENTIALS_PATH}")
    try:
        data = json.loads(CREDENTIALS_PATH.read_text())
    except json.JSONDecodeError as exc:
        raise ValueError(f"Invalid credentials JSON: {exc}") from exc
    try:
        return data["claudeAiOauth"]["accessToken"]
    except KeyError as exc:
        raise KeyError("claudeAiOauth.accessToken missing from credentials") from exc


def _pct(usage: dict, key: str) -> Optional[float]:
    def to_f(v):
        try:
            return float(v) if v is not None else None
        except (ValueError, TypeError):
            return None

    rem  = to_f(usage.get(f"anthropic-ratelimit-unified-{key}-remaining"))
    lim  = to_f(usage.get(f"anthropic-ratelimit-unified-{key}-limit"))
    util = to_f(usage.get(f"anthropic-ratelimit-unified-{key}-utilization"))

    if lim is not None and lim > 0 and rem is not None:
        return (lim - rem) / lim * 100
    if util is not None:
        return util * 100 if util <= 1 else util
    return None


def _notify(key: str, pct: Optional[float]) -> None:
    if pct is None or pct < 80:
        _notified[key] = False
        return
    if _notified[key]:
        return
    _notified[key] = True
    try:
        from plyer import notification
        notification.notify(
            title="ClaudeMeter — Usage Warning",
            message=f"{key} budget at {pct:.1f}% — approaching limit",
            app_name="ClaudeMeter",
            timeout=5,
        )
    except Exception:
        pass


def poll_usage() -> None:
    now = datetime.now(timezone.utc)
    try:
        token = load_token()
        resp = requests.post(
            API_URL,
            headers={
                "Authorization": f"Bearer {token}",
                "Content-Type": "application/json",
                "anthropic-version": "2023-06-01",
                "anthropic-beta": "claude-code-20250219",
            },
            json={
                "model": "claude-haiku-4-5-20251001",
                "max_tokens": 1,
                "messages": [{"role": "user", "content": "hi"}],
            },
            timeout=15,
        )
        if resp.status_code == 401:
            raise PermissionError("Token expired — re-authenticate with the Claude CLI")

        usage   = {h: resp.headers.get(h) for h in RATE_LIMIT_HEADERS}
        pct_5h  = _pct(usage, "5h")
        pct_7d  = _pct(usage, "7d")
        cutoff  = now.timestamp() - HISTORY_SECONDS

        with _lock:
            _cache["usage"]     = usage
            _cache["last_poll"] = now.isoformat()
            _cache["last_error"] = None
            _cache["poll_count"] += 1
            _history.append({"ts": now.isoformat(), "pct_5h": pct_5h, "pct_7d": pct_7d})
            while _history and datetime.fromisoformat(_history[0]["ts"]).timestamp() < cutoff:
                _history.popleft()

        _notify("5h", pct_5h)
        _notify("7d", pct_7d)

    except Exception as exc:
        with _lock:
            _cache["last_error"] = str(exc)
            _cache["last_poll"]  = now.isoformat()
            _cache["poll_count"] += 1


def background_poller() -> None:
    while True:
        poll_usage()
        time.sleep(POLL_INTERVAL)


@app.after_request
def add_cors(response):
    response.headers["Access-Control-Allow-Origin"] = "*"
    return response


@app.route("/")
def dashboard():
    return send_file(Path(__file__).parent / "dashboard.html")


@app.route("/api/usage")
def api_usage():
    with _lock:
        return jsonify(_cache["usage"])


@app.route("/api/history")
def api_history():
    with _lock:
        return jsonify(list(_history))


@app.route("/api/status")
def api_status():
    with _lock:
        return jsonify({
            "last_poll":            _cache["last_poll"],
            "last_error":           _cache["last_error"],
            "poll_count":           _cache["poll_count"],
            "poll_interval_seconds": POLL_INTERVAL,
            "credentials_path":     str(CREDENTIALS_PATH),
        })


if __name__ == "__main__":
    t = threading.Thread(target=background_poller, daemon=True)
    t.start()
    app.run(host="0.0.0.0", port=7842, debug=False)
