//! Ours (not retail): the Graphics & Interface window of the modern layer, over client/settings.rs (its rows, presets
//! and keys): a panel of about 900 x 600 points (clamped to the screen) with the categories down the left, the chosen
//! category's rows on the right (the heading, its help under it, when a change shows, and a switch, segments or a
//! slider) and Defaults, Apply, OK and Cancel at the bottom. Every change shows at once; Cancel puts the values back.
//! Keys (the pad's arrows, Enter, Escape, bumpers as Page Up / Down): Up / Down on the list or the rows, Left / Right
//! change a value, Enter steps an option or presses, Tab / the bumpers turn the category, Escape goes back and, on the
//! list, cancels. The pages of the Mods category are config.rs's.

use super::super::World;
use super::super::settings::{Done, SettingsUi, WCtl, WIN_BUTTONS, WRow, Zone};
use super::config::{self, ModDo};
use super::kit::{self, Btn};
use super::{Panels, Title};
use egui::{Align, Align2, Color32, FontFamily, FontId, Layout, RichText, Sense, Shape, Stroke, StrokeKind, Ui, pos2, vec2};

/// The panel's id (and what the key dispatch's focus names).
pub const ID: &str = "options";
/// The window's size at Interface Size 100%, and how far from the screen's edges it keeps.
const WIDTH: f32 = 900.0;
const HEIGHT: f32 = 600.0;
const EDGE: f32 = 12.0;
/// The category list's width, the gap, and the controls' column.
const CATS_W: f32 = 184.0;
const GAP: f32 = 14.0;
const CTL_W: f32 = 320.0;

/// What the pointer did in the window.
pub enum Do {
    Cat(usize),
    Set(usize, usize),
    Press(usize),
    Mods(ModDo),
}

/// The pointer's acts done; what the window then is (Ok and Cancel close it).
pub fn apply(s: &mut SettingsUi, acts: Vec<Do>) -> Done {
    let mut done = Done::Stay;
    for a in acts {
        match a {
            Do::Cat(k) => s.win_cat(k),
            Do::Set(row, i) => s.win_set(row, i),
            Do::Press(b) => {
                let d = s.win_press(b);
                if d != Done::Stay {
                    done = d;
                }
            }
            Do::Mods(m) => {
                s.zone = Zone::Rows;
                config::mods_do(s, vec![m]);
            }
        }
    }
    done
}

/// A key in the window: the Mods category's rows take it through config.rs's stops (its file picker and removal prompt
/// have every key), the rest the model's.
pub fn key(s: &mut SettingsUi, key: egui::Key, shift: bool) -> Done {
    use egui::Key as K;
    let modal = s.m_remove.is_some() || s.mods_state().is_some_and(|m| m.browse.is_some());
    if s.on_mods_page() && s.zone == Zone::Rows && (modal || !matches!(key, K::Tab | K::PageUp | K::PageDown | K::Escape)) {
        config::ours_key(s, key, shift);
        // The stop above the first is the category list's, the one past the last the buttons'.
        if !modal && s.m_mods.0 == 0 {
            s.zone = if key == K::ArrowDown { Zone::Buttons } else { Zone::Cats };
            s.m_mods = (1, 0);
        }
        return Done::Stay;
    }
    s.win_key(key, shift)
}

/// Keys from the game: the window of the world's Settings.
pub fn world_key(w: &mut World, key: egui::Key, shift: bool) {
    let Some(s) = w.settings.as_mut() else { return };
    self::key(s, key, shift);
    w.sounds.extend(s.sounds.drain(..).map(|x| x as u32));
}

/// Where the keyboard cursor is, as one number (the page follows it when it changes).
fn cursor(s: &SettingsUi) -> usize {
    s.category() * 1_000_000 + s.view_row() * 1000 + s.m_mods.0 * 10 + s.zone as usize
}

/// The window in the game.
pub fn draw(p: &mut Panels, w: &mut World) {
    if !w.modern {
        return;
    }
    let Some(s) = w.settings.as_ref().filter(|s| s.windowed() && !s.closing) else { return };
    let follow = p.m.moved("options", cursor(s));
    let mut acts = Vec::new();
    window(p, s, follow, &mut acts);
    if acts.is_empty() {
        return;
    }
    if let Some(s) = w.settings.as_mut() {
        apply(s, acts);
        w.sounds.extend(s.sounds.drain(..).map(|x| x as u32));
    }
}

/// The window's own cursor change, for the lobby (its page follows the cursor too).
pub fn follow(p: &Panels, s: &SettingsUi) -> bool {
    p.m.moved("options", cursor(s))
}

