//! Ours (not retail): the one-button rotation, as the other Forever games have it (Benilla's Single-Button Assistant).
//! Each press does one thing: the first of the battle menu's suggestions (client/suggest.rs, one rule set for both)
//! it has not set aside, else it engages the monster targeted. The suggestions only name what the server says we
//! have and can use now: learned spells (0x0AA) and known abilities and weapon skills (0x0AC), at our level and jobs
//! (the DAT's job / level rule), with the MP, TP and recasts for them, and not silenced, amnesic or asleep. The era's
//! closed spells are left out (client/era.rs `spell_closed`). The press goes out as the line a macro would send
//! (`/ma "Dia" <t>`), so the server checks it as any other.
//!
//! Pressed by `/rotation` (alias `/rot`, a macro line too) and the pad (client/gamepad.rs: D-pad Down walking about,
//! R3 with the battle menu up). A press is dropped while we cast, while the last action is unanswered, within `GAP`
//! of the last one sent and for `LOCK` after an action of ours finishes. An action the server does not start (no
//! 0x028 from us in `ANSWER`) counts as refused: three in a row set it aside for `ASIDE`, so a refused pick never
//! jams the button. A debuff is cast at most `TRIES` times on one monster (resisted, or the monster is immune).
//!
//! Autocast (on by default, config `rotation_autocast`; `/autocast on | off` flips the session): the rotation presses
//! itself every `TICK` while we are engaged, or a monster we target is fighting us, under the same rules, `SETTLE`
//! after it may. It never engages (a press does that) and never acts outside a fight, so nothing fires in town. It
//! pauses while dead, resting, mounted, fishing, in an event, while moving and `PAUSE` after, and `PAUSE` after any
//! line we run ourselves (a macro, a menu pick, a typed command).

use super::World;
use super::suggest::{self, Action, Suggestion};
use std::collections::HashMap;
use std::time::{Duration, Instant};

/// Presses closer than this to the last action sent are dropped.
const GAP: Duration = Duration::from_millis(1000);
/// After an action of ours finishes, the server's own pause before the next.
const LOCK: Duration = Duration::from_millis(1500);
/// How long the server has to start an action before it counts as refused.
const ANSWER: Duration = Duration::from_millis(3000);
/// Refusals in a row that set an action aside, and for how long.
const REFUSALS: u8 = 3;
const ASIDE: Duration = Duration::from_secs(30);
/// Casts of one debuff on one monster.
const TRIES: u8 = 3;
/// "Nothing to do" at most this often.
const IDLE_LINE: Duration = Duration::from_secs(5);
/// Autocast: how often it looks, how long after it may act it does, and its pause after our own input or moving.
const TICK: Duration = Duration::from_millis(500);
const SETTLE: Duration = Duration::from_millis(300);
const PAUSE: Duration = Duration::from_secs(1);

/// What a press does.
#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash)]
pub enum Step {
    Act(Action),
    /// `/attack <t>`: engage the monster targeted.
    Attack,
}

/// Who an action goes to.
#[derive(Clone, Debug, PartialEq, Eq)]
pub enum On {
    Me,
    Enemy,
    Named(String),
}

/// An action sent and not answered yet.
#[derive(Clone, Copy, Debug)]
struct Sent {
    step: Step,
    at: Instant,
    /// A debuff spell, and the monster it went to.
    debuff_on: Option<u32>,
}

#[derive(Debug, Default)]
pub struct Rotation {
    sent: Option<Sent>,
    /// When the last action went out; no press before this (after a finish of ours).
    last: Option<Instant>,
    lock: Option<Instant>,
    /// Refusals in a row per action, and when a set-aside one comes back.
    refused: HashMap<Step, (u8, Option<Instant>)>,
    /// Debuff casts the server took, per (monster, spell).
    tries: HashMap<(u32, u16), u8>,
    idle_said: Option<Instant>,
    /// Pressed this session: the hint shows from then on.
    used: bool,
    /// The hint (what the next press does, and why) and when it was worked out.
    hint: Option<String>,
    hint_at: Option<Instant>,
    /// Autocast on for this session; when it last looked, since when it may act, our own input or moving last.
    autocast: bool,
    auto_at: Option<Instant>,
    ready_since: Option<Instant>,
    manual_at: Option<Instant>,
    moved_at: Option<Instant>,
}

