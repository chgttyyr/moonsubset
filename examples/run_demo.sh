#!/usr/bin/env bash
set -e

echo "=================================================="
echo "  MoonSubset: End-to-End Demonstration Script     "
echo "=================================================="

echo "[1/2] Building MoonSubset toolchain..."
moon check
moon build

echo "[2/2] Subsetting OFL Latin Font (fixtures/test-font.ttf)..."
moon run cmd/main -- subset -f fixtures/test-font.ttf -c "Hello MoonBit 2026!" -o fixtures/demo-latin.ttf --css "DemoLatin"

echo ""
echo "[Done] Demonstration completed! Open 'examples/demo.html' in your browser to verify rendering."
