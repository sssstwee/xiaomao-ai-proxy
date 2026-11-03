#!/usr/bin/env python3
import json
import os
import threading
import time
import urllib.error
import urllib.parse
import urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

import yaml

from routing_policy import TEMPLATE, download, render, serialize

CACHE = Path(os.environ.get('ROUTING_TEMPLATE_CACHE', '/var/cache/edgetunnel-policy/template.yaml'))
LOCK = threading.Lock()
UPDATED = 0


def template():
    global UPDATED
    with LOCK:
        if time.monotonic() - UPDATED > 300:
            try:
                content = download(TEMPLATE)
                policy = yaml.safe_load(content)
                if not policy.get('proxy-groups') or not policy.get('rules'):
                    raise ValueError('Invalid template')
                temporary = CACHE.with_suffix('.new')
                temporary.write_bytes(content)
                temporary.replace(CACHE)
                UPDATED = time.monotonic()
            except Exception:
                if not CACHE.exists():
                    raise
        return yaml.safe_load(CACHE.read_bytes())


class Handler(BaseHTTPRequestHandler):
    def log_message(self, *args):
        pass

    def do_GET(self):
        parsed = urllib.parse.urlsplit(self.path)
        if parsed.path != '/sub':
            self.send_error(404)
            return
        try:
            request = urllib.request.Request('http://127.0.0.1:25510' + self.path,
                                             headers={'User-Agent': self.headers.get('User-Agent', 'subconverter')})
            with urllib.request.urlopen(request, timeout=45) as response:
                content = response.read(8 * 1024 * 1024 + 1)
                headers = response.headers
            if len(content) > 8 * 1024 * 1024:
                raise ValueError('Conversion exceeds size limit')
            query = urllib.parse.parse_qs(parsed.query)
            if query.get('target') == ['clash'] and query.get('list', ['false']) != ['true']:
                config = yaml.safe_load(content)
                config = render(config, template())
                content = serialize(config)
            self.send_response(200)
            for name in ['Content-Type', 'Content-Disposition', 'Subscription-Userinfo', 'Profile-Update-Interval']:
                if headers.get(name):
                    self.send_header(name, headers[name])
            self.send_header('Cache-Control', 'no-store')
            self.send_header('Content-Length', str(len(content)))
            self.end_headers()
            self.wfile.write(content)
        except urllib.error.HTTPError as error:
            self.send_error(error.code, 'Subscription conversion failed')
        except Exception:
            self.send_error(502, 'Subscription policy unavailable')


if __name__ == '__main__':
    ThreadingHTTPServer(('127.0.0.1', 25511), Handler).serve_forever()
