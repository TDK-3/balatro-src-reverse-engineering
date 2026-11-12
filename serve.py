#!/usr/bin/env python3
import http.server
import os
import socketserver
import sys

PORT = int(sys.argv[1]) if len(sys.argv) > 1 else 8080
WEB_ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "dist", "Balatro-Web")


class ReadOnlyLoveJSHandler(http.server.SimpleHTTPRequestHandler):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=WEB_ROOT, **kwargs)

    def end_headers(self):
        # Required headers for love.js 11.5 SharedArrayBuffer / WASM execution
        self.send_header("Cross-Origin-Opener-Policy", "same-origin")
        self.send_header("Cross-Origin-Embedder-Policy", "require-corp")
        self.send_header("Cache-Control", "no-store")
        super().end_headers()

    def list_directory(self, path):
        # Disable directory browsing for strict read-only file serving
        self.send_error(403, "Directory listing is forbidden")
        return None

    def do_POST(self):
        self.send_error(405, "Read-only server")

    def do_PUT(self):
        self.send_error(405, "Read-only server")

    def do_DELETE(self):
        self.send_error(405, "Read-only server")


if __name__ == "__main__":
    if not os.path.isdir(WEB_ROOT):
        print(f"Error: {WEB_ROOT} not found. Run ./build.sh first.")
        sys.exit(1)

    socketserver.TCPServer.allow_reuse_address = True
    with socketserver.TCPServer(("0.0.0.0", PORT), ReadOnlyLoveJSHandler) as httpd:
        print(f"Serving Balatro (love.js) read-only at http://localhost:{PORT}")
        print("Press Ctrl+C to stop.")
        try:
            httpd.serve_forever()
        except KeyboardInterrupt:
            print("\nServer stopped.")
