#!/usr/bin/env python3
"""Exercise the DEBUG SecItemImport path only in a throwaway keychain."""
from pathlib import Path
import os
import re
import shlex
import subprocess
import sys
import tempfile

binary = str(Path(sys.argv[1] if len(sys.argv) > 1 else '.build/debug/sparekey').resolve())

def command(args, *, env=None):
    result = subprocess.run(args, env=env, text=True, capture_output=True, timeout=20)
    if result.returncode:
        raise RuntimeError(f"Command failed ({result.returncode}): {args[0]}: {result.stderr.strip()}")
    return result.stdout

def keychain_state():
    return command(['security', 'list-keychains', '-d', 'user']), command(['security', 'default-keychain', '-d', 'user'])

before_list, before_default = keychain_state()
with tempfile.TemporaryDirectory(prefix='sparekey-import-test-', dir='.build') as directory:
    directory = Path(directory).resolve()
    keychain = directory / 'test.keychain-db'
    passfile = directory / 'pass'
    passfile.write_text('throwaway-p12-passphrase\n')
    os.chmod(passfile, 0o600)
    config = directory / 'cert.cnf'
    config.write_text('[req]\ndistinguished_name=dn\nprompt=no\nx509_extensions=ext\n[dn]\nCN=sparekey throwaway test\n[ext]\nbasicConstraints=critical,CA:FALSE\nkeyUsage=critical,digitalSignature\nextendedKeyUsage=codeSigning\n')
    key = directory / 'key.pem'
    cert = directory / 'cert.pem'
    p12 = directory / 'identity.p12'
    try:
        command(['/usr/bin/openssl', 'genrsa', '-out', str(key), '2048'])
        command(['/usr/bin/openssl', 'req', '-new', '-x509', '-sha256', '-days', '1', '-key', str(key), '-out', str(cert), '-config', str(config), '-extensions', 'ext'])
        command(['/usr/bin/openssl', 'pkcs12', '-export', '-inkey', str(key), '-in', str(cert), '-out', str(p12), '-passout', 'file:' + str(passfile)])
        command(['security', 'create-keychain', '-p', 'throwaway-keychain-password', str(keychain)])
        command(['security', 'unlock-keychain', '-p', 'throwaway-keychain-password', str(keychain)])
        env = dict(os.environ, SPAREKEY_TEST_P12_PATH=str(p12), SPAREKEY_TEST_PASS_PATH=str(passfile), SPAREKEY_TEST_KEYCHAIN_PATH=str(keychain))
        assert 'test-import-ok' in command([binary, 'test-import'], env=env)
        listing = command(['security', 'find-identity', '-p', 'codesigning', str(keychain)])
        fingerprint = command(['/usr/bin/openssl', 'x509', '-in', str(cert), '-noout', '-fingerprint', '-sha1']).split('=', 1)[1].replace(':', '').strip()
        assert fingerprint in listing and '"sparekey throwaway test"' in listing
        dump = command(['security', 'dump-keychain', '-a', str(keychain)])
        private_acl = dump.split('class: 0x00000010', 1)[1].split('class:', 1)[0]
        entries = re.split(r'entry \d+:', private_acl)
        assert any('sign' in entry and 'applications (0)' in entry for entry in entries)
        assert 'sparekey throwaway test' in dump
        print('ACL dump: signing entry has 0 trusted apps; imported key is sensitive and non-extractable (SecKeyCopyAttributes).')
    finally:
        subprocess.run(['security', 'delete-keychain', str(keychain)], capture_output=True, text=True, timeout=20)
        current_list, current_default = keychain_state()
        if current_list != before_list:
            original = shlex.split(before_list)
            command(['security', 'list-keychains', '-d', 'user', '-s', *original])
        if current_default != before_default:
            original_default = shlex.split(before_default)
            if original_default:
                command(['security', 'default-keychain', '-d', 'user', '-s', original_default[0]])
        after_list, after_default = keychain_state()
        assert after_list == before_list, 'User keychain search list changed.'
        assert after_default == before_default, 'User default keychain changed.'
        print('Keychain search list before/after: identical; default before/after: identical.')
