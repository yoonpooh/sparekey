#!/bin/bash
set -euo pipefail

root=$(cd "$(dirname "$0")" && pwd -P)
work="$root/work"
keychain="$work/spike.keychain-db"
password_file="$work/keychain-password"
certificate="$work/certificate.pem"
identity_file="$work/identity-sha1"
installed="$work/install/probe"
plist="$work/agent.plist"
log="$work/agent.log"
label=io.github.yoonpooh.sparekey.spike
domain="gui/$(id -u)"

usage() {
    echo "usage: $0 identity|build|install v1|v2|agent-run ax|kc-save|kc-read|kc-delete|whoami|cleanup" >&2
    exit 2
}

require_work() {
    [[ -d "$work" && ! -L "$work" ]] || { echo "Run identity first." >&2; exit 1; }
}

require_identity() {
    require_work
    [[ -f "$password_file" && -f "$identity_file" && -f "$keychain" ]] || {
        echo "Incomplete spike identity; inspect work/ before continuing." >&2
        exit 1
    }
}

bootout_if_loaded() {
    if /bin/launchctl print "$domain/$label" >/dev/null 2>&1; then
        /bin/launchctl bootout "$domain/$label"
    fi
}

agent_run() {
    local mode=$1 attempt
    [[ -f "$installed" && ! -L "$installed" ]] || { echo "Install v1 or v2 first." >&2; exit 1; }
    bootout_if_loaded
    : > "$log"
    : > "$log.stderr"
    /usr/bin/python3 - "$plist" "$installed" "$mode" "$log" "$label" <<'PY'
import plistlib
import sys
with open(sys.argv[1], 'wb') as stream:
    plistlib.dump({
        'Label': sys.argv[5],
        'ProgramArguments': [sys.argv[2], sys.argv[3]],
        'EnvironmentVariables': {'SPIKE_LOG': sys.argv[4]},
        'RunAtLoad': True,
        'LimitLoadToSessionType': 'Aqua',
        'ProcessType': 'Interactive',
        'StandardErrorPath': sys.argv[4] + '.stderr',
    }, stream)
PY
    /bin/launchctl bootstrap "$domain" "$plist"
    for attempt in {1..40}; do
        [[ -s "$log" ]] && break
        sleep 0.25
    done
    if [[ -s "$log" ]]; then
        cat "$log"
    else
        echo "No probe result after 10 seconds; inspect $log.stderr" >&2
        [[ ! -s "$log.stderr" ]] || cat "$log.stderr" >&2
        /bin/launchctl print "$domain/$label" 2>/dev/null | grep -E 'state =|last exit' >&2 || true
        bootout_if_loaded
        return 1
    fi
    bootout_if_loaded
    ! grep -Eq 'OSStatus -?[1-9][0-9]*|unknown mode|usage:' "$log"
}

