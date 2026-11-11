#!/usr/bin/env bash
set -e

echo "========================================================"
echo "Building Hermes Agent (Ultra-Lean Native Nim Edition)"
echo "Target: bin/hermes (Memory Limit: < 50MB RAM)"
echo "========================================================"

mkdir -p bin

nim c -d:release -d:ssl --mm:orc --opt:speed -o:bin/hermes src/main.nim

echo ""
echo "[SUCCESS] Compiled to bin/hermes"
echo "Run with: ./bin/hermes"
