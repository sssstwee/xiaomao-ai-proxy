import importlib.util
import unittest
from pathlib import Path

import yaml

ROOT = Path(__file__).parent
SPEC = importlib.util.spec_from_file_location('routing_policy', ROOT / 'routing_policy.py')
SYNC = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(SYNC)


class PolicyTest(unittest.TestCase):
    def setUp(self):
        self.template = yaml.safe_load((ROOT / 'clash-base.yaml').read_text())
        self.nodes = [
            {'name': 'voyra-direct', 'type': 'vless', 'uuid': 'private-fixture', 'udp': True},
            {'name': 'voyra-warp', 'type': 'vless', 'udp': True},
            {'name': 'voyra-hy2-direct', 'type': 'hysteria2', 'password': 'private-fixture'},
            {'name': 'cf-tcp-backup', 'type': 'vless', 'udp': False},
        ]
        self.current = {'proxies': self.nodes, 'proxy-groups': [{'name': 'old', 'proxies': ['voyra-hy2-direct', 'voyra-direct', 'voyra-warp', 'cf-tcp-backup']}], 'rules': ['MATCH,old'], 'mixed-port': 7890, 'tun': {'enable': True}}

    def test_shared_policy_preserves_credentials_and_runtime_settings(self):
        config = SYNC.render(self.current, self.template)
        self.assertEqual({node['name']: node for node in config['proxies']}, {node['name']: node for node in self.nodes})
        self.assertEqual(config['proxies'][0]['name'], 'voyra-hy2-direct')
        self.assertEqual(config['mixed-port'], 7890)
        self.assertEqual(config['tun'], {'enable': True})
        self.assertEqual(config['rules'], self.template['rules'])
        self.assertEqual(SYNC.render(config, self.template), config)

    def test_ai_excludes_warp_and_cloudflare_backup_without_direct_escape(self):
        config = SYNC.render(self.current, self.template)
        for group in config['proxy-groups']:
            if group['name'] not in ['Claude 专用', 'ChatGPT 专用']:
                continue
            pattern = __import__('re').compile(group['exclude-filter'])
            members = [node['name'] for node in config['proxies'] if not pattern.search(node['name'])]
            self.assertEqual(members, ['voyra-hy2-direct', 'voyra-direct'])
            self.assertEqual(group['proxies'], members)
            self.assertNotIn('include-all-proxies', group)
            self.assertEqual(group['type'], 'fallback')
        self.current['proxies'] = [node for node in self.nodes if 'direct' not in node['name']]
        with self.assertRaises(ValueError):
            SYNC.render(self.current, self.template)

    def test_selector_preserves_group_references_and_load_balance_expands_nodes(self):
        config = SYNC.render(self.current, self.template)
        groups = {group['name']: group for group in config['proxy-groups']}
        self.assertEqual(groups['默认代理']['type'], 'select')
        self.assertEqual(groups['默认代理']['proxies'], ['负载均衡', '自动选择'])
        self.assertEqual(groups['负载均衡']['type'], 'load-balance')
        self.assertEqual(groups['负载均衡']['strategy'], 'round-robin')
        self.assertEqual(groups['负载均衡']['proxies'], [node['name'] for node in config['proxies']])
        self.assertEqual(groups['自动选择']['type'], 'url-test')
        self.assertEqual(groups['自动选择']['proxies'], groups['负载均衡']['proxies'])

    def test_ai_bootstrap_precedes_direct_and_ad_rules(self):
        rules = self.template['rules']
        claude = 'RULE-SET,anthropic-bootstrap,Claude 专用,no-resolve'
        chatgpt = 'RULE-SET,openai-bootstrap,ChatGPT 专用,no-resolve'
        self.assertLess(rules.index(claude), rules.index(chatgpt))
        self.assertLess(rules.index(chatgpt), rules.index('RULE-SET,reject,REJECT'))
        self.assertLess(rules.index(chatgpt), rules.index('RULE-SET,applications,DIRECT'))
        self.assertEqual(rules[0], 'AND,((NETWORK,UDP),(DST-PORT,443)),REJECT')
        providers = self.template['rule-providers']
        self.assertIn('anthropic.auth0.com', providers['anthropic-bootstrap']['payload'])
        self.assertIn('+.oaistatsig.com', providers['openai-bootstrap']['payload'])
        self.assertIn('+.featuregates.org', providers['openai-bootstrap']['payload'])
        self.assertGreater(len(providers['openai-voice']['payload']), 100)
        for group, key in [('Claude 专用', 'rule-set:anthropic-bootstrap,anthropic'), ('ChatGPT 专用', 'rule-set:openai-bootstrap,openai')]:
            self.assertTrue(all(server.endswith('#' + group) for server in self.template['dns']['nameserver-policy'][key]))

    def test_voyra_quic_uses_only_verified_hysteria_nodes_with_reject_fallback(self):
        self.current['proxies'].append({'name': 'voyra-hy2-warp', 'type': 'hysteria2'})
        verified = ['voyra-hy2-direct', 'voyra-hy2-warp', 'voyra-direct', 'cf-tcp-backup', 'missing']
        config = SYNC.render(self.current, self.template, verified)
        group = next(group for group in config['proxy-groups'] if group['name'] == 'Voyra QUIC')
        self.assertEqual(group['proxies'], ['voyra-hy2-direct', 'voyra-hy2-warp'])
        self.assertEqual(group['type'], 'url-test')
        self.assertEqual(config['rules'][:2], [
            'SUB-RULE,(AND,((NETWORK,UDP),(DST-PORT,443))),voyra-quic', SYNC.QUIC_REJECT,
        ])
        self.assertEqual(config['rules'][1:], self.template['rules'])
        rules = config['sub-rules']['voyra-quic']
        self.assertIn('RULE-SET,google,Voyra QUIC', rules)
        self.assertIn('RULE-SET,cncidr,REJECT,no-resolve', rules)
        self.assertIn('RULE-SET,anthropic-bootstrap,REJECT,no-resolve', rules)
        self.assertIn('RULE-SET,openai-bootstrap,REJECT,no-resolve', rules)
        self.assertTrue(all(',DIRECT' not in rule for rule in rules))
        self.assertEqual(SYNC.render(config, self.template, verified), config)
        disabled = SYNC.render(config, self.template, ['voyra-direct', 'missing'])
        self.assertEqual(disabled['rules'], self.template['rules'])
        self.assertNotIn('sub-rules', disabled)

    def test_node_list_indent_remains_compatible_with_edgetunnel_transport_patch(self):
        config = SYNC.render(self.current, self.template)
        content = SYNC.serialize(config)
        self.assertIn(b'proxies:\n  - ', content)
        self.assertEqual(yaml.safe_load(content), config)

    def test_static_dependencies_use_own_repositories_and_survive_rendering(self):
        raw = 'https://raw.githubusercontent.com/sssstwee/edgetunnel/main/resources/'
        providers = self.template['rule-providers'].values()
        remote = [provider for provider in providers if provider['type'] == 'http']
        self.assertEqual(len(remote), 19)
        for provider in remote:
            self.assertTrue(provider['url'].startswith(raw + 'rules/'))
        for group in self.template['proxy-groups']:
            self.assertTrue(group['icon'].startswith(raw + 'icons/'))
        self.assertEqual(SYNC.VOICE_SOURCE, raw + 'data/chatgpt-voice.json')
        config = SYNC.render(self.current, self.template)
        self.assertEqual(set(config['geox-url']), {'geoip', 'geosite', 'mmdb', 'asn'})
        for url in config['geox-url'].values():
            self.assertTrue(url.startswith('https://github.com/sssstwee/edgetunnel/releases/latest/download/'))
        for key in ['geox-url', 'geodata-mode', 'geo-auto-update', 'geo-update-interval']:
            self.assertEqual(config[key], self.template[key])


if __name__ == '__main__':
    unittest.main()
