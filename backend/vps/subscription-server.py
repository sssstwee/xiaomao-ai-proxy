#!/usr/bin/env python3
import hashlib
import json
import os
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qs, urlparse

TOKEN = os.environ.get("VOYRA_SUB_TOKEN", "")
SUB_FILE = os.environ.get("VOYRA_SUB_FILE", "/opt/voyra-subscription/vpn.yml")
SING_BOX_FILE = os.environ.get("VOYRA_SING_BOX_FILE", "/opt/voyra-subscription/sing-box.json")
SING_BOX_WARP_FILE = os.environ.get("VOYRA_SING_BOX_WARP_FILE", "/opt/voyra-subscription/sing-box-warp.json")
BIND = os.environ.get("VOYRA_SUB_BIND", "0.0.0.0")
PORT = int(os.environ.get("VOYRA_SUB_PORT", "1024"))

YAML_CT = "text/yaml; charset=utf-8"
JSON_CT = "application/json; charset=utf-8"

class Handler(BaseHTTPRequestHandler):
    server_version = "voyra-subscription/1.4"

    def log_message(self, fmt, *args):
        print("%s - - [%s] %s" % (self.client_address[0], self.log_date_time_string(), fmt % args), flush=True)

    def _write(self, code, body, content_type="text/plain; charset=utf-8"):
        if isinstance(body, str):
            body = body.encode("utf-8")
        self.send_response(code)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(body)

    def _send_version(self, path):
        try:
            with open(path, "rb") as f:
                data = f.read()
                mtime = int(os.fstat(f.fileno()).st_mtime)
        except FileNotFoundError:
            self._write(503, "subscription unavailable\n")
            return
        body = json.dumps({"version": hashlib.sha256(data).hexdigest()[:16], "updated_at": mtime, "min_check_seconds": 300}).encode()
        self.send_response(200)
        self.send_header("Content-Type", JSON_CT)
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-cache")
        self.end_headers()
        self.wfile.write(body)

    def _send_file(self, path, content_type):
        try:
            with open(path, "rb") as f:
                data = f.read()
        except FileNotFoundError:
            self._write(503, "subscription unavailable\n")
            return
        digest = hashlib.sha256(data).hexdigest()
        etag = '"%s"' % digest
        inm = self.headers.get("If-None-Match", "")
        if inm and (inm.strip() == "*" or etag in [t.strip().removeprefix("W/") for t in inm.split(",")]):
            self.send_response(304)
            self.send_header("ETag", etag)
            self.send_header("X-Config-Version", digest[:16])
            self.send_header("Cache-Control", "no-store")
            self.end_headers()
            return
        self.send_response(200)
        self.send_header("ETag", etag)
        self.send_header("X-Config-Version", digest[:16])
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(data)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(data)

    def _target_from_request(self, parsed):
        query = parse_qs(parsed.query)
        explicit = " ".join(
            query.get("target", [])
            + query.get("type", [])
            + query.get("format", [])
            + query.get("exit", [])
            + query.get("profile", [])
        ).lower()
        if any(x in explicit for x in ("warp", "cfwarp", "cloudflare-warp")):
            return "sing-box-warp"
        if any(x in explicit for x in ("sing-box", "singbox", "hiddify", "json")):
            return "sing-box"
        if any(x in explicit for x in ("clash", "mihomo", "yaml", "yml", "flclash")):
            return "clash"

        ua = self.headers.get("User-Agent", "").lower()
        accept = self.headers.get("Accept", "").lower()
        if any(x in ua for x in ("hiddify", "sing-box", "singbox", "sfa/", "sfi/", "sft/")):
            return "sing-box"
        if any(x in ua for x in ("clash", "mihomo", "flclash", "clash-verge", "clashmeta", "metacubex")):
            return "clash"
        if "application/json" in accept and "text/yaml" not in accept and "application/yaml" not in accept:
            return "sing-box"
        return "clash"

    def _send_auto(self, parsed):
        target = self._target_from_request(parsed)
        if target == "sing-box-warp":
            self._send_file(SING_BOX_WARP_FILE, JSON_CT)
            return
        if target == "sing-box":
            self._send_file(SING_BOX_FILE, JSON_CT)
            return
        self._send_file(SUB_FILE, YAML_CT)

    def do_GET(self):
        parsed = urlparse(self.path)
        path = parsed.path
        if path == "/healthz":
            self._write(200, "ok\n")
            return
        if not TOKEN:
            self._write(404, "not found\n")
            return
        if path == f"/{TOKEN}/home.json":
            self._send_file(os.path.join(os.path.dirname(SUB_FILE), "home.json"), JSON_CT)
            return
        if path == f"/{TOKEN}/vpn.yml/version":
            self._send_version(SUB_FILE)
            return
        if path in (f"/{TOKEN}/vpn.yml", f"/{TOKEN}/clash.yml", f"/{TOKEN}/mihomo.yml"):
            self._send_file(SUB_FILE, YAML_CT)
            return
        if path in (
            f"/{TOKEN}/sing-box-warp.json",
            f"/{TOKEN}/singbox-warp.json",
            f"/{TOKEN}/hiddify-warp.json",
        ):
            self._send_file(SING_BOX_WARP_FILE, JSON_CT)
            return
        if path in (f"/{TOKEN}/sing-box.json", f"/{TOKEN}/singbox.json", f"/{TOKEN}/hiddify.json"):
            self._send_file(SING_BOX_FILE, JSON_CT)
            return
        if path in (f"/{TOKEN}/sub", f"/{TOKEN}/subscribe", f"/{TOKEN}/config"):
            self._send_auto(parsed)
            return
        self._write(404, "not found\n")

if __name__ == "__main__":
    ThreadingHTTPServer((BIND, PORT), Handler).serve_forever()
