#!/usr/bin/env bash
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SOURCE="$DIR/tools/export-apple-emoji-search.swift"
OUTPUT="$DIR/tools/emoji-index-exporter"
ARM64="$OUTPUT-arm64"
X86_64="$OUTPUT-x86_64"

swiftc -O -target arm64-apple-macosx13.0 -o "$ARM64" "$SOURCE"
swiftc -O -target x86_64-apple-macosx13.0 -o "$X86_64" "$SOURCE"
lipo -create "$ARM64" "$X86_64" -output "$OUTPUT"
rm "$ARM64" "$X86_64"
codesign -fs - "$OUTPUT"

echo "Built $OUTPUT"
