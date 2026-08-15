#!/usr/bin/env python3
"""Serve the compatibility corpus and allow its exact test to take it offline."""

from __future__ import annotations

import argparse
import functools
import http.server
import pathlib
import threading


class OfflineFixtureHandler(http.server.SimpleHTTPRequestHandler):
    def do_GET(self) -> None:  # noqa: N802 - inherited HTTP handler name
        if self.path == "/__crest_stop__":
            self.send_response(200)
            self.send_header("Cache-Control", "no-store")
            self.send_header("Content-Length", "0")
            self.end_headers()
            threading.Thread(target=self.server.shutdown, daemon=True).start()
            return
        super().do_GET()

    def end_headers(self) -> None:
        self.send_header("Cache-Control", "no-store")
        super().end_headers()


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--port", type=int, required=True)
    parser.add_argument(
        "--directory",
        type=pathlib.Path,
        default=pathlib.Path(__file__).parent,
    )
    arguments = parser.parse_args()
    handler = functools.partial(
        OfflineFixtureHandler,
        directory=str(arguments.directory.resolve()),
    )
    server = http.server.ThreadingHTTPServer(("127.0.0.1", arguments.port), handler)
    try:
        server.serve_forever()
    finally:
        server.server_close()


if __name__ == "__main__":
    main()
