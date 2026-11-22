#!/usr/bin/env bash
# Rakhssh Multi-Branch Test Runner Shell Wrapper
set -e

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$DIR"

echo "Running multi-branch integrity tests..."
python3 run_all_tests.py "$@"