impl Rotation {
    pub fn new(autocast: bool) -> Rotation {
        Rotation { autocast, ..Default::default() }
    }

    /// Autocast may act now: on, not paused by our own input or moving, and `SETTLE` past the moment it could.
    fn auto_due(&mut self, now: Instant) -> bool {
        let paused = [self.manual_at, self.moved_at].iter().flatten().any(|&t| now.duration_since(t) < PAUSE);
        if !self.autocast || paused || !self.ready(now) {
            self.ready_since = None;
            return false;
        }
        now.duration_since(*self.ready_since.get_or_insert(now)) >= SETTLE
    }

    fn aside(&self, s: Step, now: Instant) -> bool {
        self.refused.get(&s).is_some_and(|(_, until)| until.is_some_and(|u| now < u))
    }

    /// The last action got no answer in time: one more refusal.
    fn settle(&mut self, now: Instant) {
        let Some(s) = self.sent else { return };
        if now.duration_since(s.at) < ANSWER {
            return;
        }
        self.sent = None;
        let e = self.refused.entry(s.step).or_insert((0, None));
        e.0 += 1;
        if e.0 >= REFUSALS {
            *e = (0, Some(now + ASIDE));
        }
    }

    /// A press may go out now: nothing unanswered, past the gap and the lock.
    fn ready(&mut self, now: Instant) -> bool {
        self.settle(now);
        self.sent.is_none() && self.last.is_none_or(|t| now.duration_since(t) >= GAP) && self.lock.is_none_or(|t| now >= t)
    }

    fn send(&mut self, step: Step, debuff_on: Option<u32>, now: Instant) {
        self.sent = Some(Sent { step, at: now, debuff_on });
        self.last = Some(now);
    }

    /// The server started or finished something of ours: the last action was taken; a finish holds the next press.
    fn answered(&mut self, finish: bool, now: Instant) {
        if let Some(s) = self.sent.take() {
            self.refused.remove(&s.step);
            if let (Some(foe), Step::Act(Action::Spell(id))) = (s.debuff_on, s.step) {
                if self.tries.len() > 64 {
                    self.tries.clear();
                }
                *self.tries.entry((foe, id)).or_default() += 1;
            }
        }
        if finish {
            self.lock = Some(now + LOCK);
        }
    }

    fn tried_out(&self, foe: u32, spell: u16) -> bool {
        self.tries.get(&(foe, spell)).is_some_and(|&n| n >= TRIES)
    }

    /// The press's pick: the first suggestion not set aside whose target resolves, else engaging.
    fn pick(&self, sugg: &[Suggestion], engage: bool, on: impl Fn(&Suggestion) -> Option<On>, now: Instant) -> Option<(Step, On)> {
        sugg.iter()
            .filter(|s| !self.aside(Step::Act(s.action), now))
            .find_map(|s| on(s).map(|o| (Step::Act(s.action), o)))
            .or_else(|| (engage && !self.aside(Step::Attack, now)).then_some((Step::Attack, On::Enemy)))
    }
}

/// The enemy: the monster targeted (`<t>`), else the party's battle target (`<bt>`), and its id.
fn enemy(w: &World) -> Option<(&'static str, u32)> {
    if let Some(t) = w.target.filter(|t| w.entities.get(t).is_some_and(|e| e.mob && e.hpp > 0)) {
        return Some(("<t>", t));
    }
    let party: Vec<u32> = w.party.members().map(|m| m.id).filter(|&id| id != 0).chain([w.my_id]).collect();
    let mut claimed: Vec<(u16, u32)> = w.entities.iter().filter(|(_, e)| e.mob && e.hpp > 0 && e.claim != 0 && party.contains(&e.claim)).map(|(id, e)| (e.index, *id)).collect();
    claimed.sort();
    claimed.first().map(|&(_, id)| ("<bt>", id))
}

/// A spell that weakens a monster (enfeebling magic, Bio): cast a few times at most on one.
fn debuff(w: &World, s: Step) -> bool {
    let Step::Act(Action::Spell(id)) = s else { return false };
    w.actions.as_ref().and_then(|a| a.spell(id)).is_some_and(|r| r.skill == 35 || (230..=232).contains(&id))
}

