//! Ours (not retail): Settings' graphics presets and the model of the modern Graphics & Interface window (drawn by
//! modern/options.rs): its rows as the window shows them (a toggle, segments or a slider, with the help under each),
//! its keys (the category list, the rows, the bottom buttons), Defaults, Apply, OK and Cancel. The classic pages share
//! the same rows and presets; only the keys and the drawing differ.

use super::*;

/// The graphics rows a preset sets. Everything else (Window Mode, Resolution, Monitor, GPU, Frame Limit, the Interface
/// rows ...) is left as it is.
#[derive(Clone, Copy, Debug, PartialEq)]
struct Look {
    aniso: u16,
    draw: u32,
    textures: u32,
    mip: u32,
    bump: u32,
    lamps: bool,
    env: u32,
    /// The 3D scene's size in pixels ([0, 0]: the window's).
    render: [u32; 2],
}

/// The presets' names, in the Preset row's order (then Custom).
pub const PRESETS: [&str; 3] = ["Original", "High", "Ultra"];
/// The Preset row's value while the rows match none of them.
const CUSTOM: u32 = 3;

/// What the Post-processing category says until it has rows (POST).
pub const POST_NOTE: &str = "Coming soon: anti-aliasing, bloom, tone mapping, sharpening.";

/// A graphics-defaults value: a Config tool's default.
fn tool_default(n: &str) -> u32 {
    crate::config::TOOL_DEFAULTS.iter().find(|d| d.0 == n).map_or(0, |d| d.1)
}

impl SettingsUi {
    /// Preset `k` (0 Original, 1 High, 2 Ultra) as values: Original is the client's own defaults (Config::default and
    /// the tool's), High raises the quality, Ultra adds a farther draw distance and the scene drawn at 1.5x the window
    /// and scaled down (supersampling).
    fn preset_look(&self, k: u32) -> Look {
        let c = Config::default();
        let original = Look { aniso: c.anisotropy, draw: c.draw_distance, textures: tool_default("0018"), mip: tool_default("0000"), bump: tool_default("0017"), lamps: c.lamp_lights, env: tool_default("0011"), render: [tool_default("0003"), tool_default("0004")] };
        let high = Look { aniso: 16, draw: 200, textures: 2, mip: 1, bump: 1, lamps: true, env: 2, ..original };
        match k {
            0 => original,
            1 => high,
            _ => Look { draw: 300, render: self.scaled(1.5), ..high },
        }
    }

    /// The graphics rows as they are now.
    fn look(&self) -> Look {
        Look {
            aniso: self.s.anisotropy,
            draw: self.s.draw_distance,
            textures: self.tool_get("0018"),
            mip: self.tool_get("0000"),
            bump: self.tool_get("0017"),
            lamps: self.s.lamp_lights,
            env: self.tool_get("0011"),
            render: [self.tool_get("0003"), self.tool_get("0004")],
        }
    }

    /// The Preset row's value: the preset the graphics rows match, else Custom.
    pub fn preset(&self) -> u32 {
        let now = self.look();
        (0..PRESETS.len() as u32).find(|&k| self.preset_look(k) == now).unwrap_or(CUSTOM)
    }

    /// Choosing preset `k` sets the graphics rows (Custom, not a preset, sets nothing).
    pub(super) fn apply_preset(&mut self, k: u32) {
        if k as usize >= PRESETS.len() {
            return;
        }
        let l = self.preset_look(k);
        self.s.anisotropy = l.aniso;
        self.s.draw_distance = l.draw;
        self.s.lamp_lights = l.lamps;
        for (n, v) in [("0018", l.textures), ("0000", l.mip), ("0017", l.bump), ("0011", l.env), ("0003", l.render[0]), ("0004", l.render[1])] {
            self.tool_set(n, v);
        }
    }

