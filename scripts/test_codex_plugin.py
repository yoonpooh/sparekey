#!/usr/bin/env python3
"""Isolated Codex installer tests; never runs setup or touches the real home/helper."""
import argparse
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--real-codex', action='store_true')
args = parser.parse_args()
repo = Path(__file__).resolve().parents[1]
binary = repo / '.build/debug/sparekey'
source = (repo / 'skills/sparekey/SKILL.md').read_bytes()
count = 0

with tempfile.TemporaryDirectory(prefix='sparekey-plugin-', dir=repo / '.build') as temp:
    base = Path(temp)
    fake = base / 'codex'
    fake.write_text('#!' + sys.executable + '\n' + r'''
import json, os, sys, time
from pathlib import Path
home = Path(os.environ['SPAREKEY_TEST_HOME'])
state = home / 'fake-state.json'
args = sys.argv[1:]
mode = os.environ.get('SPAREKEY_FAKE_CODEX_MODE', '')
with (home / 'calls.jsonl').open('a') as out: out.write(json.dumps(args) + '\n')
if mode == 'unsupported':
    print('unrecognized subcommand plugin', file=sys.stderr); sys.exit(2)
if args[1] == 'list':
    if mode == 'malformed': print('{}'); sys.exit(0)
    print(json.dumps({'installed': [json.loads(state.read_text())] if state.exists() else []}))
elif args[1] == 'add':
    if mode == 'failure': print('install failed', file=sys.stderr); sys.exit(1)
    if mode == 'timeout': time.sleep(60)
    manifest = json.loads((home / 'plugins/sparekey/.codex-plugin/plugin.json').read_text())
    entry = {'pluginId': args[2], 'name': 'sparekey', 'version': manifest['version'],
             'installed': True, 'enabled': mode != 'disabled',
             'source': {'source': 'local', 'path': str(home / 'plugins/sparekey')}}
    state.write_text(json.dumps(entry))
    print(json.dumps(entry))
elif args[1] == 'remove':
    state.unlink(missing_ok=True); print('{}')
else: sys.exit(2)
''')
    fake.chmod(0o700)

    def environment(name):
        home = base / name
        home.mkdir()
        return home, dict(os.environ, SPAREKEY_TEST_HOME=str(home),
                         SPAREKEY_TEST_RUNTIME_DIR=str(home / 'runtime'),
                         SPAREKEY_TEST_CODEX=str(fake))

    def install(env, expected=0, force=False):
        result = subprocess.run([str(binary), 'skill', 'install', '--agent', 'codex', *(['--force'] if force else [])],
                                env=env, capture_output=True, text=True, timeout=40)
        assert result.returncode == expected, (result.returncode, result.stdout, result.stderr)
        return result

    def legacy(home, content=source):
        path = home / '.agents/skills/sparekey/SKILL.md'
        path.parent.mkdir(parents=True)
        path.write_bytes(content)
        return path

    def case():
        global count
        count += 1

    home, env = environment('fresh')
    install(env)
    manifest = home / 'plugins/sparekey/.codex-plugin/plugin.json'
    assert json.loads(manifest.read_text())['interface']['logo'] == './assets/logo.png'
    assert (home / 'plugins/sparekey/assets/logo.png').read_bytes() == (repo / 'docs/assets/logo.png').read_bytes()
    assert not (home / '.agents/skills/sparekey/SKILL.md').exists()
    install(env)
    calls = [json.loads(x) for x in (home / 'calls.jsonl').read_text().splitlines()]
    assert sum(c[1] == 'add' for c in calls) == 1
    case()

    home, env = environment('migration')
    old = legacy(home)
    old.with_name('SKILL.md.bak').write_text('previous backup')
    market = home / '.agents/plugins/marketplace.json'
    market.parent.mkdir()
    other = {'name': 'other', 'source': {'source': 'local', 'path': './plugins/other'}}
    market.write_text(json.dumps({'name': 'mine', 'interface': {'displayName': 'My plugins'}, 'plugins': [other]}))
    install(env)
    assert not old.exists() and old.with_name('SKILL.md.bak').read_text() == 'previous backup'
    backups = list((home / '.sparekey-backups').glob('codex-skill-*/SKILL.md'))
    assert len(backups) == 1 and backups[0].read_bytes() == source
    catalog = json.loads(market.read_text())
    assert catalog['plugins'][0] == other and catalog['interface']['displayName'] == 'My plugins'
    assert json.loads((home / 'fake-state.json').read_text())['pluginId'] == 'sparekey@mine'
    case()

    home, env = environment('custom')
    old = legacy(home, b'user customization')
    install(env, expected=2)
    assert old.read_bytes() == b'user customization' and not (home / 'plugins').exists()
    install(env, force=True)
    assert not old.exists()
    assert next((home / '.sparekey-backups').glob('codex-skill-*/SKILL.md')).read_bytes() == b'user customization'
    case()

    for mode in ['failure', 'disabled', 'unsupported', 'malformed', 'timeout']:
        home, env = environment(mode)
        old = legacy(home)
        env['SPAREKEY_FAKE_CODEX_MODE'] = mode
        env['SPAREKEY_TEST_CODEX_TIMEOUT'] = '0.1'
        install(env, expected=1)
        assert old.read_bytes() == source
        case()

    home, env = environment('no-cli')
    old = legacy(home)
    del env['SPAREKEY_TEST_CODEX']
    assert 'Codex CLI' in install(env, expected=1).stderr
    assert old.exists() and not (home / 'plugins').exists()
    case()

    home, env = environment('symlink')
    external = base / 'outside'; external.mkdir()
    (home / 'plugins').symlink_to(external)
    install(env, expected=1)
    assert list(external.iterdir()) == []
    case()

    home, env = environment('market-conflict')
    market = home / '.agents/plugins/marketplace.json'; market.parent.mkdir(parents=True)
    before = json.dumps({'name': 'personal', 'plugins': [{'name': 'sparekey', 'source': {'source': 'local', 'path': './other'}}]})
    market.write_text(before)
    install(env, expected=1)
    assert market.read_text() == before and not (home / 'plugins').exists()
    case()

    home, env = environment('modified-plugin')
    install(env)
    skill = home / 'plugins/sparekey/skills/sparekey/SKILL.md'
    skill.write_text('custom plugin')
    install(env, expected=2)
    assert skill.read_text() == 'custom plugin'
    install(env, force=True)
    assert skill.read_bytes() == source
    assert next((home / '.sparekey-backups').glob('codex-plugin-*/skills/sparekey/SKILL.md')).read_text() == 'custom plugin'
    case()

    home, env = environment('file-symlink')
    install(env)
    skill = home / 'plugins/sparekey/skills/sparekey/SKILL.md'
    outside = base / 'outside-skill'; outside.write_text('untouched')
    skill.unlink(); skill.symlink_to(outside)
    install(env, expected=1, force=True)
    assert outside.read_text() == 'untouched'
    case()

    home, env = environment('market-symlink')
    market = home / '.agents/plugins/marketplace.json'; market.parent.mkdir(parents=True)
    outside = base / 'outside-market'; outside.write_text('{"name":"personal","plugins":[]}')
    market.symlink_to(outside)
    install(env, expected=1, force=True)
    assert outside.read_text() == '{"name":"personal","plugins":[]}'
    case()

    home, env = environment('retry-failure')
    old = legacy(home)
    env['SPAREKEY_FAKE_CODEX_MODE'] = 'failure'
    install(env, expected=1)
    del env['SPAREKEY_FAKE_CODEX_MODE']
    install(env)
    assert not old.exists()
    case()

    if args.real_codex:
        real = shutil.which('codex')
        assert real, 'Codex CLI required for --real-codex'
        home, env = environment('real')
        (home / '.codex').mkdir()
        env['SPAREKEY_TEST_CODEX'] = real
        old = legacy(home)
        install(env)
        assert not old.exists()
        version = json.loads((home / 'plugins/sparekey/.codex-plugin/plugin.json').read_text())['version']
        cache = home / '.codex/plugins/cache/personal/sparekey' / version
        assert (cache / 'skills/sparekey/SKILL.md').read_bytes() == source
        assert (cache / 'assets/logo.png').read_bytes() == (repo / 'docs/assets/logo.png').read_bytes()
        install(env)
        real_env = dict(env, HOME=str(home), CODEX_HOME=str(home / '.codex'))
        listing = json.loads(subprocess.check_output([real, 'plugin', 'list', '--json', '--marketplace', 'personal'], env=real_env, text=True))
        assert len(listing['installed']) == 1 and listing['installed'][0]['enabled']
        subprocess.run([real, 'plugin', 'remove', 'sparekey@personal', '--json'], env=real_env, capture_output=True, check=True, timeout=30)
        case()
print(f'{count} isolated Codex plugin installer scenarios passed.')
