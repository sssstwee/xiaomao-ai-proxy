import pathlib
import shutil
import subprocess
import tempfile
import unittest


SCRIPT = pathlib.Path(__file__).resolve().parents[2] / '.github/scripts/check-no-secrets.sh'


class SecretsScanTest(unittest.TestCase):
    def scan(self, path, content):
        with tempfile.TemporaryDirectory() as tmp:
            root = pathlib.Path(tmp)
            script = root / '.github/scripts/check-no-secrets.sh'
            script.parent.mkdir(parents=True)
            shutil.copyfile(SCRIPT, script)
            fixture = root / path
            fixture.parent.mkdir(parents=True, exist_ok=True)
            fixture.write_text(content)
            subprocess.run(['git', 'init', '-q', tmp], check=True)
            subprocess.run(['git', '-C', tmp, 'add', '.'], check=True)
            return subprocess.run(['bash', str(script)], capture_output=True, text=True)

    def test_share_link_serializer_and_ui_placeholder_are_not_secrets(self):
        result = self.scan('lib/sample.dart', 'const prefix = "vmess://"; const hint = "vless://…";')
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_go_test_fixtures_are_recognized(self):
        result = self.scan('core/sample_test.go', 'const sample = "trojan://example@example.com:443"')
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_real_share_link_outside_fixtures_is_rejected_without_printing_it(self):
        value = 'vless://example-user@example.com:443'
        result = self.scan('config.txt', value)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('proxy URI outside test fixtures', result.stderr)
        self.assertNotIn(value, result.stderr + result.stdout)

    def test_private_config_file_still_fails_without_credentials(self):
        result = self.scan('env.json', '{}')
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('private configuration file', result.stderr)


if __name__ == '__main__':
    unittest.main()