/// Who a suggestion goes to: the member it names; healing and enhancing magic and self-only abilities to us; the rest
/// to the enemy (None without one, or a debuff tried out on it).
fn target_of(w: &World, s: &Suggestion, foe: Option<u32>) -> Option<On> {
    if let Some(n) = &s.target {
        return Some(On::Named(n.clone()));
    }
    let acts = w.actions.as_ref()?;
    let mine = match s.action {
        Action::Spell(id) => {
            let r = acts.spell(id)?;
            matches!(r.skill, 33 | 34) || r.targets & 0x20 == 0
        }
        Action::Ability(i) => {
            let a = acts.abilities.get(i as usize)?;
            a.kind != 3 && a.targets & 0x20 == 0
        }
    };
    if mine {
        return Some(On::Me);
    }
    let foe = foe?;
    if let Action::Spell(id) = s.action
        && debuff(w, Step::Act(s.action))
        && w.rotation.tried_out(foe, id)
    {
        return None;
    }
    Some(On::Enemy)
}

/// The line a press sends.
pub fn line(w: &World, step: Step, on: &On) -> Option<String> {
    let tok = match on {
        On::Me => "<me>".to_string(),
        On::Enemy => enemy(w)?.0.to_string(),
        On::Named(n) => n.clone(),
    };
    Some(match step {
        Step::Attack => format!("/attack {tok}"),
        Step::Act(Action::Spell(id)) => format!("/ma \"{}\" {tok}", super::magic::spell_name(w, id)),
        Step::Act(Action::Ability(i)) => {
            let ws = w.actions.as_ref().and_then(|a| a.abilities.get(i as usize)).is_some_and(|a| a.kind == 3);
            format!("{} \"{}\" {tok}", if ws { "/ws" } else { "/ja" }, super::magic::ability_name(w, i))
        }
    })
}

/// Busy: casting (our cast bar, or a cast of ours the server started).
fn busy(w: &World) -> bool {
    w.cast_bar.is_some() || w.casts.contains_key(&w.my_id)
}

/// What the next press would do, worked out as `press` does.
fn next(w: &World, now: Instant, may_engage: bool) -> Option<(Step, On, String)> {
    let sugg = suggest::all(&suggest::facts(w));
    let foe = enemy(w).map(|e| e.1);
    let engage = may_engage && w.my_motion.status != 1 && w.target.and_then(|t| w.entities.get(&t)).is_some_and(|e| e.mob && e.hpp > 0);
    let (step, on) = w.rotation.pick(&sugg, engage, |s| target_of(w, s, foe), now)?;
    let why = match step {
        Step::Act(a) => sugg.iter().find(|s| s.action == a).map_or(String::new(), |s| s.reason.clone()),
        Step::Attack => "Engage the target.".to_string(),
    };
    Some((step, on, why))
}

/// The hint's text: the action's name and why.
fn hint_text(w: &World, step: Step, why: &str) -> String {
    let name = match step {
        Step::Attack => "Attack".to_string(),
        Step::Act(Action::Spell(id)) => super::magic::spell_name(w, id),
        Step::Act(Action::Ability(i)) => super::magic::ability_name(w, i),
    };
    let who = if w.rotation.autocast && in_fight(w) { "Autocast" } else { "Rotation" };
    if why.is_empty() { format!("{who}: {name}") } else { format!("{who}: {name} - {why}") }
}

/// Once the rotation has been pressed: while fighting or with a monster targeted, the hint names what the next press
/// does (worked out again every half second; drawn by `draw`).
pub fn tick(w: &mut World) {
    let now = Instant::now();
    if w.moving {
        w.rotation.moved_at = Some(now);
    }
    if w.my_motion.status == 1 {
        on_engaged(w);
    }
    if w.rotation.autocast && in_fight(w) && w.rotation.auto_at.is_none_or(|t| now.duration_since(t) >= TICK) {
        w.rotation.auto_at = Some(now);
        if w.rotation.auto_due(now) && may_act(w) {
            fire(w, now, false);
        }
    }
    if !w.rotation.used && !(w.rotation.autocast && in_fight(w)) {
        return;
    }
    let fighting = w.my_motion.status == 1 || w.target.and_then(|t| w.entities.get(&t)).is_some_and(|e| e.mob && e.hpp > 0);
    if !fighting {
        w.rotation.hint = None;
        return;
    }
    if w.rotation.hint_at.is_none_or(|t| now.duration_since(t) >= Duration::from_millis(500)) {
        let may_engage = !(w.rotation.autocast && in_fight(w));
        w.rotation.hint = next(w, now, may_engage).map(|(s, _, why)| hint_text(w, s, &why));
        w.rotation.hint_at = Some(now);
    }
}

