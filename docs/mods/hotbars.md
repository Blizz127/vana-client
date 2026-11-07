# Hotbars: macro bars by job

Hotbars is a bundled mod (from Arusia's VCHotbar, PR #88): up to three bars of up to twelve slots over the chat
window. Each slot holds a macro of as many lines as you like. Its action's icon shows on the slot (the first spell,
ability, weapon skill or item a line names), with a shade and the time left while it recasts; a slot with no action
shows its label. Turn it on in Config → Extras, on its page (Hotbars), where its size and place are set too.

## Sets

Macros load by job. A **main set** (`WAR`) loads whenever that job is your main job; a **sub set** (`WAR` with sub
`NIN`) loads on top of it when you play WAR/NIN, slot by slot. Slots the main set fills have a gold edge, those the
sub set fills a blue one. Clearing a slot of a sub set the main set fills blanks it for that sub job only.

## On the bars

- **Keys:** bar 1 takes `1`..`0`, `-`, `=`; bar 2 the same with Ctrl, bar 3 with Alt. The manager's Keys page picks
  each bar's modifier and the key row (number row, function keys or the numpad). A slot shows its key in its corner.
- **Click** a slot to run it; **right-click** for Edit, Clear and the manager; **drag** a slot onto another to swap
  them (in the sub set when either comes from it).
- **Hover** a slot for its name and lines.
- The jobs over the top bar open the manager.

The game's macro palette hides while the bars show (Hide Stock Macro Bar); its Ctrl and Alt keys still run its
macros unless a bar uses them.

## Macros

Each line runs as typed. `/wait 2` on its own line waits two seconds; `<wait 2>` at the end of a line waits after it.
A macro still running ignores a second press.

The macros are kept in `mod-data/hotbar/files/macros.json`:

```json
{
  "WAR": {
    "main": { "1": { "1": { "name": "Provoke", "lines": ["/ja \"Provoke\" <t>"] } } },
    "sub": { "NIN": { "1": { "6": { "name": "Utsusemi", "lines": ["/ma \"Utsusemi: Ichi\" <me>"] } } } }
  }
}
```

## Commands

- `//hb` opens or closes the manager.
- `//hb show`, `//hb hide`: the bars for this session.
- `//hb run <bar> <slot>`: runs a slot (for a key bind).
- `//hb reload`: reads macros.json again.
- `//hb wipestock` empties the game's own macro sets after keeping a copy; `//hb restorestock` puts it back.
