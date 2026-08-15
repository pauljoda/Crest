#!/usr/bin/env python3

import base64
import http.server
import sys


EXPECTED_AUTHORIZATION = "Basic " + base64.b64encode(b"crest:test-only").decode("ascii")


class BasicAuthHandler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path != "/auth":
            self.send_error(404)
            return

        if self.headers.get("Authorization") != EXPECTED_AUTHORIZATION:
            self.send_response(401)
            self.send_header("WWW-Authenticate", 'Basic realm="Crest Test Realm"')
            self.send_header("Cache-Control", "no-store")
            self.end_headers()
            return

        body = b"<!doctype html><title>Authenticated</title><h1>Authenticated</h1>"
        self.send_response(200)
        self.send_header("Content-Type", "text/html; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, format, *args):
        sys.stdout.write((format % args) + "\n")
        sys.stdout.flush()


if __name__ == "__main__":
    port = int(sys.argv[1]) if len(sys.argv) > 1 else 8766
    server = http.server.ThreadingHTTPServer(("127.0.0.1", port), BasicAuthHandler)
    print(f"Basic auth fixture listening on http://127.0.0.1:{port}/auth", flush=True)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()
