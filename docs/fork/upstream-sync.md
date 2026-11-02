# This fork and its upstream

This repository is a fork of [lenonk/vana-client](https://github.com/lenonk/vana-client) by Lenon Kitchens, released
under the MIT License. The upstream copyright and licence (`LICENSE`) are kept unchanged; changes made in this fork
are released under the same licence.

## Branches

| Branch | What it holds |
|---|---|
| `master` | An exact mirror of `upstream/master`. Never commit to it here; it only fast-forwards. |
| `develop` | This fork's work, merged regularly with `master`. |

Remotes in a working clone:

```sh
git remote add upstream https://github.com/lenonk/vana-client.git   # the original project
# origin is this fork
```

## Sync routine (weekly, and before starting a larger change)

```sh
git fetch upstream
git checkout master && git merge --ff-only upstream/master     # must fast-forward; stop if it doesn't
git checkout develop && git merge --no-ff master -m "Merge upstream vana-client $(git rev-parse --short master)"
cargo build --release && cargo test --release                  # in the build sandbox
git push origin master develop                                  # the pre-push leak check runs first
```

- Conflicts: keep upstream's behaviour unless this fork changed it on purpose; note each fork-side change in the merge
  commit message.
- Fork changes that would help upstream are kept small and self-contained so they can be offered back as pull requests.

## Publishing rules (this fork is public)

- No game data, no files from anyone's game install, no secrets, credentials, account or character names, and no
  private server addresses, hostnames or ports. Server settings live in the local config (`FFXI_CONFIG` or
  `~/.config/vana-client/config.json`), never in the tree.
- Install the pre-push hook once per clone: `tools/fork/install-hooks.sh`. It runs `tools/fork/leak-check.sh`, which
  reads its patterns from a local file outside the repository (see the script header) and refuses to push on a match.
