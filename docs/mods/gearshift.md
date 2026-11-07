# Gearshift: GearSwap, LuAshitacast and Ashitacast files

Gearshift is a bundled mod that changes your gear around your actions from the job files you already have. It reads
**GearSwap** job files, **LuAshitacast** profiles and **Ashitacast** XML profiles (v4, and v3 files) as they are;
you don't rewrite them.

## Where the files go

Put them in the mod's data folder, `mod-data/gearshift/files/` in the client's data directory:

| Kind | Folder | Names it looks for, in order |
| --- | --- | --- |
| GearSwap | `gearswap/<Name>/`, `gearswap/common/`, `gearswap/` | `Name_JOB.lua`, `Name-JOB.lua`, `Name_Job.lua`, `Name-Job.lua`, `Name.lua`, `JOB.lua`, `Job.lua`, `default.lua` |
| LuAshitacast | `ashitacast/<Name>_<Id>/`, then `ashitacast/` | `JOB.lua` in the first, `Name_JOB.lua` in the second |
| Ashitacast XML | `ashitacast/<Name>_<Id>/`, then `ashitacast/` | `JOB.xml` in the first, `Name_JOB.xml` in the second |

`JOB` is the three-letter job (`WAR`), `Job` its full name (`Warrior`), `Name` your character's name and `Id` its
server id. Case doesn't matter. When there is a GearSwap file for the job it is used; otherwise a LuAshitacast
profile; otherwise an Ashitacast XML profile. The file loads when you log in and again when your main job changes.
Files a GearSwap file `include`s are looked for in the same GearSwap folders.

## What it does

- **GearSwap files:** `get_sets` at load; `pretarget`, `precast` and `midcast` around each action a command line
  starts (typed, a macro, a key bind, or a menu's line); `aftercast` when the action ends or is interrupted;
  `status_change`, `buff_change`, `sub_job_change` and `self_command`. `equip`, `set_combine`, `sets`, `empty`,
  `player`, `world`, `buffactive`, `pet`, `party`, `cancel_spell`, `change_target`, `disable` / `enable`,
  `midaction`, `send_command` (`input`, `wait`, `gs`, `bind` / `unbind`), `add_to_chat`, `include`, and the
  `windower.ffxi` getters most files use.
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
  (`idlegear`, `premagic`, `buffactive` and so on) is read through Ashitacast's own v3 import rules.

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
- `//gearshift` says which file is loaded; `//gearshift reload` loads it again.

## Not there yet

- GearSwap: `filtered_action`, `cast_delay`, `move_spell_target`, pet hooks, `pet_change`, `buff_refresh`,
  `party_buff_change`, `indi_change`; `export` and `validate`; on-screen texts from `windower.text` and the `texts`
  library draw nothing. Mote's libraries are not shipped (they carry no licence): put your own copies beside your
  files.
- LuAshitacast: `ChangeActionId`, `LockStyle`, `AddSet`, `CompareItem`, pet actions; augments are compared loosely
  (as GearSwap compares them), not with LuAshitacast's own wording; only the parts of `AshitaCore` most profiles use
  (chat commands, the player's jobs and levels).
- Ashitacast XML: `/ac addset`, `newxml`, `import` (v3 files are read directly instead), `gear`, `validate`, the
  packer commands; slots the server marks encumbered are not skipped; augments are compared loosely, as above.
