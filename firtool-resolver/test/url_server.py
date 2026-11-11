#!/usr/bin/env python3

import http.server
import pathlib
import sys


class Handler(http.server.BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"
    binary = b""

    def do_GET(self):
        if self.path == "/download":
            self.send_response(302)
            self.send_header("Location", "/asset")
            self.send_header("Content-Length", "0")
            self.end_headers()
        elif self.path == "/asset":
            self.send_response(200)
            self.send_header("Content-Type", "application/octet-stream")
            self.send_header("Content-Length", str(len(self.binary)))
            self.end_headers()
            self.wfile.write(self.binary)
        else:
            self.send_response(404)
            self.send_header("Content-Length", "0")
            self.end_headers()

    def log_message(self, format, *args):
        pass


def main():
    if len(sys.argv) != 2:
        raise SystemExit(f"usage: {sys.argv[0]} <binary>")

    Handler.binary = pathlib.Path(sys.argv[1]).read_bytes()
    with http.server.ThreadingHTTPServer(("127.0.0.1", 0), Handler) as server:
        print(server.server_address[1], flush=True)
        server.serve_forever()


if __name__ == "__main__":
    main()
