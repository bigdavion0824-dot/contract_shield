from __future__ import annotations

import json
import os
from datetime import datetime, timezone
from http import HTTPStatus
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from typing import Any
from urllib.parse import parse_qs, urlparse

HOST = os.environ.get("TELEMETRY_HOST", "0.0.0.0")
PORT = int(os.environ.get("TELEMETRY_PORT", "8787"))
LOG_PATH = Path(os.environ.get("TELEMETRY_LOG_PATH", "telemetry_receiver/telemetry.jsonl"))
AUTH_TOKEN = os.environ.get("TELEMETRY_AUTH_TOKEN", "").strip()
MAX_BODY_BYTES = 128 * 1024


def _utc_now() -> str:
    return datetime.now(timezone.utc).isoformat()


def _append_record(record: dict[str, Any]) -> None:
    LOG_PATH.parent.mkdir(parents=True, exist_ok=True)
    with LOG_PATH.open("a", encoding="utf-8") as handle:
        handle.write(json.dumps(record, ensure_ascii=True) + "\n")


def _read_recent(limit: int) -> list[dict[str, Any]]:
    if not LOG_PATH.exists():
        return []
    lines = LOG_PATH.read_text(encoding="utf-8").splitlines()
    out: list[dict[str, Any]] = []
    for line in lines[-limit:]:
        try:
            out.append(json.loads(line))
        except json.JSONDecodeError:
            out.append({"type": "invalid_line", "raw": line})
    return out


class TelemetryHandler(BaseHTTPRequestHandler):
    server_version = "ContractShieldTelemetry/1.0"

    def do_GET(self) -> None:
        parsed = urlparse(self.path)
        if parsed.path == "/health":
            self._send_json(HTTPStatus.OK, {"ok": True, "ts": _utc_now()})
            return
        if parsed.path == "/recent":
            query = parse_qs(parsed.query)
            try:
                limit = max(1, min(100, int(query.get("n", ["20"])[0])))
            except ValueError:
                limit = 20
            self._send_json(HTTPStatus.OK, {"items": _read_recent(limit)})
            return
        self._send_json(HTTPStatus.NOT_FOUND, {"error": "not_found"})

    def do_POST(self) -> None:
        parsed = urlparse(self.path)
        if parsed.path != "/ingest":
            self._send_json(HTTPStatus.NOT_FOUND, {"error": "not_found"})
            return

        if AUTH_TOKEN:
            auth_header = self.headers.get("Authorization", "")
            if auth_header != f"Bearer {AUTH_TOKEN}":
                self._send_json(HTTPStatus.UNAUTHORIZED, {"error": "unauthorized"})
                return

        content_length = self.headers.get("Content-Length", "0")
        try:
            body_size = int(content_length)
        except ValueError:
            self._send_json(HTTPStatus.BAD_REQUEST, {"error": "invalid_content_length"})
            return

        if body_size <= 0 or body_size > MAX_BODY_BYTES:
            self._send_json(HTTPStatus.BAD_REQUEST, {"error": "invalid_body_size"})
            return

        raw = self.rfile.read(body_size)
        try:
            payload = json.loads(raw.decode("utf-8"))
        except (UnicodeDecodeError, json.JSONDecodeError):
            self._send_json(HTTPStatus.BAD_REQUEST, {"error": "invalid_json"})
            return

        if not isinstance(payload, dict):
            self._send_json(HTTPStatus.BAD_REQUEST, {"error": "object_required"})
            return

        record = {
            "receivedAt": _utc_now(),
            "remoteAddr": self.client_address[0] if self.client_address else "unknown",
            **payload,
        }
        _append_record(record)
        self._send_json(HTTPStatus.ACCEPTED, {"ok": True})

    def log_message(self, fmt: str, *args: Any) -> None:
        return

    def _send_json(self, status: HTTPStatus, payload: dict[str, Any]) -> None:
        encoded = json.dumps(payload, ensure_ascii=True).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(encoded)))
        self.end_headers()
        self.wfile.write(encoded)


def main() -> None:
    print(f"Starting telemetry receiver on http://{HOST}:{PORT}")
    print(f"Writing events to {LOG_PATH}")
    if AUTH_TOKEN:
        print("Bearer auth is enabled")
    with ThreadingHTTPServer((HOST, PORT), TelemetryHandler) as server:
        server.serve_forever()


if __name__ == "__main__":
    main()
