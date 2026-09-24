#!/usr/bin/env python3
"""Prove the DEBUG foreground continuation can read a controlling PTY."""
import fcntl
import os
from pathlib import Path
import select
import subprocess
import sys
import termios
import time

binary = str(Path(sys.argv[1] if len(sys.argv) > 1 else '.build/debug/sparekey').resolve())
master, slave = os.openpty()

def control_terminal():
    os.setsid()
    fcntl.ioctl(0, termios.TIOCSCTTY, 0)
    os.tcsetpgrp(0, os.getpgrp())

child = subprocess.Popen([binary, 'tty-probe'], stdin=slave, stdout=slave, stderr=slave,
                         preexec_fn=control_terminal, close_fds=True)
os.close(slave)
output = bytearray()
try:
    deadline = time.monotonic() + 5
    sent = False
    while time.monotonic() < deadline and child.poll() is None:
        ready, _, _ = select.select([master], [], [], 0.1)
        if ready:
            try:
                chunk = os.read(master, 4096)
            except OSError:
                break
            output.extend(chunk)
            if b'Probe input:' in output and not sent:
                os.write(master, b'probe\n')
                sent = True
    assert child.wait(timeout=2) == 0, (child.returncode, bytes(output))
    assert b'tty-ready' in output, bytes(output)
    print('Foreground posix_spawn PTY password prompt: passed.')
finally:
    if child.poll() is None:
        child.kill()
        child.wait(timeout=2)
    os.close(master)
