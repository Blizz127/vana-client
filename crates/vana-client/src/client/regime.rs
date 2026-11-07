//! The training regime's panel (an Extra, not retail; the user's wish, 2026-10-28; MODLOG "Training regime window"):
//! the edge window the bundled Training Regime mod fills (ui.window with panel = "regime"), docked with the Timers and
//! sliding in and out. The mod tracks the regime; this keeps the drawer, its slide and place, and draws the classic one.

use super::World;
use super::game_ui::GameUi;
use super::timers::{Dock, Place};
use std::time::Instant;

/// A row as the panel shows it: the label, the count at the right, how full (none: unknown), and done.
#[derive(Clone, Debug, Default, PartialEq)]
pub struct Row {
    pub label: String,
    pub text: String,
    pub f: Option<f32>,
    pub done: bool,
}

/// The window's heading and rows.
#[derive(Clone, Debug, Default, PartialEq)]
pub struct View {
    pub heading: String,
    pub rows: Vec<Row>,
}

impl View {
    /// The mod's window as the panel draws it: its heading and its row gauges.
    pub fn of(win: &super::lua::window::Window) -> View {
        let rows = win
            .elems
            .iter()
            .filter_map(|e| match e {
                super::lua::window::Elem::Gauge { label, value, text, row: true, dim, .. } => Some(Row {
                    label: label.clone(),
                    text: text.clone(),
                    f: (*value > 0.0).then_some(*value),
                    done: *dim,
                }),
                _ => None,
            })
            .collect();
        View { heading: win.heading.clone(), rows }
    }
}

pub struct Tracker {
    /// The drawer is out; `slide` runs 0 (in) .. 1 (out); `dirty` when it changed (the app keeps it in the config).
    pub out: bool,
    slide: f32,
    pub dirty: bool,
    last: Option<Instant>,
    frame: Option<(View, Place)>,
    rect: Option<[f32; 4]>,
    drawer: Option<[f32; 4]>,
}

impl Tracker {
    /// Last frame's window (the skillchain window stacks on it).
    pub fn rect(&self) -> Option<[f32; 4]> {
        self.rect
    }

    pub fn new(out: bool) -> Self {
        Self { out, slide: out as u8 as f32, dirty: false, last: None, frame: None, rect: None, drawer: None }
    }

    pub fn toggle(&mut self) {
        self.out = !self.out;
        self.dirty = true;
    }
}

/// The window's width, inner margin and pitches (as the Timers').
const WIDTH: f32 = super::timers::WIDTH;
const PAD: f32 = 8.0;
const HEAD_H: f32 = 16.0;
const ROW_H: f32 = 24.0;
const SLIVER: f32 = 22.0;
const SLIDE_TICKS: f32 = 12.0;
const TOP_EDGE: f32 = 48.0;
const N: u32 = 0x8080_8080;
/// A full slot (the Records of Eminence list's done colour *(ours)*).
const DONE_TINT: u32 = 0x8040_4040;

fn ease(s: f32) -> f32 {
    s * s * (3.0 - 2.0 * s)
}

/// Where it goes: the Timers' dock, under the Timers window when that is up (above it on the right).
fn place_by(base: Place, timers: Option<[f32; 4]>) -> Place {
    match (base.dock, timers) {
        (Dock::Right, Some(r)) => {
            let y = r[1] - 4.0;
            Place { y, max_h: (base.max_h - (base.y - y)).max(0.0), ..base }
        }
        (_, Some(r)) => {
            let y = r[1] + r[3] + 4.0;
            Place { y, max_h: (base.max_h - (y - base.y)).max(0.0), ..base }
        }
        (_, None) => base,
    }
}

