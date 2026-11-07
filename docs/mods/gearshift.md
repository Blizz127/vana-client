# Gearshift: GearSwap, LuAshitacast, Ashitacast and Spellcast files

Gearshift is a bundled mod that changes your gear around your actions from the job files you already have. It reads
**GearSwap** job files, **LuAshitacast** profiles, **Ashitacast** XML profiles (v4, and v3 / LegacyAC files) and
**Spellcast** XML files as they are; you don't rewrite them.

## Where the files go

Put them in the mod's data folder, `mod-data/gearshift/files/` in the client's data directory:

| Kind | Folder | Names it looks for, in order |
| --- | --- | --- |
| GearSwap | `gearswap/<Name>/`, `gearswap/common/`, `gearswap/` | `Name_JOB.lua`, `Name-JOB.lua`, `Name_Job.lua`, `Name-Job.lua`, `Name.lua`, `JOB.lua`, `Job.lua`, `default.lua` |
| LuAshitacast | `ashitacast/<Name>_<Id>/`, then `ashitacast/` | `JOB.lua` in the first, `Name_JOB.lua` in the second |
| Ashitacast XML | `ashitacast/<Name>_<Id>/`, `ashitacast/`, then `legacyac/` | `JOB.xml` in the first, `Name_JOB.xml` in the others |
| Spellcast | `spellcast/<Name>/`, then `spellcast/` | `MAIN_SUB.xml`, `MAIN.xml` in the first; `Name_MAIN_SUB.xml`, `Name_MAIN.xml`, `MAIN_SUB.xml`, `MAIN.xml`, then `default.xml` in the second (a `default.xml` without `AutoLoadXML="true"` is used whatever the job) |

`JOB` is the three-letter job (`WAR`), `Job` its full name (`Warrior`), `Name` your character's name and `Id` its
server id. Case doesn't matter. When there is a GearSwap file for the job it is used; otherwise a LuAshitacast
profile; otherwise an Ashitacast XML profile; otherwise a Spellcast file. The file loads when you log in and again
when your main job changes (a Spellcast file when your sub job changes too).
Files a GearSwap file `include`s are looked for in the same GearSwap folders.

## What it does

- **GearSwap files:** `get_sets` at load; `pretarget`, `precast` and `midcast` around each action a command line
  starts (typed, a macro, a key bind, or a menu's line); `aftercast` when the action ends or is interrupted;
  `status_change`, `buff_change`, `sub_job_change` and `self_command`. `equip`, `set_combine`, `sets`, `empty`,
  `player`, `world`, `buffactive`, `pet`, `party`, `cancel_spell`, `change_target`, `disable` / `enable`,
  `midaction`, `send_command` (`input`, `wait`, `gs`, `bind` / `unbind`), `add_to_chat`, `include`, and the
  `windower.ffxi` getters most files use. Two of GearSwap's libraries are built in, used when you have no copy
  of them: `Modes.lua` (`M(...)` modes: `value`, `current`, `cycle`, `toggle`, `set`, `reset` and the rest) and
  `organizer-lib` (nothing to do here). The `texts` library draws on the HUD: boxes with `${name}` fields, `\cs(r,g,b)`
  colours, background, outline, position, size, show and hide.
- **LuAshitacast profiles:** `OnLoad` / `OnUnload`, `HandleDefault` on every send tick while no action is under way,
  `HandlePrecast` / `HandleMidcast`, `HandlePreshot` / `HandleMidshot`, `HandleAbility`, `HandleWeaponskill`,
  `HandleItem` around every action (menus too), `HandleCommand` from `/lac fwd`. `gFunc.Equip`, `EquipSet`,
  `Combine`, `ForceEquip(Set)`, `LockSet`, `CancelAction`, `ChangeActionTarget`, `Disable` / `Enable`,
  `EvaluateLevels`, `ApplyBaseSets`, `SetMidDelay` with `InterimEquip(Set)`; `gData.GetPlayer`, `GetAction`,
  `GetActionTarget`, `GetTarget`, `GetEntity`, `GetBuffCount`, `GetEnvironment`, `GetEquipment`, `GetPet`.
- **Ashitacast XML profiles:** every section (`load`, `unload`, `commands`, `default`, `precast` / `midcast`,
  `preranged` / `midranged`, `ability`, `weaponskill`, `item`, `petskill`, `petspell`), `sets` with `baseset`,
  `<settings>`, plain and merged `<include>`s; `if` / `elseif` / `else` / `return`; basic and `advanced` rules with
  every built-in variable, `$u_` user variables, `$b_` buff counts and `$args` / `$argN`; `equip` (lock, priority,
  `ignore`, `displaced`, `remove`, `augment`, `augpath`, `augrank`, `augtrial`), `command`, `echo`, `setvar`,
  `clearvar`, `change`, `gearlock`, `registerbuff`, `clearbuff`, `cancel`, `override`. The rules evaluate as
  Ashitacast's do, odd cases included (string `!=` in a rule never matches, `*` in an advanced rule multiplies);
  what only hangs or crashes Ashitacast (a negative number, a division by zero, a set that is its own baseset) does
  what was meant, and `fastcast` / `snapshot` shorten the wait after an action as documented. A v3 file
  (`idlegear`, `premagic`, `buffactive` and so on) is read through Ashitacast's v3 import rules.
- **Spellcast files:** an action's command line (`/ma`, `/ja`, `/ws`, `/pet`, `/nin`, `/so`, `/ra` and their long
  forms; typed, a macro or a menu's line) is read against the rules once: the precast set goes on, the line goes to
  the game (as Spellcast wrote it: names in any case, numerals for roman, a missing target filled in), the midcast
  set 0.6 s later and the aftercast set at the spell's base cast time + 1.5 s (another 1.5 s for abilities and weapon
  skills), with `castdelay`, `geardelay`, `midcastdelay` and `aftercastdelay` as written. A status change reads the
  rules as `autoset` for the idle, engaged or resting set. Groups (`default`, `inherit`, names with `|` and `*`), sets
  with `BaseSet` / `BaseGroup` and slot locks; `if` / `elseif` / `else` / `rule`, every condition and its `Not` form,
  `mode="OR"`, wildcards, `(regex)` patterns and `Advanced` with casts, `regex()`, `strmatch()`, `isArea()` and
  `buffactive()`; `%` and `$` variables (also in the lines you type); every action in both spellings (`<action
  type="equip">` and `<equip>`, `<cmd>` too); trigger spells (`/ma Trigger1`, `Update`, `CycleIdleMode` ...) never
  reach the game; XInclude includes; `FishingSet`, `HELMSet`, `ShowGearSwaps`, the `Disable*` options.

