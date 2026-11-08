#!/usr/bin/env python3
"""Loopback fixture for CalibreOnboardingUITests' opt-in download/read journey.

Run against a calibre server containing its Quick Start Guide (book ID 1):
    python3 .github/scripts/calibre-download-proxy.py --upstream http://127.0.0.1:8080

Use http://127.0.0.1:18082 as YABR_ONBOARDING_SINGLE_URL and append /p3-control
for YABR_DOWNLOAD_READ_CONTROL_URL. BD1 uses /bd1-control as
YABR_DETAIL_REFRESH_CONTROL_URL, with success/failed/unavailable metadata modes.
Other onboarding tests use their usual setup.
The proxy forwards read requests; its control endpoint changes only fixture state.
"""

import argparse
import json
import threading
import time
import urllib.error
import urllib.parse
import urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer


def serve(upstream, port):
    state = {"mode": "success", "attempts": 0, "detail_mode": "success", "manifest_mode": "real"}
    lock = threading.Lock()
    # A system proxy must never send these loopback requests to another machine.
    opener = urllib.request.build_opener(urllib.request.ProxyHandler({}))

    class Handler(BaseHTTPRequestHandler):
        def do_GET(self):
            parsed = urllib.parse.urlparse(self.path)
            if parsed.path == "/p3-control":
                query = urllib.parse.parse_qs(parsed.query)
                with lock:
                    mode = query.get("mode", [state["mode"]])[0]
                    if mode not in ("success", "slow", "fail_once"):
                        self.reply(400, b"Unknown download mode", "text/plain")
                        return
                    if "mode" in query:
                        state.update(mode=mode, attempts=0)
                    body = json.dumps(state).encode()
                self.reply(200, body, "application/json")
                return
            if parsed.path == "/bd1-control":
                mode = urllib.parse.parse_qs(parsed.query).get("mode", ["success"])[0]
                if mode not in ("success", "failed", "unavailable"):
                    self.reply(400, b"Unknown detail mode", "text/plain")
                    return
                with lock:
                    state["detail_mode"] = mode
                self.reply(200, b"{}", "application/json")
                return
            if parsed.path == "/bd3-control":
                mode = urllib.parse.parse_qs(parsed.query).get("mode", ["real"])[0]
                if mode not in ("real", "success", "empty", "waiting", "invalid", "offline", "slow"):
                    self.reply(400, b"Unknown preview mode", "text/plain")
                    return
                with lock:
                    state["manifest_mode"] = mode
                self.reply(200, b"{}", "application/json")
                return
            if parsed.path.startswith("/book-manifest/"):
                with lock:
                    manifest_mode = state["manifest_mode"]
                if manifest_mode == "slow":
                    time.sleep(5)
                payloads = {
                    "success": b'{"toc":{"children":[{"title":"Preview Chapter","children":[{"title":"Nested Chapter"}]}]}}',
                    "slow": b'{"toc":{"children":[{"title":"Late Chapter"}]}}',
                    "empty": b'{"toc":{"children":[]}}',
                    "waiting": b'{"job_status":"waiting"}',
                    "invalid": b'{"toc":"invalid"}',
                }
                if manifest_mode in payloads:
                    self.reply(200, payloads[manifest_mode], "application/json")
                    return
                if manifest_mode == "offline":
                    self.reply(503, b"Temporarily unavailable", "text/plain")
                    return
            if parsed.path.startswith("/ajax/books/"):
                with lock:
                    detail_mode = state["detail_mode"]
                if detail_mode == "failed":
                    self.reply(503, b"Temporarily unavailable", "text/plain")
                    return
                if detail_mode == "unavailable":
                    ids = urllib.parse.parse_qs(parsed.query).get("ids", [""])[0].split(",")
                    self.reply(200, json.dumps({book_id: None for book_id in ids}).encode(), "application/json")
                    return
            if parsed.path.startswith("/get/EPUB/"):
                with lock:
                    state["attempts"] += 1
                    mode, attempt = state["mode"], state["attempts"]
                if mode == "fail_once" and attempt == 1:
                    self.reply(503, b"Temporary download failure", "text/plain")
                    return
                if mode == "slow":
                    time.sleep(7)
            try:
                with opener.open(upstream + self.path, timeout=30) as response:
                    self.reply(response.status, response.read(), response.headers.get(
                        "Content-Type", "application/octet-stream"))
            except urllib.error.HTTPError as error:
                self.reply(error.code, error.read(), error.headers.get("Content-Type", "text/plain"))
            except urllib.error.URLError:
                self.reply(502, b"Cannot reach the fixture calibre server", "text/plain")

        def reply(self, status, body, content_type):
            self.send_response(status)
            self.send_header("Content-Type", content_type)
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            try:
                self.wfile.write(body)
            except (BrokenPipeError, ConnectionResetError):
                pass  # The journey deliberately cancels in-flight downloads.

    ThreadingHTTPServer(("127.0.0.1", port), Handler).serve_forever()


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--upstream", default="http://127.0.0.1:8080")
    parser.add_argument("--port", type=int, default=18082)
    args = parser.parse_args()
    serve(args.upstream.rstrip("/"), args.port)