[[ $# -ge 1 ]] || usage
case "$1" in
identity)
    [[ $# -eq 1 ]] || usage
    mkdir -p "$work"
    chmod 700 "$work"
    if [[ -e "$keychain" || -e "$password_file" || -e "$identity_file" ]]; then
        require_identity
        echo "Identity already exists in $keychain"
        exit 0
    fi
    umask 077
    /usr/bin/openssl rand -hex 32 > "$password_file"
    cat > "$work/certificate.cnf" <<'EOF'
[ req ]
distinguished_name = dn
prompt = no
x509_extensions = code_signing
[ dn ]
CN = sparekey spike local signing
[ code_signing ]
basicConstraints = critical,CA:FALSE
keyUsage = critical,digitalSignature
extendedKeyUsage = codeSigning
EOF
    /usr/bin/openssl genrsa -out "$work/private.key" 2048
    /usr/bin/openssl req -new -x509 -sha256 -days 30 \
        -key "$work/private.key" -out "$certificate" \
        -config "$work/certificate.cnf" -extensions code_signing
    /usr/bin/openssl pkcs12 -export -inkey "$work/private.key" \
        -in "$certificate" -out "$work/identity.p12" \
        -passout "file:$password_file"
    security create-keychain -p "$(cat "$password_file")" "$keychain"
    security unlock-keychain -p "$(cat "$password_file")" "$keychain"
    security import "$work/identity.p12" -k "$keychain" \
        -f pkcs12 -P "$(cat "$password_file")" -T /usr/bin/codesign
    security set-key-partition-list -S apple-tool:,apple:,codesign: \
        -s -k "$(cat "$password_file")" "$keychain"
    /usr/bin/openssl x509 -in "$certificate" -noout -fingerprint -sha1 \
        | sed 's/.*=//; s/://g' > "$identity_file"
    echo "Identity created in $keychain (login and default keychains untouched; cleanup removes it from the search list)."
    ;;
build)
    [[ $# -eq 1 ]] || usage
    require_identity
    # The dedicated keychain may have auto-locked since `identity`.
    security unlock-keychain -p "$(cat "$password_file")" "$keychain"
    mkdir -p "$work/build"
    for variant in v1 v2; do
        if [[ "$variant" == v2 ]]; then
            swiftc -D V2 "$root/probe.swift" \
                -framework ApplicationServices -framework Security \
                -o "$work/build/probe-$variant"
        else
            swiftc "$root/probe.swift" \
                -framework ApplicationServices -framework Security \
                -o "$work/build/probe-$variant"
        fi
        /usr/bin/codesign --force --sign "$(cat "$identity_file")" \
            --keychain "$keychain" --identifier "$label" "$work/build/probe-$variant"
        /usr/bin/codesign --verify --strict --verbose=2 "$work/build/probe-$variant"
        echo "$variant designated requirement:"
        /usr/bin/codesign -d -r- "$work/build/probe-$variant" 2>&1
        /usr/bin/codesign -d -r- "$work/build/probe-$variant" 2>&1 \
            | sed -n 's/^designated => //p' > "$work/build/requirement-$variant"
        [[ -s "$work/build/requirement-$variant" ]] || {
            echo "Could not extract $variant designated requirement." >&2
            exit 1
        }
    done
    if cmp -s "$work/build/requirement-v1" "$work/build/requirement-v2"; then
        echo "Designated requirements match."
    else
        echo "Designated requirements DIFFER." >&2
        exit 1
    fi
    ;;
install)
    [[ $# -eq 2 && ( "$2" == v1 || "$2" == v2 ) ]] || usage
    require_work
    [[ -f "$work/build/probe-$2" ]] || { echo "Run build first." >&2; exit 1; }
    mkdir -p "$work/install"
    # Replace via a new inode so the kernel does not reuse v1's cached signature.
    cp "$work/build/probe-$2" "$installed.tmp"
    mv -f "$installed.tmp" "$installed"
    /usr/bin/codesign --verify --strict "$installed"
    echo "Installed $2 at $installed"
    ;;
agent-run)
    [[ $# -eq 2 ]] || usage
    case "$2" in ax|kc-save|kc-read|kc-delete|whoami) ;; *) usage ;; esac
    require_work
    agent_run "$2"
    ;;
cleanup)
    [[ $# -eq 1 ]] || usage
    if [[ -d "$work" && ! -L "$work" ]]; then
        bootout_if_loaded
        if [[ -f "$installed" && ! -L "$installed" ]]; then
            agent_run kc-delete
        else
            echo "No installed probe; cannot delete a previously saved dummy item." >&2
        fi
        rm -f "$plist"
        if [[ -f "$keychain" ]]; then
            security delete-keychain "$keychain"
        fi
        /usr/bin/python3 - "$work" "$root" <<'PY'
from pathlib import Path
import shutil
import sys
work = Path(sys.argv[1])
root = Path(sys.argv[2])
if work.is_symlink() or work.resolve() != root / 'work':
    raise SystemExit('Refusing to remove an unexpected work directory')
shutil.rmtree(work)
PY
    fi
    echo "If you granted Accessibility, remove the 'probe' entry in"
    echo "System Settings > Privacy & Security > Accessibility (select it, then -)."
    ;;
*) usage ;;
esac
