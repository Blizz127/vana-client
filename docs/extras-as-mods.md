# Extras as mods (experimental branch `exp/extras-as-mods`)

The plan (user, 2026-11-06; docs/lua-mods.md decision 4): every feature that is or was on Config > Extras becomes a
bundled Lua mod, so our own features prove the API, as WoW's default UI is built from its add-on API. `/dps` is the
first, already done (assets/mods/dps). After this come the Windower and Ashita ports and a mod catalogue (the
roadmap, below).

## What each extra needs

Today's code is listed under client/ unless a path says otherwise.

| Extra | Code today | Converts with | API to add first |
| --- | --- | --- | --- |
| Text Auto-Advance | event.rs (a few lines) | `game.event`, `actions.advance` | bundled mods trusted (below) |
| Trust Speech | combat.rs (message 711) | `packets.on_in(0x02D)` or a chat filter | bundled mods trusted |
| `/find` | textcmd.rs (~25 lines) | `commands.register`, `game.items`, `res.item` | none |
| Map Overlay | map.rs (~225), modern/extras.rs | `hud.map`, binds, `hud.on` drags | drawing under the windows (it is) |
| Minimap | minimap.rs, modern/extras.rs (~150) | `hud.map`, `game.entities` | edge windows in `ui.window` |
| Skillchain Helper | skillchain.rs, dat/skillchains.rs, data | the `action` event, data as mod files | edge windows; classic docking under Timers / Regime |
| Clock | clock.rs, hudtop.rs, modern/hud.rs | `game.time`, `os.date` | slots in native panels (the location panel's line, beside the classic compass) |
| Target Distance, Target HP % | mod.rs, modern/hud.rs | `game.target` | slots in native panels (the target window's note and gauge, both UIs) |
| Timestamps on All Lines | logwin.rs, modern/chat.rs | | the log's line stamp as a switch a mod sets |
| Trust Speech, Ready Lines, Battle Text (Short), Battle Names (Coloured) | combat.rs, battlemod.rs | a battle-line filter | battle messages to filters with their actor, target, message id and values, before they are expanded into lines |
| Synthesis Amount | synth.rs (~100) | | a step in the synthesis window, or `actions.synth` with a repeat |
| Training Regime | regime.rs (696) | | event params, the options we send, and the zone dialogue's regime block |
| Timers | timers.rs (1308), durations.rs (874), data/timers | three windows: recasts, buffs, debuffs, so `/uimodes` shows and hides each (user, 2026-11-06); durations as mod data; `game.recasts().totals` | edge windows; the `timers.add` rows move to a service the Timers mod provides (`mods.provide`); party buffs (0x076) and wear-offs as events |
| Battle menu suggestions (not a row: modern UI) | suggest.rs (1034), dat/resists.rs, data | | rows in the modern battle menu, and the magic list and target prompt driven from them |

## The framework, first (done)

1. **Bundled mods are ours**: granted what their manifest asks, without the player's grant (a bundled mod is the
   client's code; the user, 2026-11-06). Their pages list no permission rows.
2. **Settings carry over**: a setting declared `from` a config field takes that field's value at its first load and
   saves it in the mod's settings file (the config keeps a field it no longer knows, so a converted extra's field
   stays readable).
3. **The Extras page shows bundled mods' settings in the old rows' places**: a setting's `tab` and `place` put it on
   one of our Extras tabs, in both UIs and the modern Settings window's topic pages (by its label); `options` with
   `values` give it the old row's choices.

Done so far (checked live, Lnxcsfix):

- **Text Auto-Advance** (assets/mods/auto-advance): `game.event().text` (waiting, open) and `actions.advance`; a
  signpost's message went on after the 3 s carried over from the config.
- **Trust Speech** (assets/mods/trust-speech): s2c 0x029 / 0x02D with message 711 blocked while Hidden, nothing hooked
  while Shown; the setting carried over (not seen live: it needs a trust's party line).
- **/find** (assets/mods/find): `/find crystal` listed the crystals by bag.
- **Map Overlay** (assets/mods/map-overlay): binds for Ctrl / Alt + O, `hud.map` with our marker (`me`, drawn as each
  UI draws it), a `hud.rect` outline (`line`) for the modern edge, `hud.on` drags to pan, the wheel through
  `input.on_mouse` to zoom at the pointer, Escape through `input.on_key` after the game's windows. Seen live: opened
  with Ctrl+O and Alt+O at the 80 % carried over, zoomed, panned, closed by Escape and by Alt+O. Compared shot for
  shot with the built-in overlay (master) in both UIs: the same box, image, edge (rounded corners), marker and name
  plates, and the minimap's marker shaded by the overlay's opacity. The Map Overlay Opacity stays a client setting
  (config `map_overlay_opacity`, its Extras row where it was): the drawing code applies it to HUD maps that give no
  alpha of their own, and the minimap's marker shades by it, as before (checked against master in the classic UI). To get
  there the modern UI draws mods' HUD elements with its own painter (modern/hudmods.rs), as its own panels draw:
  a mod's element looks as a built-in one does (user, 2026-11-06). It shows what the map window shows (user,
  2026-11-06: "no map exists" is not "you don't have it yet"): where no map exists (Mordion Gaol) the error sound and
  it stays shut; a map not ours, or not known to be yet, retail's NO MAP image (m_000_00) over the map's place with
  our marker, the map replacing it once the key item is in; a record needing no map, its image without a marker.
  `game.map` reports the record with its `kind` / `owned`. Seen live: NO MAP with our marker in Western Adoulin (the
  map not ours), beside the menu's map window showing the same. A script's `act:wheel` now passes the mods'
  mouse filters, as the window's wheel does.
- **Clock** and **Target Info** (assets/mods/clock, target-info): `ui.native.slot` fills a built-in panel's slot with
  the mod's values, drawn by the panel as its own text (the clock line beside the game's clock, the target window's
  distance and HP %); `game.clock` gives the clock line's parts; entities have `gauge`. Compared shot for shot with
  master in both UIs: the same text, font, place and colours; the settings carried over and their rows stand where
  they stood (a test pins each Extras tab's order).
- **Ready Lines**, **Battle Text** and **Battle Names** (assets/mods/battle-text, one mod: the battle log add-ons):
  `filters.battle` gives each battle message with its data (id, the action's category, actor and target, its lines)
  to the mods with game state; a mod drops it, sets its names' colour codes (the client renders the lines with them,
  and the modern chat condenses them as before) or replaces its lines (not condensed). The short forms moved to Lua
  as they were (the old Rust test runs against the mod). Compared live against master in the modern UI: the same
  lines, colour codes, modes and colours, the same look in the log. Ready Lines seen live with a trust (Kupipi): her
  cures print, her "starts casting" lines do not; ours still print.
- **Timestamps on All Lines** (assets/mods/timestamps): the client option `stamp_all_lines` (the log's stamp switch),
  set while the mod's setting is on. The classic log rewraps its lines when the switch changes (the modern chat
  stamps as it draws), so the lines that came before the mods started are stamped too. Compared with master in both
  UIs.
- **Synthesis Amount** (assets/mods/synth-amount): the count step stays the synthesis window's own (client option
  `synth_amount`: the same itemctrl under tskill1, keys and bars); its count goes to the mods (`synth_amount` event)
  and the mod makes the rest with `actions.synth` once `game.synth().busy` is false, stopping on a refusal, a
  `synth_result` that is neither made nor failed, or a zone change. Seen live in the classic UI: the count step, the
  event, the next synthesis tried at the moment the built-in tried it. On LSB today both stop after one (the server
  leaves the crystal stack locked: MODLOG "Ours, not retail: a synthesis amount"), master's built-in the same way.

## Order

1. The framework above.
2. Those that convert as they are: Text Auto-Advance, Trust Speech, `/find`, Map Overlay.
3. Edge windows in `ui.window` (both UIs), then Minimap and Skillchain Helper.
4. Slots in native panels, then Clock, Target Distance, Target HP %.
5. Battle messages to filters with their data, then Battle Text, Battle Names, Ready Lines; the log's stamp switch,
   then Timestamps.
6. Timers as three windows and the `timers.add` service.
7. The event API, then Training Regime; Synthesis Amount; the battle menu's rows, then the suggestions.

Each conversion removes the Rust it replaces, keeps the extra's look in both UIs, and is checked live.

## The roadmap after it

- Port Windower and Ashita add-ons and plugins (docs/lua-coverage.md lists them). Add-ons with players' scripts
  (GearSwap job files, AshitaCast profiles, and any others) read and run those scripts unchanged.
- Our mods on GitHub: the client lists them and offers download and install in Settings, and installs from a file:
  an archive (as many formats as we can read) or a folder with a manifest and a mod.
