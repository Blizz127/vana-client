# The mod catalogue

`mods.json` lists the Lua mods and DAT packs the client offers in Settings: Lua mods on the **Mods** page, DAT
packs on the **DAT Packs** page, each with Install (or Update when a newer version is listed). The client reads this
file from the `master` branch whenever one of those pages opens, and keeps the last copy for when it is offline.

To list a mod, open a pull request that adds an entry. Each entry pins one version: to publish a new version, change
its `version` and `files`.

```json
{
  "format": 1,
  "mods": [
    {
      "id": "greeter",
      "name": "Greeter",
      "kind": "lua",
      "version": "1.2.0",
      "authors": ["Your Name"],
      "description": "One or two sentences: what it does.",
      "homepage": "https://github.com/you/greeter",
      "files": [
        {
          "url": "https://github.com/you/greeter/releases/download/v1.2.0/greeter.zip",
          "sha256": "64 hex digits",
          "size": 4096
        }
      ]
    }
  ]
}
```

| Field | Meaning |
|---|---|
| `id` | The folder it installs to in the mods folder: letters, digits, `_` and `-`. For a Lua mod it is the mod's id: its `mod.toml` must name the same id, or none. |
| `name` | Shown on the page. |
| `kind` | `lua` (a Lua mod, the default) or `pack` (a DAT pack: game files in XIPivot's layout, `ROM*/<dir>/<file>.DAT`). |
| `version` | Compared with the installed copy's: a newer one is offered as Update. For a Lua mod, keep it the same as `mod.toml`'s. |
| `authors`, `description` | Shown in the help line. |
| `homepage` | Where to read more (for people reading the list; the client does not show it). |
| `files` | The archives (zip, 7z or rar), downloaded and unpacked in order into the one folder; a later archive's files replace an earlier one's. Each needs its `url` (on github.com), its `sha256` and its `size` in bytes. |

The client refuses an archive whose SHA-256 differs from the listed one, so a file changed after it was listed is
never installed. GitHub shows each release asset's SHA-256 (`gh api repos/OWNER/REPO/releases/tags/TAG --jq
'.assets[] | [.name, .digest]'`), or run `sha256sum` on the file you uploaded.

A Lua mod's archive holds its folder (the one with `mod.toml`), at the top or one level down, as GitHub's release
zips do. Hidden files (`.git`, `.github`) are left out.