/// Draws the window; the pointer's acts go to `act`.
pub fn window(p: &mut Panels, s: &SettingsUi, follow: bool, act: &mut Vec<Do>) {
    let m = p.m;
    let screen = p.ctx.content_rect();
    let w = WIDTH.min(screen.width() - 2.0 * EDGE).max(360f32.min(screen.width()));
    let h = HEIGHT.min(screen.height() - 2.0 * EDGE).max(300f32.min(screen.height()));
    let at = pos2(((screen.width() - w) / 2.0).round(), ((screen.height() - h) / 2.0).round().max(0.0));
    // The title, the margins, the hint and the buttons take what the body does not.
    let body = (h - 140.0).max(160.0);
    let title = Title { icon: Some("icons/config"), text: "Graphics & Interface", note: None };
    p.panel_at(ID, Some(title), w, at, |ui| {
        let inner = ui.available_width();
        let right = (inner - CATS_W - GAP).max(200.0);
        ui.horizontal_top(|ui| {
            categories(ui, m, s, body, act);
            ui.add_space(GAP);
            ui.vertical(|ui| {
                ui.set_width(right);
                page(ui, m, s, body, right, follow, act);
            });
        });
        ui.add_space(6.0);
        ui.separator();
        ui.label(RichText::new(s.win_hint()).size(m.theme.small).color(m.theme.color("muted")));
        ui.add_space(6.0);
        buttons(ui, m, s, act);
    });
}

/// The category list: the chosen one lit (gold, ringed while the list has the keys).
fn categories(ui: &mut Ui, m: &super::Modern, s: &SettingsUi, body: f32, act: &mut Vec<Do>) {
    ui.vertical(|ui| {
        ui.set_width(CATS_W);
        ui.set_min_height(body);
        for (k, name) in s.categories().iter().enumerate() {
            let (r, resp) = ui.allocate_exact_size(vec2(CATS_W, 36.0), Sense::click());
            let here = k == s.category();
            let face = match () {
                _ if here && s.zone == Zone::Cats => "controls/list_row_selected",
                _ if here || resp.hovered() => "controls/list_row_hover",
                _ => "controls/list_row_normal",
            };
            super::rows::face(ui.painter(), m, r, face, Color32::WHITE);
            let c = if here { m.theme.color("gold") } else { m.theme.color("text") };
            ui.painter().text(pos2(r.min.x + 22.0, r.center().y), Align2::LEFT_CENTER, name, FontId::proportional(m.theme.ui), c);
            if resp.clicked() {
                act.push(Do::Cat(k));
            }
            ui.add_space(2.0);
        }
    });
}

/// The chosen category: its name, then its rows (or the Mods page, or what is coming).
fn page(ui: &mut Ui, m: &super::Modern, s: &SettingsUi, body: f32, right: f32, follow: bool, act: &mut Vec<Do>) {
    let name = s.categories().get(s.category()).cloned().unwrap_or_default();
    ui.label(RichText::new(name).size(m.theme.title).family(FontFamily::Name(super::STRONG.into())).color(m.theme.color("gold")));
    ui.add_space(4.0);
    let room = body - 32.0;
    let scroll = egui::ScrollArea::vertical().id_salt(("options page", s.category())).min_scrolled_height(room).max_height(room).auto_shrink([false, false]);
    if s.on_mods_page() {
        let mut mact = Vec::new();
        scroll.show(ui, |ui| {
            ui.set_width(right - 14.0);
            config::mods_page(ui, m, s, s.zone == Zone::Rows, follow, &mut mact);
        });
        act.extend(mact.into_iter().map(Do::Mods));
        return;
    }
    if let Some(note) = s.note() {
        ui.label(RichText::new(note).size(m.theme.ui).color(m.theme.color("muted")));
        return;
    }
    let rows = s.win_rows();
    scroll.show(ui, |ui| {
        ui.set_width(right - 14.0);
        for (k, r) in rows.iter().enumerate() {
            let here = s.zone == Zone::Rows && s.view_row() == k + 1;
            row(ui, m, k + 1, r, here, follow, right - 14.0, act);
        }
    });
}

/// One row: heading, help and note on the left, its control on the right; ringed while the cursor is on it.
#[allow(clippy::too_many_arguments)]
fn row(ui: &mut Ui, m: &super::Modern, row: usize, r: &WRow, focus: bool, follow: bool, width: f32, act: &mut Vec<Do>) {
    let ctl_w = CTL_W.min(width * 0.55);
    let label_w = (width - ctl_w - 20.0).max(120.0);
    let bg = ui.painter().add(Shape::Noop);
    let inner = ui.horizontal_top(|ui| {
        ui.vertical(|ui| {
            ui.set_width(label_w);
            let c = if focus { m.theme.color("gold") } else { m.theme.color("text") };
            ui.label(RichText::new(&r.label).size(m.theme.ui).family(FontFamily::Name(super::STRONG.into())).color(c));
            ui.add(egui::Label::new(RichText::new(&r.help).size(m.theme.small - 1.0).color(m.theme.color("muted"))).wrap());
            if !r.when.is_empty() {
                ui.label(RichText::new(r.when).size(m.theme.small - 1.0).italics().color(m.theme.color("bronze")));
            }
        });
        ui.add_space(20.0);
        ui.vertical(|ui| {
            ui.set_width(ctl_w);
            ui.add_space(2.0);
            control(ui, m, row, r, act);
        });
    });
    let rect = inner.response.rect.expand2(vec2(8.0, 5.0));
    if focus {
        ui.painter().set(bg, Shape::rect_filled(rect, 6.0, m.theme.color("focus").gamma_multiply(0.12)));
        ui.painter().rect_stroke(rect, 6.0, Stroke::new(1.5, m.theme.color("focus").gamma_multiply(0.85)), StrokeKind::Outside);
        if follow {
            ui.scroll_to_rect(rect, None);
        }
    }
    ui.add_space(8.0);
    let y = ui.cursor().min.y - 4.0;
    ui.painter().hline(rect.x_range(), y, Stroke::new(1.0, m.theme.color("bronze").gamma_multiply(0.25)));
    ui.add_space(6.0);
}

