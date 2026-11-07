# Gearshift: GearSwap and LuAshitacast files

Gearshift is a bundled mod that changes your gear around your actions from the job files you already have. It reads
**GearSwap** job files and **LuAshitacast** profiles as they are; you don't rewrite them.

## Where the files go

Put them in the mod's data folder, `mod-data/gearshift/files/` in the client's data directory:

| Kind | Folder | Names it looks for, in order |
| --- | --- | --- |
| GearSwap | `gearswap/<Name>/`, `gearswap/common/`, `gearswap/` | `Name_JOB.lua`, `Name-JOB.lua`, `Name_Job.lua`, `Name-Job.lua`, `Name.lua`, `JOB.lua`, `Job.lua`, `default.lua` |
| LuAshitacast | `ashitacast/<Name>_<Id>/`, then `ashitacast/` | `JOB.lua` in the first, `Name_JOB.lua` in the second |

`JOB` is the three-letter job (`WAR`), `Job` its full name (`Warrior`), `Name` your character's name and `Id` its
server id. Case doesn't matter. When there is a GearSwap file for the job it is used; otherwise a LuAshitacast
profile. The file loads when you log in and again when your main job changes. Files a GearSwap file `include`s are
looked for in the same GearSwap folders.

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

Around an action the gear goes out as each add-on sends it: the precast gear, the action, the midcast gear, in that
order in one batch.

## Commands

- `//gs c <text>`, `//gs equip <set>`, `//gs reload`, `//gs load <file>`, `//gs enable|disable [slot|all]`,
  `//gs showswaps`, `//gs debugmode`.
- `/lac fwd <args>`, `/lac load [file]`, `/lac reload`, `/lac unload`, `/lac set <set> [seconds]`,
  `/lac enable|disable [slot|all]`, `/lac equip <slot> <item> ...`, `/lac naked`, `/lac list`, `/lac debug`.
- `//gearshift` says which file is loaded; `//gearshift reload` loads it again.

## Not there yet

- GearSwap: `filtered_action`, `cast_delay`, `move_spell_target`, pet hooks, `pet_change`, `buff_refresh`,
  `party_buff_change`, `indi_change`; `export` and `validate`; on-screen texts from `windower.text` and the `texts`
  library draw nothing. Mote's libraries are not shipped (they carry no licence): put your own copies beside your
  files.
- LuAshitacast: `ChangeActionId`, `LockStyle`, `AddSet`, `CompareItem`, pet actions; augments are compared loosely
  (as GearSwap compares them), not with LuAshitacast's own wording; only the parts of `AshitaCore` most profiles use
  (chat commands, the player's jobs and levels).
