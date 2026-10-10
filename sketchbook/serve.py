#!/usr/bin/env python3
"""
Servidor estatico do port Sketchbook (dArkOS/ArkOS - RK3326).

- Serve index.html, build/ (js/css/glb) com MIME correto (.glb = model/gltf-binary)
- Sem cache (evita .glb corrompidos em cartoes SD lentos)
- /health  -> readiness pro launcher esperar a porta abrir
- /exit    -> chamado pelo port.js quando o jogador segura SELECT+START;
              mata os PIDs listados no pidfile e desliga o servidor,
              o que derruba o browser/weston e devolve o controle ao ES
"""
import argparse
import mimetypes
import os
import signal
import sys
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import unquote, urlparse

# GLB e o formato dos modelos 3D do jogo
mimetypes.add_type("model/gltf-binary", ".glb")
mimetypes.add_type("model/gltf+json", ".gltf")
mimetypes.add_type("application/javascript", ".js")
mimetypes.add_type("text/css", ".css")


class Handler(BaseHTTPRequestHandler):
    root = "."
    pidfile = None
    server_version = "SketchbookPort/1.0"

    def log_message(self, fmt, *args):  # log curto no stdout (vai pro log.txt do port)
        sys.stdout.write("[serve] %s\n" % (fmt % args))
        sys.stdout.flush()

    def _send(self, code, body=b"", ctype="text/plain; charset=utf-8", extra=None):
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store, no-cache, must-revalidate")
        self.send_header("Access-Control-Allow-Origin", "*")
        for k, v in (extra or {}).items():
            self.send_header(k, v)
        self.end_headers()
        if self.command != "HEAD":
            self.wfile.write(body)

    def do_HEAD(self):
        self.do_GET()

    def do_GET(self):
        path = urlparse(self.path).path

        if path == "/health":
            self._send(200, b"ok")
            return

        if path == "/exit":
            self._send(200, b"bye")
            threading.Thread(target=self._exit, daemon=True).start()
            return

        rel = unquote(path).lstrip("/")
        if rel in ("", "."):
            rel = "index.html"

        full = os.path.realpath(os.path.join(self.root, rel))
        root = os.path.realpath(self.root)
        if not full.startswith(root + os.sep) and full != root:
            self._send(403, b"forbidden")
            return
        if not os.path.isfile(full):
            self._send(404, b"not found")
            return

        ctype = mimetypes.guess_type(full)[0] or "application/octet-stream"
        try:
            with open(full, "rb") as fh:
                data = fh.read()
        except OSError:
            self._send(500, b"read error")
            return
        self._send(200, data, ctype)

    def _exit(self):
        """Mata browser/weston/nw (pids no pidfile) e encerra o servidor."""
        try:
            if self.pidfile and os.path.isfile(self.pidfile):
                with open(self.pidfile) as fh:
                    pids = fh.read().split()
                for pid in pids:
                    pid = pid.strip()
                    if pid.isdigit() and int(pid) != os.getpid():
                        try:
                            os.kill(int(pid), signal.SIGTERM)
                        except (ProcessLookupError, PermissionError):
                            pass
        finally:
            # atraso pequeno pra resposta HTTP sair antes do processo morrer
            threading.Thread(
                target=lambda: (__import__("time").sleep(0.4), os._exit(0)),
                daemon=True,
            ).start()


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--root", default=os.path.dirname(os.path.abspath(__file__)))
    ap.add_argument("--port", type=int, default=8099)
    ap.add_argument("--pidfile", default="/tmp/sketchbook.pids")
    args = ap.parse_args()

    Handler.root = args.root
    Handler.pidfile = args.pidfile

    srv = ThreadingHTTPServer(("127.0.0.1", args.port), Handler)
    print("[serve] root=%s port=%d" % (args.root, args.port))
    sys.stdout.flush()
    try:
        srv.serve_forever()
    except KeyboardInterrupt:
        pass


if __name__ == "__main__":
    main()
