#!/usr/bin/env python3
"""Safe CLI smoke check: never initializes, unlocks, locks, or touches the real install."""
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile

binary = str(Path(sys.argv[1] if len(sys.argv) > 1 else '.build/debug/sparekey').resolve())
with tempfile.TemporaryDirectory(prefix='sparekey-smoke-', dir='.build') as temp:
    (Path(temp) / 'home').mkdir()
    env = dict(os.environ, SPAREKEY_TEST_RUNTIME_DIR=str(Path(temp) / 'runtime'), SPAREKEY_TEST_HOME=str(Path(temp) / 'home'))
    def run(args, expected=0):
        result = subprocess.run([binary, *args], env=env, text=True, capture_output=True, timeout=10)
        assert result.returncode == expected, (args, result.returncode, result.stdout, result.stderr)
        return result
    for args in [[], ['help'], ['--help'], ['-h'], ['help', 'setup'], ['lock', '--help']]:
        assert 'Usage:' in run(args).stdout
    assert run(['version']).stdout == 'sparekey 0.1.2\n'
    assert run(['--version']).stdout == run(['version']).stdout
    bad = json.loads(run(['unlock', '--json', '--skill', 'codex'], 2).stdout)
    assert bad['error']['code'] == 'usage'
    assert run(['setup', '--skill', 'codex', '--no-skill'], 2).returncode == 2
    assert 'Enter' not in run(['skill', 'install'], 2).stdout
    missing = json.loads(run(['status', '--json'], 1).stdout)
    assert missing['error']['code'] == 'not_set_up'
    assert not (Path(temp) / 'runtime').exists()
    skill = Path(temp) / 'home/.agents/skills/sparekey/SKILL.md'
    run(['skill', 'install', '--agent', 'codex'])
    assert skill.exists() and 'sparekey unlock --json' in skill.read_text()
    run(['skill', 'install', '--agent', 'codex'])
    skill.write_text('custom skill\n')
    run(['skill', 'install', '--agent', 'codex', '--force'])
    assert skill.with_name('SKILL.md.bak').read_text() == 'custom skill\n'
    assert 'sparekey unlock --json' in skill.read_text()
    skill.write_text('changed again\n')
    assert 'Backup already exists' in run(['skill', 'install', '--agent', 'codex', '--force'], 1).stderr
    assert skill.read_text() == 'changed again\n'
    claude = Path(temp) / 'home/.claude'
    claude.symlink_to(Path(temp) / 'home/.agents')
    assert 'symlink' in run(['skill', 'install', '--agent', 'claude'], 1).stderr
    print('Safe CLI, JSON usage errors, no-TTY skill choice, missing helper, and temp skill install checks passed.')
