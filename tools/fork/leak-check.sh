#!/usr/bin/env bash
# Fails when text that must stay private would be published by a push to this public fork.
#
# The patterns are NOT kept in the repository (they would leak the very things they guard). They live in a local
# file, one extended regex per line, '#' comments allowed:
#   ${FORK_LEAK_PATTERNS:-$HOME/.config/forever-client/leak-patterns.txt}
#
# Usage: tools/fork/leak-check.sh [<rev-range>]     (default: upstream/master..HEAD)
# As a pre-push hook: tools/fork/install-hooks.sh
set -euo pipefail
patterns="${FORK_LEAK_PATTERNS:-$HOME/.config/forever-client/leak-patterns.txt}"
range="${1:-upstream/master..HEAD}"
if [[ ! -r "$patterns" ]]; then
  echo "leak-check: pattern file $patterns missing; refusing to continue" >&2
  exit 2
fi
regex=$(grep -v -E '^\s*(#|$)' "$patterns" | paste -sd'|')
[[ -n "$regex" ]] || { echo "leak-check: no patterns in $patterns" >&2; exit 2; }
fail=0
# Added lines in the diff, commit messages, and author/committer identities of every commit in the range.
if git diff "$range" -- . | grep -E '^\+' | grep -n -i -E "$regex"; then fail=1; fi
if git log --format='%an %ae %cn %ce%n%B' "$range" | grep -n -i -E "$regex"; then fail=1; fi
# Names of added files (game data must never be committed).
if git diff --name-only --diff-filter=A "$range" | grep -i -E '\.(dat|dll|exe|cab|msi|rar|7z)$|/ROM[0-9]*/'; then fail=1; fi
if (( fail )); then
  echo "leak-check: FAILED for $range: private text or game data above; nothing pushed" >&2
  exit 1
fi
echo "leak-check: clean ($range)"
