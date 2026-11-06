#!/usr/bin/env python3
"""Loopback fixture for the opt-in P4 Calibre connection recovery UI journey.

Run with a real calibre server at --upstream (default port 8080). Point
YABR_ONBOARDING_SINGLE_URL at http://127.0.0.1:18084 and
YABR_CONNECTION_CONTROL_URL at http://127.0.0.1:18084/p4-control.
Only library-info probes fail; success forwards ordinary requests to calibre.
Modes: html503, auth401, auth403, auth_basic and success. auth_basic requires
username contract and password correct. Set modes via /p4-control?mode=MODE.
"""

import argparse
import base64
import json
import threading
import urllib.error
import urllib.parse
import urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer


def serve(upstream, port):
    state = {"mode": "html503"}
    lock = threading.Lock()
    opener = urllib.request.build_opener(urllib.request.ProxyHandler({}))
    html = ("<!DOCTYPE html><html><head><title>503 - Connect failed</title><style>"
            + "body { background-color: white; color: black; }\n" * 2000
            + "</style></head><body>Proxy could not connect</body></html>").encode()

    class Handler(BaseHTTPRequestHandler):
        def do_GET(self):
            parsed = urllib.parse.urlparse(self.path)
            if parsed.path == "/p4-control":
                mode = urllib.parse.parse_qs(parsed.query).get("mode", ["html503"])[0]
                if mode not in ("html503", "auth401", "auth403", "auth_basic", "success"):
                    self.reply(400, b"Unknown mode", "text/plain")
                    return
                with lock:
                    state["mode"] = mode
                self.reply(200, json.dumps(state).encode(), "application/json")
                return
            with lock:
                mode = state["mode"]
            if parsed.path.endswith("/ajax/library-info") and mode == "auth_basic":
                credential = "Basic " + base64.b64encode(b"contract:correct").decode()
                if self.headers.get("Authorization") != credential:
                    self.reply(401, b"Credentials required", "text/plain", authenticate=True)
                    return
                mode = "success"
            if parsed.path.endswith("/ajax/library-info") and mode != "success":
                status = {"html503": 503, "auth401": 401, "auth403": 403}[mode]
                self.reply(status, html, "text/html")
                return
            try:
                with opener.open(upstream + self.path, timeout=30) as response:
                    self.reply(response.status, response.read(), response.headers.get(
                        "Content-Type", "application/octet-stream"))
            except urllib.error.HTTPError as error:
                self.reply(error.code, error.read(), error.headers.get("Content-Type", "text/plain"))
            except urllib.error.URLError:
                self.reply(502, b"Cannot reach the fixture calibre server", "text/plain")

        def reply(self, status, body, content_type, authenticate=False):
            self.send_response(status)
            if authenticate:
                self.send_header("WWW-Authenticate", 'Basic realm="P4 Calibre Fixture"')
            self.send_header("Content-Type", content_type)
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            try:
                self.wfile.write(body)
            except (BrokenPipeError, ConnectionResetError):
                pass

    ThreadingHTTPServer(("127.0.0.1", port), Handler).serve_forever()


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--upstream", default="http://127.0.0.1:8080")
    parser.add_argument("--port", type=int, default=18084)
    args = parser.parse_args()
    serve(args.upstream.rstrip("/"), args.port)