/// A row's control: a click or drag acts on the row.
fn control(ui: &mut Ui, m: &super::Modern, row: usize, r: &WRow, act: &mut Vec<Do>) {
    match &r.ctl {
        WCtl::Toggle(on) => {
            ui.horizontal(|ui| {
                let (rect, resp) = ui.allocate_exact_size(vec2(52.0, 26.0), Sense::click());
                let lit = *on;
                let hover = resp.hovered();
                let p = ui.painter();
                p.rect(rect, 13.0, if lit { m.theme.color("bronze") } else { m.theme.color("charcoal") }, Stroke::new(1.5, if lit || hover { m.theme.color("gold") } else { m.theme.color("bronze").gamma_multiply(0.6) }), StrokeKind::Inside);
                let kx = if lit { rect.max.x - 13.0 } else { rect.min.x + 13.0 };
                p.circle(pos2(kx, rect.center().y), 9.0, if lit { m.theme.color("gold") } else { m.theme.color("muted") }, Stroke::new(1.0, Color32::from_black_alpha(200)));
                ui.add_space(8.0);
                ui.label(RichText::new(if lit { "On" } else { "Off" }).size(m.theme.small).color(if lit { m.theme.color("gold") } else { m.theme.color("muted") }));
                // The ON / OFF choices are (ON, OFF): stop 0 is On.
                if resp.clicked() {
                    act.push(Do::Set(row, if lit { 1 } else { 0 }));
                }
            });
        }
        WCtl::Segments { labels, at, locked } => {
            ui.horizontal_wrapped(|ui| {
                ui.spacing_mut().item_spacing = vec2(6.0, 6.0);
                let font = FontId::proportional(m.theme.small);
                for (k, label) in labels.iter().enumerate() {
                    let lit = k == *at;
                    let shut = *locked == Some(k);
                    let tw = ui.fonts_mut(|f| f.layout_no_wrap(label.clone(), font.clone(), Color32::WHITE).size().x);
                    // A locked choice (the Preset's Custom) shows what holds but cannot be taken.
                    let s = Btn { lit, cursor: false, off: shut && !lit };
                    if kit::button(ui, m, label, (tw + 22.0).max(46.0), s).clicked() && !shut {
                        act.push(Do::Set(row, k));
                    }
                }
            });
        }
        WCtl::Slider { n, at, shown } => {
            if let Some(i) = kit::slider(ui, m, *n, *at, shown) {
                act.push(Do::Set(row, i));
            }
        }
    }
}

/// Defaults at the left; Apply, OK and Cancel at the right.
fn buttons(ui: &mut Ui, m: &super::Modern, s: &SettingsUi, act: &mut Vec<Do>) {
    let has_rows = s.on_mods_page() || s.note().is_none();
    let state = |i: usize| Btn { cursor: s.zone == Zone::Buttons && s.btn == i, lit: false, off: i == 0 && (s.on_mods_page() || !has_rows) };
    ui.horizontal(|ui| {
        let b = state(0);
        if kit::clicked(&kit::button(ui, m, WIN_BUTTONS[0], 104.0, b), b) {
            act.push(Do::Press(0));
        }
        ui.with_layout(Layout::right_to_left(Align::Center), |ui| {
            for i in (1..WIN_BUTTONS.len()).rev() {
                let b = state(i);
                if kit::clicked(&kit::button(ui, m, WIN_BUTTONS[i], 104.0, b), b) {
                    act.push(Do::Press(i));
                }
            }
        });
    });
}

/// The shot's window (`modern-shot --panel`): the category named and its row, over sample monitors.
pub fn sample(p: &mut Panels, name: &str, row: usize, size: [u32; 2]) {
    let mut cfg = crate::config::Config::default();
    cfg.tool.insert("0001".into(), size[0]);
    cfg.tool.insert("0002".into(), size[1]);
    let mut s = SettingsUi::open(&cfg, size);
    s.in_game = true;
    s.monitors = vec![("DP-1".into(), "DP-1  2560 x 1440".into()), ("HDMI-1".into(), "HDMI-1  1920 x 1080".into())];
    s.gpus = vec!["AMD Radeon RX 6800 XT (RADV NAVI21)".into(), "llvmpipe".into()];
    s.begin();
    if !s.open_page(name) {
        s.open_page("graphics");
    }
    if row == 0 {
        s.zone = Zone::Cats;
    } else {
        s.goto_row(row);
    }
    let mut acts = Vec::new();
    window(p, &s, false, &mut acts);
}