    /// The page's note, for a category with no rows yet.
    pub fn note(&self) -> Option<&'static str> {
        (self.kind == Kind::Settings && self.tab == POST_TAB && self.rows().is_empty()).then_some(POST_NOTE)
    }

    pub fn windowed(&self) -> bool {
        self.kind == Kind::Settings
    }

    /// The cursor's row in the category (from 1).
    pub fn view_row(&self) -> usize {
        self.row
    }

    /// The cursor to row `row` of the category, in its rows (the offscreen shot).
    pub fn goto_row(&mut self, row: usize) {
        self.goto(self.tab, row);
        self.zone = Zone::Rows;
    }

    /// The category on show (Settings: the page).
    pub fn category(&self) -> usize {
        self.tab
    }

    pub fn categories(&self) -> Vec<String> {
        self.tabs()
    }

    /// Opens on the category named `name` (case aside), the cursor on its first row; false when there is none.
    pub fn open_page(&mut self, name: &str) -> bool {
        let name = name.to_ascii_lowercase();
        let Some(k) = self.tabs().iter().position(|t| t.to_ascii_lowercase().starts_with(&name)) else { return false };
        self.goto(k, 1);
        self.m_mods = (1, 0);
        self.zone = if self.row_count() > 0 { Zone::Rows } else { Zone::Cats };
        true
    }

    /// The window is (re)opened: what it holds now is what Cancel goes back to, and the keys start on the categories.
    pub fn begin(&mut self) {
        self.orig = self.s.clone();
        self.zone = Zone::Cats;
        self.btn = 2;
        self.closing = false;
        self.edit = false;
    }

    /// Apply: the values so far are kept as what Cancel goes back to (they already show, and are stored as they change).
    pub fn commit(&mut self) {
        self.orig = self.s.clone();
        self.sounds.push(Se::Select);
    }

    /// Cancel: the values back to what they were when the window opened or was last applied. The installed and removed
    /// mod packs, and the places' reset, are done things and stay.
    pub fn cancel(&mut self) {
        let mods = std::mem::take(&mut self.s.mods);
        self.s = self.orig.clone();
        self.s.mods = mods;
        self.s.reset_places = false;
        self.dirty = true;
        self.closing = true;
        self.sounds.push(Se::Cancel);
    }

    /// Defaults: this category's rows back to the client's defaults (Config::default and the tool's); on Graphics that
    /// is the Original preset and the other quality rows. The Interface row (the window itself would vanish) and a
    /// pending Panel Places reset stay.
    pub fn reset_category(&mut self) {
        let d = SettingsUi::open_kind(&Config::default(), self.window, Kind::Settings);
        let before = self.s.clone();
        for r in self.rows() {
            match r.val {
                Val::Preset | Val::ModernUi | Val::ResetPlaces | Val::Mod(_) => {}
                Val::Size(a, b, _) => {
                    self.tool_set(a, d.tool_get(a));
                    self.tool_set(b, d.tool_get(b));
                }
                Val::Gamma => self.tool_set("0028", d.tool_get("0028")),
                Val::FrameLimit => self.s.frame_limit = d.s.frame_limit,
                Val::Monitor => self.s.monitor = d.s.monitor.clone(),
                Val::Gpu => self.s.gpu = d.s.gpu.clone(),
                Val::Music => self.s.music = d.s.music,
                Val::Effects => self.s.effects = d.s.effects,
                Val::MapOpacity => self.s.map_opacity = d.s.map_opacity,
                v => self.set(v, d.get(v)),
            }
        }
        self.dirty |= self.s != before;
        self.sounds.push(Se::Select);
    }

    /// The rows as the window shows them.
    pub fn win_rows(&self) -> Vec<WRow> {
        self.rows()
            .iter()
            .map(|r| {
                let ctl = match () {
                    _ if is_slider(r) => {
                        let (n, at) = self.stops(r);
                        WCtl::Slider { n, at, shown: self.shown(r) }
                    }
                    _ if r.choices.len() == 2 && r.choices[0].1 == "ON" && r.choices[1].1 == "OFF" => WCtl::Toggle(self.get(r.val) == r.choices[0].0),
                    _ => WCtl::Segments { labels: r.choices.iter().map(|c| c.1.clone()).collect(), at: self.stops(r).1, locked: matches!(r.val, Val::Preset).then_some(CUSTOM as usize) },
                };
                let when = match r.when {
                    When::Now => "",
                    When::NextZone => "Applies on next zone",
                    When::Restart => "Needs restart",
                };
                WRow { label: r.label.clone(), help: plain(&r.help), when, ctl }
            })
            .collect()
    }

    /// The window's help for the cursor (the Mods page's own, else the key line).
    pub fn win_hint(&self) -> String {
        match self.zone {
            Zone::Cats => "Up / Down: category. Enter: its settings. Escape: cancel.".into(),
            Zone::Buttons => "Left / Right: a button. Enter: press it. Escape: back to the categories.".into(),
            Zone::Rows if self.on_mods() => self.modern_mods_help(),
            Zone::Rows => "Up / Down: setting. Left / Right: change it. Enter: next option. Escape: back to the categories.".into(),
        }
    }

    /// A category turned to by `d` in the window (the rows start at the first).
    pub fn win_turn(&mut self, d: i32) {
        self.edit = false;
        self.turn(d);
        self.row = 1;
        self.m_mods = (1, 0);
        if self.zone == Zone::Rows && self.row_count() == 0 && !self.on_mods() {
            self.zone = Zone::Cats;
        }
    }

    /// The category list's row `k` clicked.
    pub fn win_cat(&mut self, k: usize) {
        self.sounds.clear();
        self.zone = Zone::Cats;
        if k != self.tab {
            self.win_turn(k as i32 - self.tab as i32);
        }
    }

    /// The pointer on a row: the cursor there.
    pub fn win_focus(&mut self, row: usize) {
        if self.zone != Zone::Rows || self.row != row {
            self.zone = Zone::Rows;
            self.row = row;
            self.col = self.marked_col();
        }
    }

    /// A row set to stop `i` (a click or a drag).
    pub fn win_set(&mut self, row: usize, i: usize) {
        self.sounds.clear();
        self.win_focus(row);
        self.edit = false;
        let Some(r) = row.checked_sub(1).and_then(|k| self.rows().get(k).cloned()) else { return };
        if self.stops(&r).1 != i {
            self.set_stop(&r, i);
            self.sounds.push(Se::Cursor);
        }
    }

    /// A bottom button pressed (Defaults, Apply, OK, Cancel).
    pub fn win_press(&mut self, btn: usize) -> Done {
        self.sounds.clear();
        self.zone = Zone::Buttons;
        self.btn = btn.min(WIN_BUTTONS.len() - 1);
        match self.btn {
            0 => self.reset_category(),
            1 => self.commit(),
            2 => {
                self.commit();
                self.closing = true;
                return Done::Ok;
            }
            _ => {
                self.cancel();
                return Done::Cancel;
            }
        }
        Done::Stay
    }

    /// Enter on the category list: into its rows.
    fn win_into_rows(&mut self) {
        if self.row_count() == 0 && !self.on_mods() {
            self.sounds.push(Se::Error);
            return;
        }
        self.zone = Zone::Rows;
        self.row = 1;
        self.m_mods = (1, 0);
        self.col = self.marked_col();
        self.sounds.push(Se::Select);
    }

    /// A key in the window (the Mods category's rows take theirs from modern/options.rs). Tab and the pad's bumpers
    /// (Page Up / Down) turn the category from anywhere.
    pub fn win_key(&mut self, key: egui::Key, shift: bool) -> Done {
        use egui::Key as K;
        self.sounds.clear();
        match key {
            K::Tab => return self.turn_key(if shift { -1 } else { 1 }),
            K::PageUp => return self.turn_key(-1),
            K::PageDown => return self.turn_key(1),
            _ => {}
        }
        match self.zone {
            Zone::Cats => match key {
                K::ArrowUp | K::ArrowLeft => self.win_turn(-1),
                K::ArrowDown | K::ArrowRight => self.win_turn(1),
                K::Enter => self.win_into_rows(),
                K::Escape => {
                    self.cancel();
                    return Done::Cancel;
                }
                _ => {}
            },
            Zone::Rows => self.win_rows_key(key),
            Zone::Buttons => match key {
                K::ArrowLeft | K::ArrowRight => {
                    let n = WIN_BUTTONS.len() as i32;
                    self.btn = (self.btn as i32 + if key == K::ArrowRight { 1 } else { -1 }).rem_euclid(n) as usize;
                    self.sounds.push(Se::Cursor);
                }
                K::ArrowUp if self.row_count() > 0 || self.on_mods() => {
                    self.zone = Zone::Rows;
                    self.row = self.row_count().max(1);
                    self.col = self.marked_col();
                    self.sounds.push(Se::Cursor);
                }
                K::ArrowUp | K::ArrowDown | K::Escape => {
                    self.zone = Zone::Cats;
                    self.sounds.push(Se::Cursor);
                }
                K::Enter => return self.win_press(self.btn),
                _ => {}
            },
        }
        Done::Stay
    }

    fn turn_key(&mut self, d: i32) -> Done {
        self.win_turn(d);
        Done::Stay
    }

    fn win_rows_key(&mut self, key: egui::Key) {
        use egui::Key as K;
        let n = self.rows().len();
        let Some(r) = self.row.checked_sub(1).and_then(|k| self.rows().get(k).cloned()) else {
            self.zone = Zone::Cats;
            return;
        };
        match key {
            K::ArrowUp if self.row > 1 => self.row -= 1,
            K::ArrowUp => self.zone = Zone::Cats,
            K::ArrowDown if self.row < n => self.row += 1,
            K::ArrowDown => self.zone = Zone::Buttons,
            K::ArrowLeft | K::ArrowRight => {
                let (stops, at) = self.stops(&r);
                let d = if key == K::ArrowRight { 1 } else { -1 };
                // Two options flip either way; more stop at their ends (a slider never wraps).
                let to = if stops == 2 { 1 - at.min(1) } else { (at as i32 + d).clamp(0, stops as i32 - 1) as usize };
                if to != at {
                    self.set_stop(&r, to);
                    self.sounds.push(Se::Cursor);
                }
                return;
            }
            // Enter steps an option on (round, past the Preset's Custom); a slider has nothing to press.
            K::Enter => {
                if is_slider(&r) {
                    return;
                }
                let (stops, at) = self.stops(&r);
                let list = if matches!(r.val, Val::Preset) { PRESETS.len() } else { stops };
                if list < 2 {
                    return;
                }
                self.set_stop(&r, (at + 1) % list);
                self.sounds.push(Se::Select);
                return;
            }
            K::Escape => self.zone = Zone::Cats,
            _ => return,
        }
        self.col = self.marked_col();
        self.sounds.push(Se::Cursor);
    }
}

/// A row the window draws as a slider: the numeric and list-valued ones, and named choices too many for segments.
fn is_slider(r: &Row) -> bool {
    matches!(r.val, Val::Size(..) | Val::Gamma | Val::FrameLimit | Val::Monitor | Val::Gpu | Val::Music | Val::Effects | Val::MapOpacity | Val::ModernOpacity) || !(2..=5).contains(&r.choices.len())
}

/// A row as the window draws it: its heading, the help under it, when a change shows (empty: at once) and its control.
pub struct WRow {
    pub label: String,
    pub help: String,
    pub when: &'static str,
    pub ctl: WCtl,
}

/// A row's control in the window: a switch for ON / OFF, segments for a few named choices (`locked`: one that shows but
/// cannot be chosen, the Preset's Custom), a slider for the rest.
pub enum WCtl {
    Toggle(bool),
    Segments { labels: Vec<String>, at: usize, locked: Option<usize> },
    Slider { n: usize, at: usize, shown: String },
}
