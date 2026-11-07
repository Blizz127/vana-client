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
- **Inventory HUD** (assets/mods/inventory-hud; invtracker, giltracker, invmon, itemwatch, Packrat and kin): gil in
  the heading, the inventory's space (every bag with Every Bag), and the items and key items added with `//bags add`
  / `//bags addkey`, an item's bar how full its stack is. Seen live: 3/30, a Wind Crystal, a key item not held.
- **Chat Alerts** (assets/mods/chat-alerts; chatmon, RAWR, chime, Audible and kin): one of the game's call sounds
  (`<call0>`..`<call21>`, interface sounds 17..38) on a tell, our name, chosen words, party or linkshell lines,
  invites, checks and emotes at us, optionally only while the window is in the background; one call a second at most.
  A Rust test drives its handlers; live it ran on real chat without errors (the test runs have no sound).
- **Player Bars** (assets/mods/player-bars; xivbar, pbar, PlayerInfo and kin): our HP, MP and TP as large HUD gauges
  (the HUD's hp / mp / tp kinds) over the middle of the screen, MP only for a job with MP; width and height settings.
  Seen live (WAR: HP and TP).
- **Effect Remover** (assets/mods/effect-remover; cancel, Cancel, Ashita's debuff): `//cancel <effects>` cancels our
  status effects by name, `*` pattern or id, several separated by commas (macros too). Seen live: `//cancel sne*`
  ended a Sneak.
- **Macro Book Switch** (assets/mods/macro-books; macrochanger, macromaster): the palette turns to the book and set
  saved (`//macros save [sub]`) for main / sub or the main job, else to a book titled with the job, when the job
  changes and once at the start (the first frame that knows the job and has the macros: the login event comes
  before mods run). Seen live: book 2 set 3 saved for WAR, the palette there at the next login.
- **Mount Picker** (assets/mods/mount-picker; MountRoulette, mountme): `//ride` calls one of our mounts at random,
  `//ride <part of a name>` the first that matches, `//ride list` names them (key items 3072 + the mount's index).
  Seen live: Chocobo and Raptor listed, the Raptor ridden. It found `game.key_items()` returning the bit table's raw
  words, not ids: fixed (Inventory HUD's key item rows read it too).
- **Log Files** (assets/mods/log-files; Logger, logs, KParser's input): the chat log, battle lines optional, to
  `logs/<character>/<date>.log` in its data folder as plain words with the time, written once a second (the lines are
  taken raw in a chat filter and made plain in the mod phase, where the auto-translate dictionary is). Seen live.
- **Tell Inbox** (assets/mods/tell-inbox; answeringmachine, respond, autorespond): while the game's `/away` flag is up
  (game.player gained `away`, `anonymous`, `seeking` from our 0x037 flags) tells are kept and each sender may get one
  Away Reply; back `/online`, they are counted and shown; `//tells` shows them again; `//r <message>` answers the last
  tell. Seen live: /away and /online followed (no tell came in from the bot); a Rust test covers keeping and replies.
- **Link Catcher** (assets/mods/link-catcher; ChatLink, links): web links in chat get a number (`[1]`); `//links`
  lists the last 30 to open in the browser or copy, `//links <n>` opens one. Seen live: the server's welcome link
  numbered and listed (not opened in the test).
- **Trust Lineups** (assets/mods/trust-lineups; Trusts, trustme): `//trusts save <lineup> [trust, ...]` keeps named
  trusts (or the party's), `//trusts <lineup>` calls those not in the party one after another, each once the last
  stands in the party and the game takes a spell again (4 s after). Seen live: Kupipi and Nanaa Mihgo called in turn;
  saving from the party not seen (names compare without spaces: the party shows "NanaaMihgo").
- **Sell and Hand In** (assets/mods/sell-hand-in; SellNPC, TradeNPC, sellit and kin): `//sell <item> [all]` sells a
  stack (or every stack) to the open shop; `//trade <item> [count], ...` hands items to the targeted NPC (8 stacks at
  most). Seen live: 12 pebbles sold to Carautia from a Hotbars slot running `//sell pebble all`; //trade not seen.
  It showed that a mod's command run by another mod on the player's input (a hotbar click) was not the player's
  input: `commands.run` now carries it (From::Mod's `input`).
- **Web Search** (assets/mods/web-search; Lookup, linker, wiki, PriceCheck and kin): `//wiki [words]` and `//ah
  [words]` open the wiki's or the auction site's search in the browser: the words, else the item, spell, ability or
  key item under a list's cursor, else the target. A Rust test checks the three sources and the encoding (the test
  runs open no browser).
- **Camera Range** (assets/mods/camera-range; XICamera, zoom, xicamera): the camera's distance, its battle distance and
  the pan speed through render.set_camera, the game's back when off or unloaded. Seen live: distance 2.
- **Chat Filter** (assets/mods/chat-filter; blist, Silence, stfu, Hush, antiemote and kin): others' chat (log modes 9
  say .. 15 emote) hidden by speaker, by word, shouts or yells, and repeated says / shouts / yells within a minute;
  the speaker read from the line's form (`Name :`, `(Name)`, `<Name>`, `[1]<Name>`, `Name>>`). A Rust test covers the
  rules; live our own lines pass as they should and no bot chat came in the minute watched. Linkshell 2 and Unity
  lines are not taken yet (their log modes still to be read).
- **Storage Search** went into **Find** (findAll, FindAll, findall, GearFinder): each character's bags are kept in the
  account's storage (every minute, on zoning and at logout) and `/find` lists the account's other characters' holdings
  after ours (`Lnxcsfix's Inventory 1`). Seen live: Lnxcsfix's Wind Crystal found while playing Lnxtest. Not yet: key
  items, and characters of other accounts (that needs files.shared).
- **Damage Meter** went into **DPS** (scoreboard, Parse, Deeps, Metrics): its Damage Meter setting shows the party's
  damage live in an edge window, a row per member with damage a second, total and share (its bar), the fight's span and
  total in the heading; `/dps` and `/dps reset` as before. Seen live: a hare fight, 62 damage at 6.9/s. Not yet:
  accuracy, the parse's details and export.
- **Target Bar** (assets/mods/target-bar; enemybar, enemybar2, HitPoints): a wide HP gauge for the target near the
  top (name, HP %, distance), with the line the game prints when it readies a move or starts a spell (the start's
  message through res.message) until it finishes or 5 s pass; dragged by its top, it keeps the place. Seen live on
  a Forest Hare; the readying line not seen yet (no move came). Not yet: the engaged enemies' bars.
- **Quick Commands** (assets/mods/quick-commands; shortcuts, Shorthand and kin): a typed `/<spell or ability>
  [target]` for anything we can use becomes the full command (any case, no spaces or marks, 2..6 for II..VI; targets
  t, me, st, bt, p0..p5 or the start of a member's name), the game's commands left alone through the new
  `commands.is_game`. Seen live: `/berserk` and `/provoke` on a hare. Not yet: one nuke / cure command by element and
  tier, upcasting and stepping down.
- **Countdowns** (assets/mods/countdowns; stopwatch, Tickle, ctimers, Ticker and kin): `//timer <time> <name>` (90,
  5m, 1h30m, 2:30) counts down as a Timers row and says when it is up; cancel and clear. The resting tick is the
  client's own (its "Next tick" over the party list). Seen live: a 20 s countdown ending with its line.
- **Party Tools** (assets/mods/party-tools; autojoin, autoinvite, invite): invites accepted from the players listed
  (`*` anyone), others optionally declined; a tell holding the Invite Word gets its sender an invite (optionally only
  listed players). Seen live: a bot's invite accepted in Southern San d'Oria; the invite word not tried. Not yet:
  AnnounceTarget's call-outs, ready checks.
- **Key Commands** (assets/mods/key-commands; Windower's binds and aliases, Binder, GBinder and kin): `//bind <key>
  <line>`, `//unbind`, `//binds`; `//alias <name> <line>` (with $1.. and $*) makes /name run the line, `//unalias`,
  `//aliases`; kept per character and bound again at login. Seen live: F9 bound to an /echo, an alias with $1 and $*.
- **Event Rules** (assets/mods/event-rules; autoex, AutoExec, onevent, logincmd): `rules.txt` in its data folder, one
  `event | match | line` a line (login, zone, job, gain, lose, hp_below, mp_below, chat, day, weather); an example file
  is written on first start; `//rules` lists, `//rules reload` reads it again. Seen live: login, Sneak gained and lost.
  Not yet: autoex's XML rule files (no XML helper yet).
- **Music Picker** (assets/mods/music-picker; BattleStations, MountMuzzle, setbgm, VanaTunes, nocombat, NoMount):
  `//music <track>` holds a track until `//music off`; Battle Music the game's, the zone's own day / night track, or
  silence; Mount Music the game's or silence. The zone's tracks come from the new `audio.music_slots()`. Seen live:
  Southern San d'Oria's slots read, track 108 held and released (the log's music lines; test runs have no sound).
- **Typing Helpers** (assets/mods/typing-helpers; translate, chars, autotrans): in typed lines `[[words]]` becomes
  the auto-translate phrase with that text and `<star>`, `<note>`, `<heart>`, `<arrow>` and others the game's symbols;
  the game's `<me>`-style tags are left alone. Seen live in an /echo. Not yet: InfoReplacer's %tokens, translating
  received Japanese.
- **Zone Banner** (assets/mods/zone-banner; zonename): the zone's name across the upper screen for about 4 s on
  arrival, faded in and out. Seen live: Northern and Southern San d'Oria.
- **Item Use Queue** (assets/mods/use-all; Pouches, nomorecrap): `//useall <item>` uses each copy in the inventory in
  turn, the next once the last use finished (or was refused); `//useall stop`. Seen live: two bolt quivers opened.
- **Hide Rules** (assets/mods/hide-rules; hideparty, minimapmon, minimapcontrol, HXIUIBegone and kin): HUD pieces
  (party, target, buffs, compass, minimap, cast, timers, regime, log, plates) hidden in the Mog House, in zones named,
  while engaged or in events, each by its own setting, through ui.native.hide. Seen live: party and minimap hidden in
  Southern San d'Oria.
- **Screen Notes** (assets/mods/screen-notes; Text): `//note <name> <text>` puts a note on the screen, dragged to its
  place and kept per character; `//note <name>` removes it, `//notes` lists them. Seen live: a note added and dragged.
- **Calculator** (assets/mods/calculator; calculator): `//calc <sum>` prints the answer (+ - * / % ^, brackets, 1.5k,
  2m, commas in the answer); `//calc` alone opens a window that answers as Enter ends the line. Parsed by hand, never
  run as Lua; a Rust test covers it. Seen live in chat and in the window. (The emote picker add-on is the game's own
  Emotes list, so it has no port.)
- **Attendance** (assets/mods/attendance; Att, Attendance, EventTracker): `//attend [note]` writes the party, the
  alliance and players within 50 yalms with the time, zone and note to `attendance/<date>.txt`. Seen live. Not yet:
  DKP bids.
- **Screen Capture** (assets/mods/screen-capture; SSOrganizer, DashCam, video capture): `//shot` saves a screenshot as
  `<character>/<zone>/<date time>.png` under the game's screenshots folder; `//record` and `//record stop` record a
  video. Seen live: a screenshot filed (then removed); recording not tried (it needs ffmpeg).
- **Quick Play** (assets/mods/quick-play; autologin, autoenterkey): a lobby mod that plays the chosen character once
  the character list shows, once per start (the password stays the login screen's Remember password). Bundled mods
  with `lobby = true` now start in the lobby too (only folder mods did). Seen live: Lnxtest played from the title.
- **Target Marker** (assets/mods/target-marker; Greed, customtarget): a ground ring under the target in a chosen
  colour and size (a band of four rings: draw lines are a pixel wide). Seen live under an NPC.
- **Cast Grid** (assets/mods/cast-grid; Nostrum's cure grid, the click-to-cast parts of the party HUDs): over the
  party list (above the chat window's full height in the modern UI), a row per party member with their name and a
  button per chosen spell; a click casts it on them (`<me>` for us), unlearned or recasting spells dimmed. The rest of
  the party HUD add-ons (HP / MP / TP, buffs) is the client's own party window. Seen live: the grid, a click casting.
- **Target Debuffs** (assets/mods/target-debuffs; Debuffed, debuff-tracker): the effects anyone put on the target as
  status icons over the target window (name and time since it landed in the tip), from the action results that name
  their effect (the messages the Timers read), gone when they wear off, are removed or the target is defeated. A Rust
  test drives it; live the bot's Dia showed it cannot see effects whose message is plain damage (Dia, Bio), which needs
  a spell -> effect table. Not seen live with an effect landing (the hares died first).
- **Skill-up Log** (assets/mods/skill-log; skilluptracker, craftmon, prism): our skill-up lines get the session's
  total for the skill (`(+0.5 this session)`, through filters.battle); `//skills` lists combat and magic skills with
  level, cap and gain. Seen live: hand-to-hand rises in two hare fights. Not yet: craft skills, the synthesis result
  shown at the start.
- **Swing Timer** (assets/mods/swing-timer; nextauto): while engaged, a small bar over the middle fills toward the
  next auto-attack, from our last melee round and the main weapon's delay (unarmed 480 added for hand-to-hand; haste
  and dual wield not counted). Seen live in a hare fight.
- **Weather Watch** (assets/mods/weather-watch; WeatherMon, weatherhelper, Meteorologist; the time and moon of
  gametime are the Clock mod's): a line and a call sound when a watched weather starts or ends in the zone (optionally
  in party chat); `//weather` says the weather, zone and day. Seen live with `!setweather` rain and clear.
- **Targeting Helpers** (assets/mods/targeting; SetTarget, TurnAround, autochecker, MobCompass's facing): `//tgt
  <name | id>` targets the nearest match, `//face` / `//face away` turn toward or away from the target, Check New
  Targets /checks each monster once. Seen live on an NPC. (`/target` is a game command, hence `//tgt`.)
- **Entity Styles** (assets/mods/entity-styles; renamer, noname, BigMode): on our screen only, `//rename <name> as
  <new>` renames a character or monster, Hide My Name hides our plate, My Size scales us (render.entity, applied twice
  a second to what is in range). Seen live: an NPC renamed, our plate hidden, our size 1.3. Not yet: tints by kind
  and the name colour table.
- **Visual Tweaks** (assets/mods/visual-tweaks; toon, shades, clearcolor, Render knobs): Brightness, Colour
  (saturation) and Cel Shading (brightness in four bands with the hue kept, outlines where the depth jumps) as one
  post pass (render.shader), Wireframe through the client's switch; the menus untouched. Seen live: the cel look in
  Southern San d'Oria. Not yet: the weather shown, Indi- bubbles hidden.
- **Window Placement** (assets/mods/window-placement; position_manager, WinControl, affinity and kin): `//winpos save`
  keeps the character's window size (and place where the system tells it; not on Wayland), restored at the next
  login; Always on Top; Priority. Seen live: the save and forget; the restore not tried (it would move the window).
- **Range Rings** (assets/mods/range-rings; DistancePlus's rings, magiccircle, songcast): ground rings around us at
  chosen radii (default 6, 10, 20 yalms), optionally around the target at the first; bands of three rings so they
  read. Seen live in Southern San d'Oria. Not yet: geomancy bubbles, avatar Favor, hitboxes.
- **Tracking Tools** (assets/mods/tracking; widescan, filterscan, watchdog): `//track <name>` tracks the nearest NPC
  or monster of that name with Wide Scan (its index from the server id), `//track stop`; `//seek <name>` counts the
  zone's matches and the nearest's distance. Seen live: Rumoie tracked (the compass arrow and her name), //seek.
  The modern compass now names what it tracks beside the grid label, as retail's names it by the dial.
- **Pet Status** (assets/mods/pet-status; PetTP, petinfo, PetMe, PetsReborn): an edge window with the pet's HP, MP and
  TP, what it fights (entity.pet_target, new: s2c 0x068's target) and the recasts of the pet commands and the job
  abilities that act through it. Seen live: Carbuncle on a SMN, the Blood Pact recasts. With it the modern party
  panel gained retail's pet and fellow rows (the classic UI had them): name, HP gauge and percent, the pet's TP.
- **Pad Bars** (assets/mods/pad-bars; XIVCrossbar, Crossbar, tCrossBar, cBind): controller crossbars: an LT side and
  an RT side of two diamonds each (the d-pad's four slots, the face buttons' four); holding a trigger, the d-pad and
  face buttons use that side's slots (the side lit, the other dimmed) and the game never sees them; LT and RT belong
  to the bars while it is on. Multi-line macros per main job with icons and recast shades (Hotbars' helpers),
  `//padbars` edits them. It needed pad input for mods: `input.on_pad` (presses and releases before the game reads the
  pad, a press taken until it comes up; input.capture) and `input.pad` (buttons, sticks, triggers), filtered inside the
  gamepad poll so a taken button never reaches the game. Seen live with the virtual Xbox pad: LT+A used Berserk (its
  recast on the slot), LT+X and RT+Y ran their lines. Not yet: double-trigger sets (LT then RT).
- **Job Gauges** (assets/mods/job-gauges; strats, maneuver, ninhelper, NinjaTool): an edge window with the charges of
  Stratagems, Ready and Quick Draw (LandSandBoat's charge table: charges left and the next one's wait from the running
  recast), Ninja shadows and tool counts, Puppetmaster maneuvers, for the main and sub jobs. A Rust test covers the
  charge math (SCH 99, 100 s left: 2 / 5, the next in 4 s); not seen live (no SCH, NIN or PUP on the test character).
- **Roll Helper** (assets/mods/roll-helper; rolltracker, RollTracker): after each Phantom Roll and Double-Up (messages
  420 / 422 / 424 / 425, 426 the bust) a line with the roll's number, lucky / unlucky and its power, from
  LandSandBoat's roll table (31 rolls; the lucky number its spike, the unlucky its dip); Guard Lucky Rolls holds back
  a Double-Up typed at a lucky number or 11. A Rust test covers it; not seen live (no Corsair on the test character).
- **Automaton Sets** (assets/mods/automaton-sets; autocontrol, pupatt, pupsets): `//automaton save <name>` keeps the
  head, frame and attachments (game.job_data), `//automaton <name>` takes the attachments off and puts the set on
  (actions.attach), then says which the server refused; list and delete. The customization window is the client's
  own. A Rust test covers the round trip; not seen live (no Puppetmaster with attachments). Not yet: the burden
  tracker.
- **Loot Tracker** (assets/mods/loot-tracker; TreasurePool, thtracker, LootScope, Lootz): an edge window with the
  target's Treasure Hunter level (its rises: an additional effect, message 603, the level as its value), the pool's
  items with their 5 minutes counting down (dim once lotted or passed), and this session's kills and drops by monster
  (`//lootlog reset`). Seen live: hare kills counted; a Rust test covers TH and the pool (no Thief or party drops in
  the test).
- **Monster Alerts** (assets/mods/monster-alerts; ohShi, skillwatch, Warn, watcher, HorizonScout's alerts): a box near
  the top of the screen with what monsters ready (0x028 category 7) or start casting (8), the move or spell named
  from the first result's value, for 8 seconds each; a call for the Watched Moves; a line and a call when a Watched
  Monster comes within 50 yalms. Seen live: the box on a hare's move and the watched-monster alert; a Rust test covers
  the lines. It uses the game's own line through `res.message` given an action result's values in the game's order
  (the action's param, the result's value, ...), now documented; its own text is the fallback.
- Not ported: Discord Status (it needs a Discord application id: the user's call); Safety Catches' call-for-help block (the game's own /blockhelp does it; the cast hold while moving is
  not done); GM Helper (gmcommand: LSB takes `!` lines as they are); Mod Profiles (plugin_manager: mod sets per character) waits for a settings API across mods; the emote
  picker is the game's Emotes list.

A mod's edge window without a built-in panel takes a place the first time it shows and keeps it, saved as if the
player had put it there: on the left edge under the built-in windows and the other mods' there if it fits above the
location panel, else on the right edge under the minimap, else the left all the same.
