#!/bin/sh
set -eu
if [ "$#" -gt 2 ] || { [ "$#" -eq 2 ] && [ "$2" != "--video" ]; }; then
    echo "Usage: $0 [OUTPUT_DIRECTORY [--video]]" >&2
    exit 2
fi
cd "$(dirname "$0")/.."
output="${1:-/tmp/sparekey-shimmer-evidence}"
mkdir -p "$output"
swiftc -o "$output/render-shimmer" Sources/sparekey/CoverLayout.swift Sources/sparekey/CoverShimmer.swift Sources/sparekey/EmbeddedLogo.swift scripts/render-shimmer/main.swift
"$output/render-shimmer" "$output" "${2:-}"