Around an action the gear goes out as each add-on sends it: the precast gear, the action, the midcast gear, in that
order in one batch.

## Commands

- `//gs c <text>`, `//gs equip <set>`, `//gs reload`, `//gs load <file>`, `//gs enable|disable [slot|all]`,
  `//gs showswaps`, `//gs debugmode`.
- `/lac fwd <args>`, `/lac load [file]`, `/lac reload`, `/lac unload`, `/lac set <set> [seconds]`,
  `/lac enable|disable [slot|all]`, `/lac equip <slot> <item> ...`, `/lac naked`, `/lac list`, `/lac debug`.
- `/ac load [file]`, `/ac reload`, `/ac unload`, `/ac set <set> [ms]`, `/ac enable|disable [slot]`, `/ac naked`,
  `/ac setvar <name> <value>`, `/ac clearvar <name>`, `/ac clearvars`, `/ac eval <text>`, `/ac print vars|uvars`,
  `/ac debug`. A profile's `<commands>` take the lines they match first.
- `/sc` (while a Spellcast file is loaded; otherwise the game's) or `//spellcast`: `file`, `reload`, `info`,
  `group`, `set`, `naked`, `disable`, `enable`, `debug`, `var set|rem|inc|dec|list|clear`.
- `//gearshift` says which file is loaded; `//gearshift reload` loads it again.

## Not there yet

- GearSwap: `filtered_action`, `cast_delay`, `move_spell_target`, pet hooks, `pet_change`, `buff_refresh`,
  `party_buff_change`, `indi_change`; `export` and `validate`; `windower.text` draws nothing (the `texts` library
  does), and a `texts` box can't be dragged. Mote's other libraries (`Mote-Include` and its family) are not shipped
  (they carry no licence): put copies of them beside your files.
- LuAshitacast: `ChangeActionId`, `LockStyle`, `AddSet`, `CompareItem`, pet actions; augments are compared loosely
  (as GearSwap compares them), not with LuAshitacast's wording; only the parts of `AshitaCore` most profiles use
  (chat commands, the player's jobs and levels).
- Ashitacast XML: `/ac addset`, `newxml`, `import` (v3 files are read directly instead), `gear`, `validate`, the
  packer commands; slots the server marks encumbered are not skipped; augments are compared loosely, as above.
- Spellcast: quick aliases (`//cure3`), partial player names as targets, `exportgear`, the debug log file; the
  timers are Spellcast's (no fast cast, no early finish), as it had them.
