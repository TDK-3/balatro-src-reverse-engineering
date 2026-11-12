#!/usr/bin/env bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE}")" && pwd)"
cd "$SCRIPT_DIR"

REPO="TDK-3/balatro-src-reverse-engineering"
DIST_DIR="dist"
TAG="${1:-v1.0-$(date +%Y%m%d-%H%M)}"
TITLE="Release ${TAG}"
NOTES="Multi-platform release (Windows x64, macOS Universal, Linux x86_64, and Balatro.love)."

echo "=== Publishing release ${TAG} to ${REPO} ==="
gh release create "$TAG" "${DIST_DIR}"/* \
    --repo "$REPO" \
    --title "$TITLE" \
    --notes "$NOTES"

echo "Successfully published release ${TAG}!"
