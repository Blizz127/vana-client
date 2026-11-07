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
- **Training Regime** (assets/mods/regime): the first edge window. `ui.window` takes `edge`, `heading`, `resize` and
  `panel = "regime"` (its place, fold, /uimodes and hiding; in the classic UI the Timers' dock); gauges take
  `style = "row"` and `dim`. The modern body is the mod window's (modwin::body, shared with the panels); the classic
  one draws the row gauges as the regime window drew its rows. The tracking moved to Lua (packets.on_in / on_out, the
  new `zone_text` event, `res.zone_text` / `zone_text_find`; the Rust tests run against it); the kept state carries
  over into storage. The modern layer keeps the panel's egui layer shown (empty) until the mod's window is in it, so it
  stacks under the HUD panels as the built-in did (a layer first shown later goes on top). Compared with master in
  both UIs (the same kept regime); seen live at a Field Manual: accept, Review, cancel.
- **Timers** (assets/mods/timers): three edge windows (panels timers_recasts, timers_buffs, timers_debuffs; the user:
  so /uimodes controls each), each with a `timers` element for its section. The tracking and LSB's durations stay the
  client's engine (timers.rs, durations.rs); the element's `builtin` (the mod's setting) adds its rows, the mods'
  timers.add rows show either way. The modern UI: a window per section, its heading with the count folds it, the
  drawer (/timers, T) folds all three, the recasts' window in the old window's saved place and the others under it,
  mode presets that named "timers" name the three. The classic UI keeps the one window with three sections:
  compared with master, the same.
- **Skillchain Helper** (assets/mods/skillchain): the edge window panel `skillchains`, drawing the client's view
  (skillchain.rs, its party skills, resonances and LSB's properties stay the client's) whatever the window's elements;
  in the classic UI under the Timers and the regime as before. Not seen live: with a trust in the party (Kupipi, Nanaa
  Mihgo) neither master nor the mod shows it (it needs party members' known weapon skills).
- **Minimap** (assets/mods/minimap): the edge window panel `minimap`, in which the client draws its minimap (the map,
  the radar's dots, the wheel's zoom) and, in the modern UI, Wide Scan under it; Minimap Position and Size stay the
  client's rows for the classic place. Its layer is made when its map first draws, Wide Scan's held from the first
  frame, as the built-in ones were (the map over Wide Scan's tab). Compared with master in both UIs.

Every row of the Extras tabs is now a bundled mod's setting or a client setting for a native panel's place (Map
Overlay Opacity, Minimap Position and Size, Timers Position).

The battle menu's suggestions had no Extras row (the modern battle menu always showed them). Now the bundled
**Battle Suggestions** mod (assets/mods/suggestions, on by default) shows them: the rules stay the client's
(suggest.rs) and run only while a mod listens for the `suggestions` event, which carries their rows; the mod puts
them in the `battle_rows` slot, rows above the battle menu's commands that any mod may fill (the family submenus, the
hold while the cursor is on them and the pick through Magic or Abilities into the target prompt are the menu's).
Seen live: Berserk suggested while engaged, gone with the setting off, back with it on.

### Edge windows

`ui.window` gains `edge = true`: the window is drawn as the built-in edge windows are (modern: `edge_window` with
its flyout label = `title`, a header line = `heading`, fold, sides, drags, `resize`; classic: the Timers' dock with
the frame, the drawer arrow and the slide, stacked as Timers / Regime are). `panel = "regime"` (also timers,
minimap, skillchain) makes it stand in for that built-in panel: its saved place and fold, `ui.native.hide` and
`/uimodes`. Elements keep their kinds; a gauge's `row` style is the regime's row (label, count at the right, a thin
bar, dim when done). Specialised bodies (the timers' rows, the map, the skillchain view) become element kinds drawn
by the existing Rust, fed by the mod's data. First user: Training Regime (its tracking moves to Lua: event packets,
battle messages, the zone dialogue's regime block through res, state in storage.character).

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

### Ports so far

- **Gearshift** (assets/mods/gearshift, docs/mods/gearshift.md): GearSwap job files and LuAshitacast profiles,
  unchanged, from its data folder. One engine (src/core.lua: held items resolved by name, bag and augments, the
  wear check, 0x050 / 0x051 built and sent, what was sent counted as worn until the server agrees) under two front
  ends (src/gs.lua with a Windower shim, src/lac.lua with gFunc / gData / a little of AshitaCore). Our outgoing
  action packet (0x01A categories 3 / 7 / 9 / 16, 0x037) is held by a packets.on_out hook and sent again with the gear
  around it: the precast gear, the action, the midcast gear, in one batch, as both add-ons send them. GearSwap's
  hooks follow the command lines (filters.typed); LuAshitacast's every action. A Rust test runs both kinds of file
  against a fake game; seen live (Lnxcsfix, Berserk): a GearSwap file's precast, midcast and aftercast swaps, and a
  profile's HandleAbility and HandleDefault, the gear on the server as sent. What is left is in its doc.
- **Hotbars** (assets/mods/hotbar, docs/mods/hotbars.md): Arusia's VCHotbar (PR #88), taken in and finished: bars of
  multi-line macros by main job and sub job, each slot its action's icon (the first /ma, /ja, /pet, /ws or /item
  line) with its recast shade and time, its macro in a tip; click, right-click menu, drag onto another slot to swap,
  hotkeys per bar, the manager window. The bars stand over the chat window at its full height (ui.native.rect's
  `room`; the classic log too), so they stay put while it grows and folds. Seen live in both UIs.
- **XP Tracker** (assets/mods/xp-tracker; PointWatch, Ashita's points, Attainment and the like): experience, merits
  and limit points, job points and capacity points as rows of an edge window, each with what came in per hour
  (`//xp reset` starts again). Gains are read from game.stats and game.job_points once a second, a level, merit or
  job point taken in counting what rolled over. Seen live (two `!givexp` gains: 33.8k/h over a minute).
- **Cutscene Speed** (assets/mods/cutscene-speed; FastCS and its kin): events play 1 to 4 times faster through the
  client's `cutscene_speed` switch, back to the game's speed when off. Seen live: the switch at 3.0, then 1.0.
- **Loot Rules** (assets/mods/loot-rules; Treasury, Lootwhore, lottery and kin): the character's Lot, Pass and Drop
  lists (names, `*` patterns or ids; a window from `//loot`, or `//loot lot add <item>`...). Pool items on the Lot
  list are lotted, on the Pass list (or all others, with Pass Everything Else) passed; Drop list items are dropped as
  they reach the inventory; Stack Loot sorts the inventory after loot. Seen live in a party with a bot: a rabbit hide
  passed by a `*Hide` rule, hare meat dropped by the Drop list; a lot not seen (no lot-listed drop came).
- **Client Tweaks** (assets/mods/client-tweaks; DelayMeNot, instantah, instantchat, macrofix, quicksets, paranormal,
  TrueFont and kin): one setting per client switch: Instant Macro Palette, Instant Auction Results, No Equip Set Wait,
  Instant Log Lines, Commands While K.O., TrueType Text, Animation Speed. Seen live: Instant Log Lines and Animation
  Speed 2 reaching their switches. Not in it yet: instaLS's linkshell chat right after zoning, `//config`-style
  game settings by command.
- **Equipment Grid** (assets/mods/equipment-grid; equipviewer, equipmon, EquipViewer): the worn gear as the equipment
  menu's 4 x 4 grid of item icons (a canvas in an edge window) with the ammunition's count. Seen live: a sword, a cap
  and pebbles in their cells.

Mod edge windows without a built-in panel that were never moved start on the left edge under the Timers' and the
regime's windows and under the mods' drawn before them, so two never open on one place.