/// In a fight, for autocast: engaged, or the monster we target is on us.
fn in_fight(w: &World) -> bool {
    w.my_motion.status == 1 || w.target.filter(|t| w.entities.get(t).is_some_and(|e| e.mob && e.hpp > 0)).is_some_and(|t| super::skillchain::hitting(w, t) == Some(w.my_id))
}

/// Not dead, casting, resting, mounted, fishing, sitting or in an event.
fn may_act(w: &World) -> bool {
    w.stats.is_some() && !matches!(w.my_motion.status, 2 | 3) && !busy(w) && super::magic::status_check(w).is_none() && !super::event::active(w)
}

/// `/autocast [on | off]`: the session's autocast (alone: flipped).
pub fn autocast_command(w: &mut World, arg: Option<&str>) {
    w.rotation.autocast = match arg.map(str::to_ascii_lowercase).as_deref() {
        Some("on") => true,
        Some("off") => false,
        _ => !w.rotation.autocast,
    };
    w.rotation.ready_since = None;
    w.chat.push(format!("Rotation autocast {}.", if w.rotation.autocast { "on: it acts by itself while you fight" } else { "off: press /rotation" }));
}

/// A line we ran ourselves (not the rotation's): autocast holds off a moment.
pub fn manual(w: &mut World) {
    w.rotation.manual_at = Some(Instant::now());
}

/// The hint, centred at the top of the screen.
pub fn draw(gu: &mut super::game_ui::GameUi, r: &Rotation, sw: f32) {
    if let Some(h) = &r.hint {
        gu.text(h, sw / 2.0, HINT_Y, 1, [0x80, 0x80, 0x80, 0x80]);
    }
}

/// The hint's line (below the cast bar, which sits at 47 or 94).
const HINT_Y: f32 = 128.0;

/// One press: one action, or a line saying why none.
pub fn press(w: &mut World) {
    let now = Instant::now();
    w.rotation.used = true;
    w.rotation.hint_at = None;
    if w.my_motion.status == 1 {
        on_engaged(w);
    }
    if busy(w) || !w.rotation.ready(now) {
        return;
    }
    if w.stats.is_none() || matches!(w.my_motion.status, 2 | 3) {
        return;
    }
    fire(w, now, true);
}

/// The action a press (`pressed`: it may engage, and says when there is nothing) or autocast sends.
fn fire(w: &mut World, now: Instant, pressed: bool) {
    let Some((step, on, _)) = next(w, now, pressed) else {
        if pressed && w.rotation.idle_said.is_none_or(|t| now.duration_since(t) >= IDLE_LINE) {
            w.rotation.idle_said = Some(now);
            w.chat.push("Rotation: nothing to do now.".to_string());
        }
        return;
    };
    let Some(text) = line(w, step, &on) else { return };
    log::info!("rotation{}: {text}", if pressed { "" } else { " (autocast)" });
    w.rotation.hint_at = None;
    let debuff_on = (on == On::Enemy && debuff(w, step)).then(|| enemy(w).map(|e| e.1)).flatten();
    w.rotation.send(step, debuff_on, now);
    super::textcmd::run(w, &text, super::textcmd::Mode::Internal);
}

/// 0x028 from us (combat.rs): an action started or finished, so the last press was taken.
pub fn on_own_action(w: &mut World, finish: bool) {
    w.rotation.answered(finish, Instant::now());
}

