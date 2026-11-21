#!/usr/bin/env python3
"""Fake OpenCode 2 HTTP API for tests.

usage: fake-api.py PORT FIXTURE_DIR   (PORT 0 picks a free port)

Serves GET <path> from FIXTURE_DIR/<path with / as _>.json, ignoring the query
string. Requires Basic auth opencode:$FAKE_API_PASSWORD (default test-only).
A file <name>.lazy next to a fixture makes the first request for that path
answer {"_tag":"AgentNotFoundError"}, as a real server does before agents have
loaded. A missing fixture answers 404 with a JSON body.

Prints "<port> <pid>" on one line to stdout once listening. If FAKE_API_LOG is
set, each request appends "METHOD PATH auth=ok|bad query=RAW" to that file.
"""
import base64
import json
import os
import sys
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlsplit

PASSWORD = os.environ.get("FAKE_API_PASSWORD", "test-only")
EXPECTED = "Basic " + base64.b64encode(f"opencode:{PASSWORD}".encode()).decode()
LOG = os.environ.get("FAKE_API_LOG")
seen = set()
lock = threading.Lock()


class Handler(BaseHTTPRequestHandler):
    def log_message(self, *args):
        pass

    def _send(self, status, body, headers=()):
        data = body.encode() if isinstance(body, str) else body
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data)))
        for k, v in headers:
            self.send_header(k, v)
        self.end_headers()
        self.wfile.write(data)

    def _handle(self):
        path = urlsplit(self.path).path
        authed = self.headers.get("Authorization") == EXPECTED
        if LOG:
            with lock, open(LOG, "a") as f:
                query = urlsplit(self.path).query
                f.write(f"{self.command} {path} auth={'ok' if authed else 'bad'} query={query}\n")
        if not authed:
            self._send(401, '{"error":"unauthorized"}',
                       [("WWW-Authenticate", 'Basic realm="opencode"')])
            return
        if self.command != "GET":
            self._send(405, '{"error":"method not allowed"}')
            return
        stem = os.path.join(FIXTURES, path.strip("/").replace("/", "_"))
        if not os.path.isfile(stem + ".json"):
            self._send(404, json.dumps({"error": "no fixture", "path": path}))
            return
        if os.path.isfile(stem + ".lazy"):
            with lock:
                first = path not in seen
                seen.add(path)
            if first:
                name = path.rstrip("/").rsplit("/", 1)[-1]
                self._send(404, json.dumps({
                    "_tag": "AgentNotFoundError", "agentID": name,
                    "message": f"Agent not found: {name}"}))
                return
        with open(stem + ".json", "rb") as f:
            self._send(200, f.read())

    do_GET = do_POST = do_PUT = do_DELETE = _handle


if __name__ == "__main__":
    if len(sys.argv) != 3:
        sys.exit("usage: fake-api.py PORT FIXTURE_DIR")
    FIXTURES = sys.argv[2]
    server = ThreadingHTTPServer(("127.0.0.1", int(sys.argv[1])), Handler)
    print(f"{server.server_address[1]} {os.getpid()}", flush=True)
    server.serve_forever()