/// Draws the window at `p` with the drawer at `slide`; its rect and the drawer's.
pub fn draw_panel(gu: &mut GameUi, r: &View, p: &Place, slide: f32, sw: f32) -> Option<([f32; 4], [f32; 4])> {
    let rows = ((p.max_h - 2.0 * PAD - HEAD_H) / ROW_H).floor().max(0.0) as usize;
    let rows = rows.min(r.rows.len());
    if rows == 0 {
        return None;
    }
    let h = 2.0 * PAD + HEAD_H + ROW_H * rows as f32;
    let (mut x, mut y) = (p.x, if p.dock == Dock::Right { p.y - h } else { p.y });
    let e = 1.0 - ease(slide.clamp(0.0, 1.0));
    match p.dock {
        Dock::Left => x -= (x + WIDTH - SLIVER) * e,
        Dock::Right => x += (sw - SLIVER - x) * e,
        Dock::Top => y -= (y + h - (TOP_EDGE + SLIVER)) * e,
    }
    if p.dock == Dock::Top {
        gu.clip(Some([0.0, TOP_EDGE, sw, 1.0e5]));
    }
    gu.frame(x, y, WIDTH, h);
    let inward = slide < 0.5;
    match p.dock {
        Dock::Left => gu.sprite("menu    frames", if inward { 26 } else { 25 }, x + WIDTH - 20.0, y + 6.0, N),
        Dock::Right => gu.sprite("menu    frames", if inward { 25 } else { 26 }, x + 4.0, y + 6.0, N),
        Dock::Top => {
            let (m, dx, dy, ay) = if inward {
                ([0.0, 1.0, -1.0, 0.0], 0.0, 18.0, y + h - 18.0)
            } else {
                ([0.0, -1.0, 1.0, 0.0], 9.0, 0.0, y + 4.0)
            };
            gu.sprite_affine("menu    frames", 25, x + WIDTH - 18.0 + dx, ay + dy, m, N);
            true
        }
    };
    let drawer = match p.dock {
        Dock::Left => [x + WIDTH - SLIVER, y, SLIVER, h.min(48.0)],
        Dock::Right => [x, y, SLIVER, h.min(48.0)],
        Dock::Top if inward => [x, y + h - SLIVER, WIDTH, SLIVER],
        Dock::Top => [x + WIDTH - 24.0, y, 24.0, 24.0],
    };
    let rect = if p.dock == Dock::Top && y < TOP_EDGE {
        [x, TOP_EDGE, WIDTH, (y + h - TOP_EDGE).max(0.0)]
    } else {
        [x, y, WIDTH, h]
    };
    if slide <= 0.0 {
        gu.clip(None);
        return Some((rect, drawer));
    }
    let (rx, right, inner) = (x + PAD, x + WIDTH - PAD, WIDTH - 2.0 * PAD);
    let hx = if p.dock == Dock::Right { rx + 16.0 } else { rx };
    gu.shape_fit(&r.heading, hx, y + PAD + 1.0, inner - 22.0, 0x80a0_a080);
    let mut ly = y + PAD + HEAD_H;
    for s in r.rows.iter().take(rows) {
        let (done, f) = (s.done, s.f);
        let tint = if done { DONE_TINT } else { N };
        gu.text_fit(&format!("{}:", s.label), rx, ly - 2.0, inner - 36.0, tint);
        gu.shape_text(&s.text, right, ly + 13.0, tint, true);
        let gy = ly + 14.0;
        if let Some(f) = f.filter(|f| *f > 0.0) {
            gu.sprite_coloured(
                "menu    windowps",
                97,
                rx + 4.0,
                gy + 1.0,
                f.min(1.0),
                1.0,
                if done { [0x40, 0x40, 0x40, 0xa9] } else { [0x20, 0x70, 0x80, 0xa9] },
                8,
            );
        }
        gu.sprite("menu    windowps", 38, rx, gy, if f.is_some_and(|f| f > 0.0) { N } else { 0x3050_5050 });
        ly += ROW_H;
    }
    gu.clip(None);
    Some((rect, drawer))
}

/// Each frame from the HUD after the Timers' prepare: hidden in events, under the map, and with nothing to show.
pub fn prepare(gu: &GameUi, w: &mut World, base: Place) {
    let now = Instant::now();
    let dt = w.regime.last.map_or(0.0, |l| now.duration_since(l).as_secs_f32());
    w.regime.last = Some(now);
    let step = dt * 60.0 / SLIDE_TICKS;
    w.regime.slide = if w.regime.out { (w.regime.slide + step).min(1.0) } else { (w.regime.slide - step).max(0.0) };
    w.regime.frame = None;
    let _ = gu;
    if super::event::active(w) || w.map.is_some() || w.cnq.is_some() {
        return;
    }
    let Some(win) = w.lua.edge_panel("regime") else { return };
    let r = View::of(&win);
    if r.rows.is_empty() {
        return;
    }
    let timers = w.timers.rect();
    w.regime.frame = Some((r, place_by(base, timers)));
}

pub fn draw(gu: &mut GameUi, t: &mut Tracker, sw: f32) {
    (t.rect, t.drawer) = (None, None);
    let Some((r, p)) = t.frame.take() else { return };
    if let Some((rect, drawer)) = draw_panel(gu, &r, &p, t.slide, sw) {
        (t.rect, t.drawer) = (Some(rect), Some(drawer));
    }
}

/// After every window: a click on the drawer's arrow, unless a window over ours has the spot. The window's rect for
/// the world-click blockers.
pub fn pointer(
    w: &mut World,
    gu: &GameUi,
    p: Option<(f32, f32)>,
    clicked: bool,
    over: &[[f32; 4]],
) -> Option<[f32; 4]> {
    let r = w.regime.rect?;
    let Some(p) = p else { return Some(r) };
    let inside = |r: &[f32; 4]| p.0 >= r[0] && p.0 < r[0] + r[2] && p.1 >= r[1] && p.1 < r[1] + r[3];
    if !inside(&r) || over.iter().any(inside) || !w.regime.drawer.as_ref().is_some_and(inside) {
        return Some(r);
    }
    gu.hover.set(true);
    if clicked {
        w.regime.toggle();
        w.sounds.push(crate::audio::Ui::Cursor as u32);
    }
    Some(r)
}

/// topbar-shot's sample (`--window regime:DOCK[:SLIDE]`): Garlaige's page 704 half done.
pub fn shot(gu: &mut GameUi, spec: &str, sw: f32, sh: f32, mini: Option<[f32; 4]>) {
    let f: Vec<&str> = spec.split(':').collect();
    let dock = Dock::of(f.first().and_then(|d| d.parse().ok()).unwrap_or(0));
    let slide = f.get(1).and_then(|d| d.parse().ok()).unwrap_or(1.0);
    let row = |label: &str, k: u8, n: u8| Row {
        label: label.into(),
        text: format!("{k}/{n}"),
        f: Some(k as f32 / n as f32),
        done: k >= n,
    };
    let r = View { heading: "Garlaige Citadel".into(), rows: vec![row("Siege Bat", 3, 4), row("Borer Beetle", 2, 2)] };
    let log_top = sh - 16.0 - 8.0 * 16.0 - 14.0;
    let foot = sh - 16.0 - 34.0 - 46.0;
    let p = super::timers::place(dock, sw, sh, 4, log_top, foot, mini);
    draw_panel(gu, &r, &p, slide, sw);
}
