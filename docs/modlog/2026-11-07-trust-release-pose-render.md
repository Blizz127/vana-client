## Released trust keeps standing: the drawn motion (2026-11-07)

Follow-up to "Released trust keeps standing (2026-11-06)": that change only reached actmotion::status_motion, but
the drawn status motion is picked again in the render loop (choose_strafed with the actor's place status), which
still gave `cor`. Both now go through actmotion::sdep_stand.
