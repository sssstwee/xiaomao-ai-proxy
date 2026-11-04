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
VOICE_SOURCE = 'https://raw.githubusercontent.com/sssstwee/edgetunnel/main/resources/data/chatgpt-voice.json'
QUIC_MATCH = 'AND,((NETWORK,UDP),(DST-PORT,443))'
QUIC_REJECT = f'{QUIC_MATCH},REJECT'
QUIC_GROUP = 'Voyra QUIC'
QUIC_RULES = 'voyra-quic'


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


def render(current, template, quic_nodes=()):
    result = copy.deepcopy(current)
    for key in ['mode', 'ipv6', 'unified-delay', 'proxy-groups', 'rule-providers', 'rules', 'dns']:
        result[key] = copy.deepcopy(template[key])
    for key in ['geox-url', 'geodata-mode', 'geo-auto-update', 'geo-update-interval']:
        if key in template:
            result[key] = copy.deepcopy(template[key])
    nodes = {node['name']: node for node in current['proxies']}
    old_default = next((rule.split(',')[1] for rule in reversed(current.get('rules', [])) if rule.startswith(('MATCH,', 'FINAL,'))), '')
    old_group = next((group for group in (current.get('proxy-groups') or []) if group['name'] == old_default), {})
    order = list(dict.fromkeys([name for name in old_group.get('proxies', []) if name in nodes] + list(nodes)))
    result['proxies'] = [nodes[name] for name in order]
    for group in result['proxy-groups']:
        if not group.get('include-all-proxies'):
            continue
        filters = [re.compile(pattern) for pattern in group.get('exclude-filter', '').split('`') if pattern]
        members = [name for name in order if not any(pattern.search(name) for pattern in filters)]
        if not members:
            raise ValueError('A hosted proxy group has no usable members')
        group['proxies'] = members
        group.pop('include-all-proxies', None)

    sub_rules = result.get('sub-rules') or {}
    if QUIC_RULES in sub_rules:
        del sub_rules[QUIC_RULES]
        if not sub_rules:
            del result['sub-rules']
    verified = [name for name in order if name in quic_nodes and nodes[name]['type'] == 'hysteria2']
    if verified:
        if result['rules'][0] != QUIC_REJECT:
            raise ValueError('Missing initial QUIC rejection rule')
        auto = next(group for group in result['proxy-groups'] if group['name'] == '自动选择')
        result['proxy-groups'].append({**auto, 'name': QUIC_GROUP, 'proxies': verified})
        quic_rules = []
        for rule in result['rules'][1:]:
            match, _, target = rule.removesuffix(',no-resolve').rpartition(',')
            # Keep the template's rule order, with every direct or AI route closed to QUIC.
            quic_target = QUIC_GROUP if target == '默认代理' else 'REJECT'
            params = ',no-resolve' if rule.endswith(',no-resolve') else ''
            quic_rules.append(f'{match},{quic_target}{params}')
        sub_rules[QUIC_RULES] = quic_rules
        result['sub-rules'] = sub_rules
        result['rules'].insert(0, f'SUB-RULE,({QUIC_MATCH}),{QUIC_RULES}')
    result['harmony-runtime'] = current.get('harmony-runtime', {})
    return result


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--config', default='/opt/voyra-subscription/vpn.yml')
    parser.add_argument('--template', default=TEMPLATE)
    parser.add_argument('--output')
    parser.add_argument('--mihomo')
    parser.add_argument('--mihomo-home', default='/var/lib/voyra-routing')
    parser.add_argument('--quic-node', action='append', default=[])
    args = parser.parse_args()
    target = Path(args.output or args.config)
    current = yaml.safe_load(Path(args.config).read_text())
    raw = download(args.template) if args.template.startswith('https://') else Path(args.template).read_bytes()
    template = yaml.safe_load(raw)
    voice = template.get('rule-providers', {}).get('openai-voice')
    if voice:
        try:
            document = json.loads(download(VOICE_SOURCE))
            prefixes = [entry[key] for entry in document['prefixes'] for key in ['ipv4Prefix', 'ipv6Prefix'] if key in entry]
            if not prefixes or len(prefixes) > 10000:
                raise ValueError('Invalid voice prefix count')
            for prefix in prefixes:
                ipaddress.ip_network(prefix, strict=False)
            voice['payload'] = list(dict.fromkeys(prefixes))
        except Exception:
            pass
    content = serialize(render(current, template, args.quic_node))
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
