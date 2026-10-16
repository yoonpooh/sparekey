#!/usr/bin/env python3
"""Isolated standalone skill and legacy plugin migration regression checks."""
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile

repo = Path(__file__).resolve().parents[1]
binary = repo / '.build/debug/sparekey'
source = (repo / 'skills/sparekey/SKILL.md').read_bytes()
count = 0
with tempfile.TemporaryDirectory(prefix='sparekey-migration-', dir=repo / '.build') as temp:
    base = Path(temp)
    fake = base / 'codex'
    fake.write_text('#!' + sys.executable + '\n' + r'''
import json, os, sys, time
from pathlib import Path
home = Path(os.environ['SPAREKEY_TEST_HOME'])
state = home / 'state.json'
mode = os.environ.get('MODE', '')
with (home / 'calls').open('a') as out: out.write(sys.argv[2] + '\n')
if mode == 'timeout': time.sleep(30)
if mode == 'failure': sys.exit(1)
if sys.argv[2] == 'list':
    print(json.dumps({} if mode == 'malformed' else {'installed': [json.loads(state.read_text())] if state.exists() else []}))
elif sys.argv[2] == 'remove':
    if mode != 'still-installed': state.unlink(missing_ok=True)
    if mode == 'changed-skill':
        p = home / '.agents/skills/sparekey/SKILL.md'
        p.parent.mkdir(parents=True, exist_ok=True); p.write_text('concurrent edit')
    if mode == 'concurrent':
        p = home / '.agents/plugins/marketplace.json'
        d = json.loads(p.read_text()); d['changed'] = True; p.write_text(json.dumps(d))
    print('{}')
else: sys.exit(2)
''')
    fake.chmod(0o700)

    def case(name, plugin=True, root='.codex/plugins/sparekey'):
        global count
        count += 1
        home = base / name; home.mkdir()
        env = dict(os.environ, SPAREKEY_TEST_HOME=str(home), SPAREKEY_TEST_RUNTIME_DIR=str(home / 'runtime'), SPAREKEY_TEST_CODEX=str(fake), SPAREKEY_TEST_CODEX_TIMEOUT='3')
        market = home / '.agents/plugins/marketplace.json'
        if plugin:
            market.parent.mkdir(parents=True)
            market.write_text(json.dumps({'name': 'mine', 'metadata': 'keep', 'plugins': [{'name': 'other'}, {'name': 'sparekey', 'source': {'source': 'local', 'path': './' + root}}]}))
            (home / 'state.json').write_text(json.dumps({'pluginId': 'sparekey@mine', 'installed': True, 'enabled': True, 'source': {'source': 'local', 'path': str(home / root)}}))
            package = home / root; package.mkdir(parents=True); (package / 'custom').write_text('preserved')
        return home, env, market, home / '.agents/skills/sparekey/SKILL.md'

    def install(env, expected=0, force=False):
        result = subprocess.run([str(binary), 'skill', 'install', '--agent', 'codex', *(['--force'] if force else [])], env=env, capture_output=True, text=True, timeout=10)
        assert result.returncode == expected, (result.returncode, result.stdout, result.stderr)
        return result

    home, env, market, skill = case('fresh', False)
    env.pop('SPAREKEY_TEST_CODEX')
    install(env); install(env)
    assert skill.read_bytes() == source and not market.exists() and not (home / 'calls').exists()
    report = subprocess.run([str(binary), 'doctor', '--json'], env=env, capture_output=True, text=True)
    assert json.loads(report.stdout)['statuses']['codex_skill'] == 'ok'

    for root in ['.codex/plugins/sparekey', 'plugins/sparekey']:
        home, env, market, skill = case('migration-' + root.split('/')[0], root=root)
        install(env); install(env)
        assert skill.read_bytes() == source and not (home / 'state.json').exists()
        assert json.loads(market.read_text()) == {'name': 'mine', 'metadata': 'keep', 'plugins': [{'name': 'other'}]}
        assert (home / root / 'custom').read_text() == 'preserved'
        assert (home / 'calls').read_text().splitlines() == ['list', 'remove', 'list']

    for mode in ['failure', 'malformed', 'timeout', 'still-installed', 'concurrent']:
        home, env, market, skill = case(mode); env['MODE'] = mode
        before = market.read_bytes()
        if mode == 'timeout': env['SPAREKEY_TEST_CODEX_TIMEOUT'] = '0.1'
        install(env, 1)
        assert not skill.exists()
        if mode == 'concurrent':
            assert json.loads(market.read_text())['changed']
            env.pop('MODE'); install(env); assert skill.read_bytes() == source
        else: assert market.read_bytes() == before

    home, env, market, skill = case('custom-skill')
    skill.parent.mkdir(parents=True); skill.write_text('custom')
    install(env, 2)
    assert not (home / 'calls').exists() and skill.read_text() == 'custom'
    install(env, force=True)
    assert skill.with_suffix('.md.bak').read_text() == 'custom' and skill.read_bytes() == source

    home, env, market, skill = case('existing-backup')
    skill.parent.mkdir(parents=True); skill.write_text('custom'); skill.with_suffix('.md.bak').write_text('older')
    install(env, 1, force=True)
    assert not (home / 'calls').exists() and skill.read_text() == 'custom'

    home, env, market, skill = case('wrong-source')
    d = json.loads((home / 'state.json').read_text()); d['source']['path'] = '/elsewhere'
    (home / 'state.json').write_text(json.dumps(d))
    install(env, 1); assert not skill.exists() and (home / 'calls').read_text() == 'list\n'

    home, env, market, skill = case('market-symlink')
    outside = home / 'outside'; market.rename(outside); market.symlink_to(outside)
    before = outside.read_bytes(); install(env, 1)
    assert outside.read_bytes() == before and not (home / 'calls').exists()

    home, env, market, skill = case('skill-symlink')
    skill.parent.mkdir(parents=True); skill.symlink_to(market)
    install(env, 1); assert not (home / 'calls').exists()

    home, env, market, skill = case('changed-skill'); env['MODE'] = 'changed-skill'
    install(env, 1); assert skill.read_text() == 'concurrent edit'

    home, env, market, skill = case('already-removed')
    (home / 'state.json').unlink(); install(env)
    assert skill.read_bytes() == source and (home / 'calls').read_text() == 'list\n'

print(f'{count} isolated skill/migration scenarios passed.')
