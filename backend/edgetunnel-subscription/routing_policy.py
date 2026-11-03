#!/usr/bin/env python3
import argparse
import copy
import hashlib
import ipaddress
import json
import os
import re
import shutil
import subprocess
import tempfile
import urllib.request
from pathlib import Path

import yaml

TEMPLATE = 'https://raw.githubusercontent.com/sssstwee/xiaomao-ai-proxy/main/backend/edgetunnel-subscription/clash-base.yaml'


class IndentedDumper(yaml.SafeDumper):
    def increase_indent(self, flow=False, indentless=False):
        return super().increase_indent(flow, False)


def serialize(config):
    return yaml.dump(config, Dumper=IndentedDumper, allow_unicode=True, sort_keys=False, width=200).encode()


def download(url, limit=262144):
    with urllib.request.urlopen(url, timeout=15) as response:
        content = response.read(limit + 1)
    if len(content) > limit:
        raise ValueError('Hosted policy exceeds size limit')
    return content


def render(current, template):
    result = copy.deepcopy(current)
    for key in ['mode', 'ipv6', 'unified-delay', 'proxy-groups', 'rule-providers', 'rules', 'dns']:
        result[key] = copy.deepcopy(template[key])
    nodes = {node['name']: node for node in current['proxies']}
    old_default = next((rule.split(',')[1] for rule in reversed(current.get('rules', [])) if rule.startswith(('MATCH,', 'FINAL,'))), '')
    old_group = next((group for group in (current.get('proxy-groups') or []) if group['name'] == old_default), {})
    order = list(dict.fromkeys([name for name in old_group.get('proxies', []) if name in nodes] + list(nodes)))
    result['proxies'] = [nodes[name] for name in order]
    for group in result['proxy-groups']:
        filters = [re.compile(pattern) for pattern in group.get('exclude-filter', '').split('`') if pattern]
        members = [name for name in order if not any(pattern.search(name) for pattern in filters)]
        if not members:
            raise ValueError('A hosted proxy group has no usable members')
        group['proxies'] = members
        group.pop('include-all-proxies', None)
    result['harmony-runtime'] = current.get('harmony-runtime', {})
    return result


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--config', default='/opt/voyra-subscription/vpn.yml')
    parser.add_argument('--template', default=TEMPLATE)
    parser.add_argument('--output')
    parser.add_argument('--mihomo')
    parser.add_argument('--mihomo-home', default='/var/lib/voyra-routing')
    args = parser.parse_args()
    target = Path(args.output or args.config)
    current = yaml.safe_load(Path(args.config).read_text())
    raw = download(args.template) if args.template.startswith('https://') else Path(args.template).read_bytes()
    template = yaml.safe_load(raw)
    voice = template.get('rule-providers', {}).get('openai-voice')
    if voice:
        try:
            document = json.loads(download('https://openai.com/chatgpt-voice.json'))
            prefixes = [entry[key] for entry in document['prefixes'] for key in ['ipv4Prefix', 'ipv6Prefix'] if key in entry]
            if not prefixes or len(prefixes) > 10000:
                raise ValueError('Invalid voice prefix count')
            for prefix in prefixes:
                ipaddress.ip_network(prefix, strict=False)
            voice['payload'] = list(dict.fromkeys(prefixes))
        except Exception:
            pass
    content = serialize(render(current, template))
    if target.exists() and target.read_bytes() == content:
        print(json.dumps({'changed': False, 'sha256': hashlib.sha256(content).hexdigest()}))
        return
    target.parent.mkdir(parents=True, exist_ok=True)
    descriptor, temporary = tempfile.mkstemp(prefix='.routing-', suffix='.yaml', dir=target.parent)
    try:
        with os.fdopen(descriptor, 'wb') as stream:
            stream.write(content)
            stream.flush()
            os.fsync(stream.fileno())
        if target.exists():
            metadata = target.stat()
            os.chmod(temporary, metadata.st_mode & 0o777)
            os.chown(temporary, metadata.st_uid, metadata.st_gid)
        if args.mihomo:
            checked = subprocess.run([args.mihomo, '-t', '-f', temporary, '-d', args.mihomo_home], capture_output=True)
            if checked.returncode:
                raise ValueError('Mihomo rejected the hosted configuration; current subscription retained')
        if target.exists():
            backup = target.parent / 'backups' / ('routing-' + hashlib.sha256(target.read_bytes()).hexdigest()[:16] + '.yaml')
            backup.parent.mkdir(mode=0o700, exist_ok=True)
            if not backup.exists():
                shutil.copy2(target, backup)
                backup.chmod(0o600)
        os.replace(temporary, target)
    finally:
        Path(temporary).unlink(missing_ok=True)
    print(json.dumps({'changed': True, 'sha256': hashlib.sha256(content).hexdigest()}))


if __name__ == '__main__':
    try:
        main()
    except Exception as error:
        raise SystemExit('Routing sync failed: ' + type(error).__name__)
