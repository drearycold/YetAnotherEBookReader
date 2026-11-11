#!/usr/bin/env python3
"""Loopback fixture for CalibreOnboardingUITests.testHelperConfigurationRetryConfirmationAndPageExit."""

import argparse
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import json
import threading
from urllib.parse import parse_qs, urlsplit


class HeldResponse:
    def __init__(self):
        self.arrived = threading.Event()
        self.released = threading.Event()


class HelperFixture(BaseHTTPRequestHandler):
    base_port = 18091
    lock = threading.Lock()
    held = None

    def do_GET(self):
        url = urlsplit(self.path)
        port = self.server.server_port
        if port == self.base_port:
            self.serve_calibre(url)
        elif url.path != '/dshelper/1/configuration/_':
            self.reply(404)
        elif port == self.base_port + 1:
            self.reply(401, b'fixture-private-response', 'text/plain')
        else:
            with self.lock:
                held = type(self).held
            if held is not None:
                held.arrived.set()
                if not held.released.wait(30):
                    self.reply(504)
                    return
            self.json_reply({'dsreader_helper_prefs': {'plugin_prefs': {'Options': {
                'servicePort': port,
                'dictViewerEnabled': True,
                'dictViewerLibraryName': 'Fixture Dictionary',
            }}}})

    def serve_calibre(self, url):
        if url.path == '/control':
            self.configure(parse_qs(url.query).get('mode', [''])[0])
        elif url.path == '/ajax/library-info':
            self.json_reply({'default_library': 'Fixture', 'library_map': {'Fixture': 'Fixture'}})
        elif url.path.startswith('/ajax/search'):
            self.json_reply({
                'total_num': 0, 'sort_order': 'asc', 'num_books_without_search': 0, 'offset': 0,
                'num': 0, 'sort': 'title', 'base_url': '', 'library_id': 'Fixture',
                'book_ids': [], 'vl': '',
            })
        elif url.path.startswith('/ajax/categories'):
            self.json_reply([])
        else:
            self.reply(404)

    def configure(self, mode):
        cls = type(self)
        with self.lock:
            held = cls.held
            if mode == 'hold':
                if held is not None:
                    held.released.set()
                cls.held = HeldResponse()
            elif mode == 'release' and held is not None:
                held.released.set()
                cls.held = None
        if mode == 'wait':
            self.reply(200 if held is not None and held.arrived.wait(8) else 408)
        elif mode in ('hold', 'release'):
            self.reply(200)
        else:
            self.reply(400)

    def json_reply(self, value):
        self.reply(200, json.dumps(value).encode(), 'application/json')

    def reply(self, code, body=b'', content_type='text/plain'):
        self.send_response(code)
        self.send_header('Content-Type', content_type)
        self.send_header('Content-Length', str(len(body)))
        try:
            self.end_headers()
            self.wfile.write(body)
        except (BrokenPipeError, ConnectionResetError):
            # A cancelled native download can close its socket before release.
            pass


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--base-port', type=int, default=18091,
                        help='Calibre mock port, followed by the failure and success Helper ports')
    options = parser.parse_args()
    HelperFixture.base_port = options.base_port
    servers = [
        ThreadingHTTPServer(('127.0.0.1', port), HelperFixture)
        for port in range(options.base_port, options.base_port + 3)
    ]
    for server in servers[1:]:
        threading.Thread(target=server.serve_forever, daemon=True).start()
    print(f'Fixture and control ready on http://127.0.0.1:{options.base_port}/control', flush=True)
    servers[0].serve_forever()


if __name__ == '__main__':
    main()