/// Engaging shows as our status, not as an action.
pub fn on_engaged(w: &mut World) {
    if w.rotation.sent.is_some_and(|s| s.step == Step::Attack) {
        w.rotation.answered(false, Instant::now());
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::client::suggest::{AbilityFact, Facts, Member, SpellFact, TargetFact};

    /// A Red Mage of `level` (support `sub`): the spells it would know and be able to cast at that level from the RDM
    /// 1..60 list, the way the server's 0x0AA bits and the DAT's level rule leave them, and the target it fights.
    fn rdm(level: u8, sub: (u8, u8), hp: u32, mp: u32, tp: u32) -> Facts {
        // (id, RDM level, skill, targets, MP, name); elemental magic is skill 36, enfeebling 35, healing 33, enhancing 34.
        const RDM: &[(u16, u8, u16, u16, u16, &str)] = &[
            (1, 3, 33, 0x3f, 8, "Cure"),
            (23, 1, 35, 0x20, 7, "Dia"),
            (159, 4, 36, 0x20, 4, "Stone"),
            (43, 7, 34, 0x1f, 9, "Protect"),
            (2, 14, 33, 0x3f, 24, "Cure II"),
            (58, 6, 35, 0x20, 6, "Paralyze"),
            (56, 13, 35, 0x20, 15, "Slow"),
            (48, 17, 34, 0x1f, 18, "Shell"),
            (144, 19, 36, 0x20, 7, "Fire"),
            (100, 24, 34, 0x01, 12, "Enfire"),
            (104, 16, 34, 0x01, 12, "Enthunder"),
            (3, 26, 33, 0x3f, 46, "Cure III"),
            (24, 31, 35, 0x20, 30, "Dia II"),
            (164, 29, 36, 0x20, 9, "Thunder"),
            (160, 35, 36, 0x20, 16, "Stone II"),
            (109, 41, 34, 0x1f, 40, "Refresh"),
            (57, 48, 34, 0x1f, 40, "Haste"),
            (165, 60, 36, 0x20, 37, "Thunder II"),
        ];
        let mut spells: Vec<SpellFact> = RDM.iter().filter(|r| r.1 <= level).map(|&(id, _, skill, targets, mp, name)| SpellFact { id, name: name.into(), skill, element: 0, mp, targets }).collect();
        // A Black Mage support's own spells at its level.
        if sub.0 == 4 && sub.1 >= 15 {
            spells.push(SpellFact { id: 149, name: "Blizzard".into(), skill: 36, element: 1, mp: 8, targets: 0x20 });
        }
        spells.retain(|s| s.mp as u32 <= mp);
        let mp_max = 20 + level as u32 * 6;
        let abilities = if level >= 40 { vec![AbilityFact { index: 0x200 + 40, name: "Convert".into(), ..Default::default() }] } else { Vec::new() };
        Facts {
            party: vec![Member { name: "Blizz".into(), me: true, here: true, hp, hp_max: 1000, job: 5, ..Default::default() }],
            tp,
            engaged: true,
            spells,
            abilities,
            target: Some(TargetFact { name: "Crab".into(), hpp: 90, ..Default::default() }),
            main: (5, level),
            sub,
            mp,
            mp_max,
            ..Default::default()
        }
    }

    fn first(f: &Facts) -> Option<Action> {
        suggest::all(f).first().map(|s| s.action)
    }

    #[test]
    fn level_1_only_dia_then_nothing_it_lacks() {
        let mut f = rdm(1, (0, 0), 1000, 26, 0);
        assert_eq!(first(&f), Some(Action::Spell(23)));
        // Dia on: no Stone (level 4), no Cure (3): nothing it does not have.
        f.target.as_mut().unwrap().ours = vec![134];
        assert!(suggest::all(&f).iter().all(|s| s.action != Action::Spell(159) && s.action != Action::Spell(1)));
    }

    #[test]
    fn level_12_dia_paralyze_then_stone_and_cures_when_low() {
        let mut f = rdm(12, (3, 6), 1000, 80, 0);
        f.target.as_mut().unwrap().ours = vec![134];
        // Slow comes at 13: Paralyze (6), then the filler nuke.
        assert_eq!(first(&f), Some(Action::Spell(58)));
        f.target.as_mut().unwrap().ours = vec![134, 4];
        assert_eq!(first(&f), Some(Action::Spell(159)));
        f.party[0].hp = 400;
        assert_eq!(first(&f), Some(Action::Spell(1)));
    }

    #[test]
    fn level_25_enspell_then_debuffs_in_order() {
        let mut f = rdm(25, (4, 12), 1000, 170, 0);
        // Out of MP-heavy needs: the enspell while meleeing comes before the debuffs.
        assert_eq!(first(&f), Some(Action::Spell(104)));
        f.own = vec![(94 + 4, None)];
        assert_eq!(first(&f), Some(Action::Spell(23)));
        f.target.as_mut().unwrap().ours = vec![134];
        assert_eq!(first(&f), Some(Action::Spell(56)));
        f.target.as_mut().unwrap().ours = vec![134, 13];
        assert_eq!(first(&f), Some(Action::Spell(58)));
        // Bio does not overwrite Dia: with Dia on, no Bio even if known.
        f.spells.push(SpellFact { id: 230, name: "Bio".into(), skill: 37, mp: 15, targets: 0x20, ..Default::default() });
        f.target.as_mut().unwrap().ours = vec![134, 13, 4];
        assert!(suggest::all(&f).iter().all(|s| s.action != Action::Spell(230)));
    }

    #[test]
    fn level_40_refresh_first_and_convert_when_dry() {
        let mut f = rdm(40, (3, 20), 1000, 200, 0);
        f.spells.retain(|s| s.id != 109);
        // Refresh is 41: not offered at 40.
        assert!(suggest::all(&f).iter().all(|s| s.action != Action::Spell(109)));
        // Convert at 40 with MP under a quarter and HP high.
        let mut f = rdm(40, (3, 20), 950, 30, 0);
        f.own = vec![(98, None)];
        assert_eq!(first(&f), Some(Action::Ability(0x200 + 40)));
    }

    #[test]
    fn level_60_keeps_refresh_haste_then_weapon_skill() {
        let mut f = rdm(60, (4, 30), 1000, 380, 1100);
        f.weapon_skills = vec![AbilityFact { index: 33, name: "Red Lotus Blade".into(), power: 50, ..Default::default() }];
        assert_eq!(first(&f), Some(Action::Spell(109)));
        f.own = vec![(43, None)];
        assert_eq!(first(&f), Some(Action::Spell(57)));
        f.own = vec![(43, None), (33, None), (98, None)];
        f.target.as_mut().unwrap().ours = vec![134, 13, 4];
        assert_eq!(first(&f), Some(Action::Ability(33)));
        // TP spent, MP high: Thunder II, the costliest nuke ready (the Black Mage support's Blizzard is cheaper).
        f.tp = 0;
        assert_eq!(first(&f), Some(Action::Spell(165)));
        // Half the MP gone: no nuke, nothing left to do.
        f.mp = 150;
        f.spells.retain(|s| s.mp as u32 <= 150);
        assert!(first(&f).is_none());
    }

    #[test]
    fn refusals_set_an_action_aside_then_it_comes_back() {
        let mut r = Rotation::default();
        let t0 = Instant::now();
        let dia = Suggestion { action: Action::Spell(23), target: None, reason: String::new() };
        let stone = Suggestion { action: Action::Spell(159), target: None, reason: String::new() };
        let sugg = [dia, stone];
        let on = |_: &Suggestion| Some(On::Enemy);
        // Mashed every 1.5 s with no answer: the unanswered press holds the next ones until it counts as refused.
        let mut sends = 0;
        let mut at = t0;
        while at < t0 + Duration::from_secs(12) {
            if r.ready(at) {
                let (step, _) = r.pick(&sugg, false, on, at).unwrap();
                if step == Step::Act(Action::Spell(23)) {
                    sends += 1;
                }
                r.send(step, None, at);
            }
            at += Duration::from_millis(1500);
        }
        assert_eq!(sends, 3);
        let later = t0 + Duration::from_secs(12);
        assert!(r.aside(Step::Act(Action::Spell(23)), later));
        assert_eq!(r.pick(&sugg, false, on, later).unwrap().0, Step::Act(Action::Spell(159)));
        assert_eq!(r.pick(&sugg, false, on, later + ASIDE).unwrap().0, Step::Act(Action::Spell(23)));
        // An answered action clears its count.
        let mut r = Rotation::default();
        r.send(Step::Act(Action::Spell(159)), None, t0);
        r.settle(t0 + ANSWER);
        r.send(Step::Act(Action::Spell(159)), None, t0 + ANSWER);
        r.answered(false, t0 + ANSWER);
        assert!(r.sent.is_none() && !r.refused.contains_key(&Step::Act(Action::Spell(159))));
    }

    #[test]
    fn gap_and_lock_hold_presses_after_an_answer() {
        let mut r = Rotation::default();
        let t0 = Instant::now();
        r.send(Step::Act(Action::Spell(23)), None, t0);
        // Started at once: still within the gap.
        r.answered(false, t0 + Duration::from_millis(200));
        assert!(!r.ready(t0 + Duration::from_millis(500)));
        assert!(r.ready(t0 + GAP));
        // A finish holds the next press for the lock, past the gap.
        r.answered(true, t0 + Duration::from_secs(3));
        assert!(!r.ready(t0 + Duration::from_secs(4)));
        assert!(r.ready(t0 + Duration::from_secs(3) + LOCK));
    }

    #[test]
    fn autocast_waits_to_settle_and_pauses_for_our_own_input() {
        let t0 = Instant::now();
        let mut r = Rotation::new(false);
        assert!(!r.auto_due(t0) && !r.auto_due(t0 + SETTLE));
        let mut r = Rotation::new(true);
        assert!(!r.auto_due(t0));
        assert!(r.auto_due(t0 + SETTLE));
        // Sent: nothing until it is answered and the gap is past, then the settle again.
        r.send(Step::Act(Action::Spell(23)), None, t0 + SETTLE);
        assert!(!r.auto_due(t0 + SETTLE * 2));
        r.answered(true, t0 + SETTLE * 3);
        let after = t0 + SETTLE * 3 + LOCK;
        assert!(!r.auto_due(after) && r.auto_due(after + SETTLE));
        // A line of our own, or moving: a pause.
        r.manual_at = Some(after + SETTLE);
        assert!(!r.auto_due(after + SETTLE * 2) && !r.auto_due(after + SETTLE + PAUSE / 2));
        assert!(!r.auto_due(after + SETTLE + PAUSE) && r.auto_due(after + SETTLE * 2 + PAUSE));
    }

    #[test]
    fn a_debuff_is_cast_three_times_at_most_on_one_monster() {
        let mut r = Rotation::default();
        let t0 = Instant::now();
        for k in 0..3 {
            assert!(!r.tried_out(7, 56));
            r.send(Step::Act(Action::Spell(56)), Some(7), t0 + Duration::from_secs(5 * k));
            r.answered(true, t0 + Duration::from_secs(5 * k + 1));
        }
        assert!(r.tried_out(7, 56) && !r.tried_out(8, 56));
    }

    #[test]
    fn nothing_suggested_engages_and_enemy_spells_wait_for_an_enemy() {
        let r = Rotation::default();
        let now = Instant::now();
        let dia = Suggestion { action: Action::Spell(23), target: None, reason: String::new() };
        assert_eq!(r.pick(&[], true, |_| None, now), Some((Step::Attack, On::Enemy)));
        assert_eq!(r.pick(&[dia], false, |_| None, now), None);
    }
}

#[cfg(test)]
mod data {
    use crate::dat::actions::Actions;

    /// The spell ids the rules name are the Red Mage spells they mean (the game's data, when the install is there):
    /// RDM levels (job 5) of Dia, Paralyze, Slow, Enthunder, Enfire, Phalanx, Refresh, Haste, Thunder II.
    #[test]
    fn rdm_spell_ids_in_the_game_data() {
        let Ok(index) = crate::dat::DatIndex::open(&crate::config::Config::load().ffxi_dir()) else { return };
        let Ok(a) = Actions::load(&index) else { return };
        let rdm = |id: u16| a.spell(id).map(|s| s.levels[5]);
        let got: Vec<_> = [23, 58, 56, 104, 100, 106, 109, 57, 165].iter().map(|&id| (id, rdm(id))).collect();
        eprintln!("RDM levels: {got:?}");
        for (id, lv) in got {
            assert!(lv.is_some_and(|l| (1..=60).contains(&l)), "spell {id}: RDM level {lv:?}");
        }
    }
}
