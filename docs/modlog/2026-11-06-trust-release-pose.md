## Released trust keeps standing (2026-11-06)

From FFXiMain.dll (Steven's unpacked copy), full_text.asm.

- FUN_100c8bb0 picks the status motion: status 2 / 3 go to 0x100c8c36. Offline (`*(DAT_104568fc + 9)` 0) it is
  `cor`; online (set to 1 at 0x10011e2d / 0x10011e5e / 0x10011f11) it is `cor` only when vtable +0x200 says so,
  else actor +0x7d8.
- FUN_1008c6c0 writes `"    "` to +0x7d8 right after running a death scheduler (0x1008cb4f, also 0x1008ca9d /
  0x1008cacc), so the status pick adds nothing and the scheduler's motions are what show: `dead` / `?ead` lay the
  body down themselves (`ded`, then `cor0`), `sdep` (a trust, +0x12c bit 22, or +0x12f bit 0) has no such motions.
- LSB releases a trust by sending it status 3 (Death) before the despawn, so ours fell into the corpse pose.
- Ours: actmotion::status_motion stands (status 0) for a `sdep` entity in status 2 / 3 *(inf: vtable +0x200 not
  identified; the blank name is taken as "keep the stand")*.
