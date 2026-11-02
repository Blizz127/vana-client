#!/usr/bin/env bash
# Installs the fork's pre-push hook into this clone.
set -euo pipefail
root=$(git rev-parse --show-toplevel)
install -m755 "$root/tools/fork/pre-push" "$(git rev-parse --git-path hooks)/pre-push"
echo "pre-push hook installed"
