#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
swiftc -o /tmp/sparekey-render-cover Sources/sparekey/CoverLayout.swift Sources/sparekey/EmbeddedLogo.swift scripts/render-cover/main.swift
/tmp/sparekey-render-cover 2560 1440 /tmp/paseo-evidence/cover-impl/cover-2560x1440.png
/tmp/sparekey-render-cover 1440 900 /tmp/paseo-evidence/cover-impl/cover-1440x900.png
