#!/usr/bin/env python3

import argparse
import http.server
import time


class RecoveryHandler(http.server.BaseHTTPRequestHandler):
    delay = 30.0

    def do_GET(self):
        if self.path == "/ready":
            self._send(200, b"ready\n", "text/plain; charset=utf-8")
            return

        if self.path != "/slow":
            self._send(404, b"not found\n", "text/plain; charset=utf-8")
            return

        opening = b"""<!doctype html>
<meta charset="utf-8">
<title>WebContent Recovery Fixture</title>
<h1>WebContent Recovery Fixture</h1>
<p>The response has committed. Its final bytes are intentionally delayed.</p>
"""
        try:
            self.send_response(200)
            self.send_header("Content-Type", "text/html; charset=utf-8")
            self.send_header("Cache-Control", "no-store")
            self.end_headers()
            self.wfile.write(opening)
            self.wfile.flush()
            time.sleep(self.delay)
            self.wfile.write(b"<p>The delayed navigation completed.</p>\n")
        except (BrokenPipeError, ConnectionResetError):
            pass

    def _send(self, status, body, content_type):
        try:
            self.send_response(status)
            self.send_header("Content-Type", content_type)
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)
        except (BrokenPipeError, ConnectionResetError):
            pass

    def log_message(self, format, *args):
        print(f"{self.address_string()} - {format % args}", flush=True)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--port", type=int, default=8766)
    parser.add_argument("--delay", type=float, default=30.0)
    arguments = parser.parse_args()

    RecoveryHandler.delay = arguments.delay
    server = http.server.ThreadingHTTPServer(("127.0.0.1", arguments.port), RecoveryHandler)
    print(
        f"WebContent recovery fixture listening on http://127.0.0.1:{arguments.port}/slow",
        flush=True,
    )
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()


if __name__ == "__main__":
    main()
