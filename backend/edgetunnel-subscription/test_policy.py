import importlib.util
import unittest
from pathlib import Path

import yaml

ROOT = Path(__file__).parent
AI_GROUPS = ['Claude 专用', 'ChatGPT 专用', 'Gemini 专用']
GEMINI_PROVIDERS = ['gemini-bootstrap', 'gemini', 'google']
PROCESS_RULES = [
    'PROCESS-NAME-REGEX,(?i)^(antigravity|gemini)( helper.*| \\(.*\\))?(\\.exe)?$,Gemini 专用',
    'PROCESS-PATH-REGEX,(?i)(/Applications/Antigravity\\.app/|\\\\Programs\\\\Antigravity\\\\),Gemini 专用',
]
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
            if group['name'] not in AI_GROUPS:
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

    def test_selector_defaults_to_ordered_failover_and_preserves_manual_modes(self):
        config = SYNC.render(self.current, self.template)
        groups = {group['name']: group for group in config['proxy-groups']}
        self.assertEqual(groups['默认代理']['type'], 'select')
        self.assertEqual(groups['默认代理']['proxies'], ['自动选择', '故障转移'])
        self.assertEqual(groups['故障转移']['type'], 'fallback')
        self.assertEqual(groups['故障转移']['proxies'], [node['name'] for node in config['proxies']])
        self.assertNotIn('负载均衡', groups)
        self.assertEqual(groups['自动选择']['type'], 'url-test')
        self.assertEqual(groups['自动选择']['proxies'], groups['故障转移']['proxies'])
        for name in ['故障转移', '自动选择']:
            self.assertEqual((groups[name]['interval'], groups[name]['timeout'], groups[name]['lazy'], groups[name]['max-failed-times']), (300, 5000, True, 3))
        self.assertEqual(groups['自动选择']['tolerance'], 100)
        for name in AI_GROUPS:
            self.assertEqual((groups[name]['interval'], groups[name]['timeout'], groups[name]['lazy'], groups[name]['max-failed-times']), (600, 5000, True, 3))

    def test_ai_bootstrap_precedes_general_proxy_and_domestic_rules(self):
        rules = self.template['rules']
        claude = 'RULE-SET,anthropic-bootstrap,Claude 专用,no-resolve'
        chatgpt = 'RULE-SET,openai-bootstrap,ChatGPT 专用,no-resolve'
        self.assertLess(rules.index(claude), rules.index(chatgpt))
        self.assertLess(rules.index(chatgpt), rules.index('RULE-SET,reject,REJECT'))
        self.assertLess(rules.index(chatgpt), rules.index('GEOSITE,cn,DIRECT'))
        self.assertEqual([rule for rule in rules if ',DIRECT' in rule], [
            'RULE-SET,cn-ai-extra,DIRECT', 'RULE-SET,private,DIRECT', 'RULE-SET,lancidr,DIRECT,no-resolve',
            'RULE-SET,ai-cn,DIRECT', 'RULE-SET,direct,DIRECT', 'GEOSITE,cn,DIRECT',
            'RULE-SET,cncidr,DIRECT,no-resolve',
        ])
        self.assertEqual(rules[-2:], ['MATCH,默认代理', 'NETWORK,UDP,REJECT'])
        self.assertEqual(rules[0], 'AND,((NETWORK,UDP),(DST-PORT,443)),REJECT')
        providers = self.template['rule-providers']
        self.assertIn('anthropic.auth0.com', providers['anthropic-bootstrap']['payload'])
        self.assertIn('+.oaistatsig.com', providers['openai-bootstrap']['payload'])
        self.assertIn('+.featuregates.org', providers['openai-bootstrap']['payload'])
        self.assertGreater(len(providers['openai-voice']['payload']), 100)
        for group, key in [('Claude 专用', 'rule-set:anthropic-bootstrap,anthropic'), ('ChatGPT 专用', 'rule-set:openai-bootstrap,openai')]:
            self.assertTrue(all(server.endswith('#' + group) for server in self.template['dns']['nameserver-policy'][key]))

    def test_voyra_quic_uses_only_verified_hysteria_nodes_with_reject_fallback(self):
        self.current['sub-rules'] = None
        self.current['proxies'].append({'name': 'voyra-hy2-warp', 'type': 'hysteria2'})
        verified = ['voyra-hy2-direct', 'voyra-hy2-warp', 'voyra-direct', 'cf-tcp-backup', 'missing']
        config = SYNC.render(self.current, self.template, verified)
        group = next(group for group in config['proxy-groups'] if group['name'] == 'Voyra QUIC')
        self.assertEqual(group['proxies'], ['voyra-hy2-direct', 'voyra-hy2-warp'])
        self.assertEqual(group['type'], 'load-balance')
        self.assertEqual(group['strategy'], 'round-robin')
        self.assertEqual(config['rules'][:2], [
            'SUB-RULE,(AND,((NETWORK,UDP),(DST-PORT,443))),voyra-quic', SYNC.QUIC_REJECT,
        ])
        self.assertEqual(config['rules'][1:], self.template['rules'])
        rules = config['sub-rules']['voyra-quic']
        self.assertIn('RULE-SET,google,REJECT,no-resolve', rules)
        self.assertIn('RULE-SET,lancidr,REJECT,no-resolve', rules)
        self.assertIn('GEOSITE,cn,REJECT', rules)
        self.assertEqual(rules[-2:], ['MATCH,Voyra QUIC', 'NETWORK,UDP,REJECT'])
        self.assertIn('RULE-SET,anthropic-bootstrap,REJECT,no-resolve', rules)
        self.assertIn('RULE-SET,openai-bootstrap,REJECT,no-resolve', rules)
        self.assertTrue(all(',DIRECT' not in rule for rule in rules))
        self.assertEqual(SYNC.render(config, self.template, verified), config)
        disabled = SYNC.render(config, self.template, ['voyra-direct', 'missing'])
        self.assertEqual(disabled['rules'], self.template['rules'])
        self.assertNotIn('sub-rules', disabled)

    def test_ai_quic_pins_verified_dedicated_node_before_reject(self):
        config = SYNC.render(self.current, self.template, ['voyra-hy2-direct'])
        rules = config['sub-rules']['voyra-quic']
        ai_providers = ['anthropic-bootstrap', 'anthropic', 'anthropic-ip', 'claude-deps', 'openai-bootstrap', 'openai', 'openai-voice']
        for provider in ai_providers:
            allowed = f'RULE-SET,{provider},voyra-hy2-direct,no-resolve'
            rejected = f'RULE-SET,{provider},REJECT,no-resolve'
            position = rules.index(allowed)
            self.assertEqual(rules[position + 1], rejected)
            self.assertNotIn(f'AND,((NETWORK,UDP),(RULE-SET,{provider})),REJECT', rules[:position])
            self.assertLess(position, rules.index('GEOSITE,cn,REJECT'))
        baseline = SYNC.render(self.current, self.template)
        self.assertEqual(config['rules'][1:], baseline['rules'])
        self.assertEqual(config['proxy-groups'][:-1], baseline['proxy-groups'])
        self.assertEqual(config['dns'], baseline['dns'])

    def test_ai_quic_stays_rejected_without_verified_dedicated_membership(self):
        self.current['proxies'].append({'name': 'voyra-hy2-warp', 'type': 'hysteria2'})
        config = SYNC.render(self.current, self.template, ['voyra-hy2-warp'])
        self.assertFalse(any(',voyra-hy2-direct' in rule for rule in config['sub-rules']['voyra-quic']))
        for group in self.template['proxy-groups']:
            if group['name'] in ['Claude 专用', 'ChatGPT 专用']:
                group['exclude-filter'] += '|^voyra-hy2-direct$'
        config = SYNC.render(self.current, self.template, ['voyra-hy2-direct', 'voyra-hy2-warp'])
        rules = config['sub-rules']['voyra-quic']
        self.assertFalse(any(',voyra-hy2-direct' in rule for rule in rules))
        self.assertIn('AND,((NETWORK,UDP),(RULE-SET,anthropic-bootstrap)),REJECT', rules)
        self.assertIn('AND,((NETWORK,UDP),(RULE-SET,openai-bootstrap)),REJECT', rules)

    def test_ai_routes_and_dns_cannot_reach_load_balance(self):
        expected = {
            'anthropic-bootstrap': 'Claude 专用',
            'anthropic': 'Claude 专用',
            'anthropic-ip': 'Claude 专用',
            'claude-deps': 'Claude 专用',
            'openai-bootstrap': 'ChatGPT 专用',
            'openai': 'ChatGPT 专用',
            'openai-voice': 'ChatGPT 专用',
            'ai': '故障转移',
            'artifact-resources': '故障转移',
            'ai-resources': '故障转移',
            'gemini-bootstrap': 'Gemini 专用',
            'meta-bootstrap': '故障转移',
            'ai-shared': '故障转移',
            'gemini': 'Gemini 专用',
            'twitter-ai': '故障转移',
            'bing-ai': '故障转移',
            'google': 'Gemini 专用',
        }
        for config in [self.template, SYNC.render(self.current, self.template, ['voyra-hy2-direct'])]:
            groups = {group['name']: group for group in config['proxy-groups']}

            def reaches_balance(name, seen=None):
                seen = set() if seen is None else seen
                if name in seen:
                    return False
                seen.add(name)
                group = groups.get(name, {})
                return group.get('type') == 'load-balance' or any(
                    reaches_balance(member, seen) for member in group.get('proxies', [])
                )

            for rule in config['rules']:
                parts = rule.split(',')
                if parts[0] == 'RULE-SET' and parts[1] in expected:
                    self.assertEqual(parts[2], expected[parts[1]])
                    self.assertFalse(reaches_balance(parts[2]), rule)
            for rule in config.get('sub-rules', {}).get('voyra-quic', []):
                parts = rule.split(',')
                if parts[0] == 'RULE-SET' and parts[1] in expected:
                    self.assertIn(parts[2], ['REJECT', 'voyra-hy2-direct'])
                    self.assertFalse(reaches_balance(parts[2]), rule)
            for key, servers in config['dns']['nameserver-policy'].items():
                if not key.startswith('rule-set:'):
                    continue
                for provider in key.removeprefix('rule-set:').split(','):
                    if provider in expected:
                        self.assertTrue(all(server.endswith('#' + expected[provider]) for server in servers), key)
                        self.assertTrue(all(not reaches_balance(server.rsplit('#', 1)[-1]) for server in servers), key)
            self.assertEqual(groups['默认代理']['proxies'], ['自动选择', '故障转移'])

    def test_edgetunnel_ordinary_groups_reuse_strict_ai_pool(self):
        self.current['proxies'] = [
            {'name': '192.0.2.1 洛杉矶 · AI', 'type': 'vless'},
            {'name': '198.51.100.1 新加坡 · 普通', 'type': 'vless'},
            {'name': '192.0.2.2 洛杉矶 · AI', 'type': 'vless'},
            {'name': '198.51.100.2 洛杉矶 · 普通', 'type': 'vless'},
        ]
        config = SYNC.render(self.current, self.template)
        groups = {group['name']: group for group in config['proxy-groups']}
        for name in AI_GROUPS:
            self.assertEqual(groups[name]['proxies'], ['192.0.2.1 洛杉矶 · AI', '192.0.2.2 洛杉矶 · AI'])
            if name == 'Gemini 专用':
                continue
            self.assertNotIn('dns.google', str(config['dns']['nameserver-policy'][
                'rule-set:anthropic-bootstrap,anthropic' if name == 'Claude 专用'
                else 'rule-set:openai-bootstrap,openai']))
        for name in ['故障转移', '自动选择']:
            self.assertEqual(groups[name]['proxies'], ['192.0.2.1 洛杉矶 · AI', '192.0.2.2 洛杉矶 · AI'])
            self.assertEqual(groups[name]['url'], 'https://cp.cloudflare.com/generate_204')
            self.assertEqual(groups[name]['expected-status'], '204')
        rules = config['rules']
        self.assertLess(rules.index('RULE-SET,anthropic-bootstrap,Claude 专用,no-resolve'),
                        rules.index('RULE-SET,ai-resources,故障转移,no-resolve'))
        self.assertIn('openaiassets.blob.core.windows.net',
                      config['rule-providers']['ai-resources']['payload'])
        self.current['proxies'] = self.current['proxies'][1::2]
        with self.assertRaises(ValueError):
            SYNC.render(self.current, self.template)

    def test_node_list_indent_remains_compatible_with_edgetunnel_transport_patch(self):
        config = SYNC.render(self.current, self.template)
        content = SYNC.serialize(config)
        self.assertIn(b'proxies:\n  - ', content)
        self.assertEqual(yaml.safe_load(content), config)

    def test_pinned_ai_dependencies_precede_broad_domestic_rules_in_routing_and_dns(self):
        rules = self.template['rules']
        policy_keys = list(self.template['dns']['nameserver-policy'])
        domestic_route = rules.index('RULE-SET,ai-cn,DIRECT')
        domestic_dns = policy_keys.index('rule-set:ai-cn')
        self.assertLess(rules.index('RULE-SET,cn-ai-extra,DIRECT'),
                        rules.index('RULE-SET,anthropic-bootstrap,Claude 专用,no-resolve'))
        for provider in ['gemini-bootstrap', 'meta-bootstrap', 'ai-shared', 'gemini',
                         'twitter-ai', 'bing-ai', 'google']:
            target = 'Gemini 专用' if provider in GEMINI_PROVIDERS else '故障转移'
            route = rules.index(f'RULE-SET,{provider},{target},no-resolve')
            self.assertLess(route, domestic_route, provider)
            self.assertEqual(rules[route - 1], f'AND,((NETWORK,UDP),(RULE-SET,{provider})),REJECT')
            dns_key = next(key for key in policy_keys if key.startswith('rule-set:')
                           and provider in key.removeprefix('rule-set:').split(','))
            self.assertLess(policy_keys.index(dns_key), domestic_dns, provider)

    def test_static_dependencies_use_own_repositories_and_survive_rendering(self):
        raw = 'https://raw.githubusercontent.com/sssstwee/edgetunnel/main/resources/'
        providers = self.template['rule-providers'].values()
        remote = [provider for provider in providers if provider['type'] == 'http']
        self.assertEqual(len(remote), 19)
        for provider in remote:
            self.assertTrue(provider['url'].startswith(raw + 'rules/'))
            # Large domain / IP lists load as Mihomo binary rule sets; classical lists stay YAML.
            binary = provider['behavior'] in ['domain', 'ipcidr']
            self.assertEqual(provider['format'], 'mrs' if binary else 'yaml', provider['url'])
            self.assertTrue(provider['url'].endswith('.mrs' if binary else '.yaml'), provider['url'])
            self.assertTrue(provider['path'].endswith('.mrs' if binary else '.yaml'), provider['path'])
        self.assertEqual(sum(provider['format'] == 'mrs' for provider in remote), 18)
        for group in self.template['proxy-groups']:
            self.assertTrue(group['icon'].startswith(raw + 'icons/'))
        self.assertEqual(SYNC.VOICE_SOURCE, raw + 'data/chatgpt-voice.json')
        config = SYNC.render(self.current, self.template)
        self.assertEqual(set(config['geox-url']), {'geoip', 'geosite', 'mmdb', 'asn'})
        for url in config['geox-url'].values():
            self.assertTrue(url.startswith('https://github.com/sssstwee/edgetunnel/releases/latest/download/'))
        for key in ['geox-url', 'geodata-mode', 'geo-auto-update', 'geo-update-interval']:
            self.assertEqual(config[key], self.template[key])

    def test_claude_dependencies_share_the_claude_group_ahead_of_shared_bootstraps(self):
        rules = self.template['rules']
        route = rules.index('RULE-SET,claude-deps,Claude 专用,no-resolve')
        self.assertEqual(rules[route - 1], 'AND,((NETWORK,UDP),(RULE-SET,claude-deps)),REJECT')
        self.assertEqual(rules[route - 2], 'RULE-SET,anthropic-ip,Claude 专用,no-resolve')
        self.assertLess(route, rules.index('RULE-SET,openai-bootstrap,ChatGPT 专用,no-resolve'))
        payload = self.template['rule-providers']['claude-deps']['payload']
        self.assertEqual(len(set(payload)), len(payload))
        for host in ['+.datadoghq.com', 'cdn.growthbook.io', 'o1158394.ingest.us.sentry.io', '+.statsig.com',
                     '+.hcaptcha.com', 'challenges.cloudflare.com', 'js.stripe.com', '+.intercom.io',
                     '+.segment.io', 'storage.googleapis.com', 'registry.npmjs.org', 'mcp.notion.com']:
            self.assertIn(host, payload)
        # Hosts other assistants sign in through stay on their own groups.
        for host in ['+.sentry.io', '+.workos.com', 'accounts.google.com', 'oauth2.googleapis.com', 'login.microsoftonline.com']:
            self.assertNotIn(host, payload)
        domestic = set(self.template['rule-providers']['cn-ai-extra']['payload'])
        self.assertFalse(domestic & set(payload))
        keys = list(self.template['dns']['nameserver-policy'])
        self.assertLess(keys.index('rule-set:claude-deps'), keys.index('rule-set:openai-bootstrap,openai'))
        self.assertTrue(all(server.endswith('#Claude 专用') for server in self.template['dns']['nameserver-policy']['rule-set:claude-deps']))

    def test_domestic_addresses_without_a_domain_stay_direct_after_every_proxy_rule(self):
        rules = self.template['rules']
        route = rules.index('RULE-SET,cncidr,DIRECT,no-resolve')
        self.assertEqual(rules[route - 1], 'GEOSITE,cn,DIRECT')
        self.assertEqual(rules[route + 1:-2], PROCESS_RULES)
        self.assertEqual(rules[-2:], ['MATCH,默认代理', 'NETWORK,UDP,REJECT'])
        provider = self.template['rule-providers']['cncidr']
        self.assertEqual((provider['type'], provider['behavior']), ('http', 'ipcidr'))
        sniffer = self.template['sniffer']
        self.assertTrue(sniffer['enable'] and sniffer['parse-pure-ip'])
        self.assertFalse(sniffer['override-destination'])
        self.assertEqual(set(sniffer['sniff']), {'HTTP', 'TLS', 'QUIC'})

    def test_gemini_and_antigravity_share_a_dedicated_group_for_routes_dns_and_processes(self):
        groups = {group['name']: group for group in self.template['proxy-groups']}
        gemini = groups['Gemini 专用']
        claude = groups['Claude 专用']
        self.assertEqual(gemini['type'], 'fallback')
        self.assertEqual(gemini['url'], 'https://generativelanguage.googleapis.com/v1beta/models')
        self.assertEqual(gemini['expected-status'], '403/404')
        self.assertEqual(gemini['exclude-filter'], claude['exclude-filter'])
        self.assertTrue(gemini['icon'].endswith('/icons/Gemini.png'))
        rules = self.template['rules']
        for provider in GEMINI_PROVIDERS:
            route = rules.index(f'RULE-SET,{provider},Gemini 专用,no-resolve')
            self.assertEqual(rules[route - 1], f'AND,((NETWORK,UDP),(RULE-SET,{provider})),REJECT')
            self.assertGreater(route, rules.index('RULE-SET,openai-voice,ChatGPT 专用,no-resolve'))
        payload = self.template['rule-providers']['gemini-bootstrap']['payload']
        for host in ['antigravity-pa.googleapis.com', 'antigravity.googleapis.com', '+.antigravity.google',
                     'cloudcode-pa.googleapis.com', '+.generativelanguage.googleapis.com', 'accounts.google.com']:
            self.assertIn(host, payload)
        policy = self.template['dns']['nameserver-policy']
        for key in ['+.gemini.google.com', 'rule-set:gemini-bootstrap,gemini,google']:
            self.assertTrue(all(server.endswith('#Gemini 专用') for server in policy[key]), key)
        self.assertEqual(self.template['find-process-mode'], 'strict')
        name, path = [__import__('re').compile(rule.split(',')[1]) for rule in PROCESS_RULES]
        for process in ['Antigravity', 'Antigravity Helper (Renderer)', 'Antigravity.exe', 'gemini']:
            self.assertTrue(name.search(process), process)
        for process in ['Google Chrome', 'node', 'geminiweb']:
            self.assertFalse(name.search(process), process)
        for location in ['/Applications/Antigravity.app/Contents/Resources/app/extensions/antigravity/bin/language_server_macos_arm',
                         'C:\\Users\\me\\AppData\\Local\\Programs\\Antigravity\\Antigravity.exe']:
            self.assertTrue(path.search(location), location)
        config = SYNC.render(self.current, self.template, ['voyra-hy2-direct'])
        quic = config['sub-rules']['voyra-quic']
        for provider in GEMINI_PROVIDERS:
            self.assertIn(f'RULE-SET,{provider},REJECT,no-resolve', quic)
        for rule in PROCESS_RULES:
            self.assertIn(rule.rsplit(',', 1)[0] + ',REJECT', quic)

    def test_ad_and_tracker_list_is_blocked_after_ai_and_before_domestic_rules(self):
        rules = self.template['rules']
        block = rules.index('RULE-SET,reject,REJECT')
        self.assertNotIn('RULE-SET,reject,默认代理', rules)
        for rule in ['RULE-SET,claude-deps,Claude 专用,no-resolve', 'RULE-SET,openai-bootstrap,ChatGPT 专用,no-resolve',
                     'RULE-SET,google,Gemini 专用,no-resolve', 'RULE-SET,ai-cn,DIRECT', 'RULE-SET,ai,故障转移']:
            self.assertLess(rules.index(rule), block, rule)
        self.assertLess(block, rules.index('RULE-SET,direct,DIRECT'))
        self.assertFalse(any('reject' in key.removeprefix('rule-set:').split(',')
                             for key in self.template['dns']['nameserver-policy'] if key.startswith('rule-set:')))


if __name__ == '__main__':
    unittest.main()
