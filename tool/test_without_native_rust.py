#!/usr/bin/env python3
"""Run Flutter tests without building the native Rust client library."""
import pathlib
import subprocess
import sys

root = pathlib.Path(__file__).resolve().parent.parent
files = sorted(root.glob('test/**/*_test.dart'))
requires_native = [p for p in files if 'initEditorNative' in p.read_text()]
print(f'Native Rust loading remains unverified: {len(requires_native)} test files.', flush=True)
for path in requires_native:
    print(f'  deferred: {path.relative_to(root)}', flush=True)
selected = [str(p.relative_to(root)) for p in files if p not in requires_native]
sys.exit(subprocess.call(['dart', 'tool/test.dart', *selected, '--', '--no-pub', '--reporter', 'expanded', '--concurrency=4'], cwd=root))
