//! Ours (the plan's "UI states": Exploration, Combat, Management as adaptive presets, docs/modern-ui.md): which HUD
//! panels each mode shows. The mode follows the game (engaged: Combat, held a few seconds after; a window or menu
//! the command menu opens: Management; else Exploration), never takes the keyboard, and only hides or shows panels.
//! A panel pinned shows in every mode. Panels fade in and out unless fades are off. `/uimodes` opens the editor (a
//! panel per row, a toggle per mode, a pin); config `modern_modes`.

use super::super::World;
use super::{Panels, Title, kit};
use crate::config::ModernModes;
use egui::{Context, FontId, Id, Sense, pos2, vec2};
use std::collections::HashMap;
use std::time::{Duration, Instant};

/// The modes, in config order.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Mode {
    Exploration = 0,
    Combat = 1,
    Management = 2,
}

pub const MODES: [(Mode, &str); 3] =
    [(Mode::Exploration, "Exploration"), (Mode::Combat, "Combat"), (Mode::Management, "Management")];

/// The panels a mode may hide (panel id, name). Windows the player opens are never hidden.
pub const PANELS: [(&str, &str); 13] = [
    ("status", "Status icons"),
    ("party", "Party"),
    ("alliance1", "Alliance 1"),
    ("alliance2", "Alliance 2"),
    ("target", "Target"),
    ("where", "Location"),
    ("cast", "Cast bar"),
    ("minimap", "Minimap"),
    ("timers_recasts", "Recasts"),
    ("timers_buffs", "Buffs"),
    ("timers_debuffs", "Debuffs"),
    ("regime", "Training"),
    ("skillchains", "Skillchains"),
];

/// How long Combat holds after disengaging (a pull's pause between targets keeps the combat layout).
const HOLD: Duration = Duration::from_secs(4);
/// A fade's length.
const FADE: f32 = 0.25;

/// The mode the game is in now; `engaged_at` keeps when we were last engaged.
pub fn current(w: &World, engaged_at: &std::cell::Cell<Option<Instant>>, focus: Option<&str>) -> Mode {
    if w.my_motion.status == 1 {
        engaged_at.set(Some(Instant::now()));
    }
    if engaged_at.get().is_some_and(|t| t.elapsed() < HOLD) {
        return Mode::Combat;
    }
    if matches!(focus, Some("window" | "command" | "command sub" | "list" | "cats" | "check" | "loot")) {
        return Mode::Management;
    }
    Mode::Exploration
}

/// Whether panel `id` shows in `mode`.
pub fn shows(cfg: &ModernModes, mode: Mode, id: &str) -> bool {
    cfg.pinned.iter().any(|p| p == id) || !cfg.hidden[mode as usize].iter().any(|p| p == id)
}

/// Each listed panel's opacity this frame (1 shown, 0 hidden; between while fading): the built-in panels and the
/// mods' windows (`mods`: key, label).
pub fn visibility(ctx: &Context, cfg: &ModernModes, mode: Mode, mods: &[(String, String)]) -> HashMap<String, f32> {
    PANELS
        .iter()
        .map(|&(id, _)| id)
        .chain(mods.iter().map(|m| m.0.as_str()))
        .map(|id| {
            let on = shows(cfg, mode, id);
            let v = if cfg.fades {
                ctx.animate_bool_with_time(Id::unique(("modern mode fade", id)), on, FADE)
            } else if on {
                1.0
            } else {
                0.0
            };
            (id.to_string(), v)
        })
        .collect()
}

/// The editor's rows: the built-in panels, then the mods' windows not standing in for one of them.
fn rows(mods: &[(String, String)]) -> Vec<(String, String)> {
    let mut out: Vec<(String, String)> = PANELS.iter().map(|&(id, name)| (id.to_string(), name.to_string())).collect();
    for (k, label) in mods {
        if !out.iter().any(|o| &o.0 == k) {
            out.push((k.clone(), label.clone()));
        }
    }
    out
}

/// The editor (/uimodes): per panel a toggle for each mode (lit: shown) and a pin; fades on or off; Reset; Close.
/// True when the config changed.
pub fn editor(p: &mut Panels, open: &mut bool, cfg: &mut ModernModes, mode: Mode, mods: &[(String, String)]) -> bool {
    if !*open {
        return false;
    }
    let m = p.m;
    let mut changed = false;
    let mut close = false;
    let note = format!("now: {}", MODES[mode as usize].1);
    let at = p.ctx.content_rect().center() - vec2(300.0, 230.0);
    p.panel_at(
        "uimodes",
        Some(Title { icon: None, text: "UI Modes", note: Some(&note), name: false }),
        600.0,
        at,
        |ui| {
            ui.label(
                egui::RichText::new(
                    "Which panels each mode shows, the mods' windows too. A pinned panel always shows.",
                )
                .size(m.theme.small)
                .color(m.theme.color("muted")),
            );
            ui.add_space(6.0);
            let font = FontId::proportional(m.theme.small);
            let max_h = (p.ctx.content_rect().height() * 0.6).max(200.0);
            egui::ScrollArea::vertical().max_height(max_h).auto_shrink([false, true]).show(ui, |ui| {
                egui::Grid::new(Id::unique("modern ui modes")).spacing(vec2(8.0, 4.0)).show(ui, |ui| {
                    ui.label("");
                    for (_, name) in MODES {
                        ui.label(egui::RichText::new(name).size(m.theme.small).color(m.theme.color("gold")));
                    }
                    ui.label(egui::RichText::new("Pinned").size(m.theme.small).color(m.theme.color("gold")));
                    ui.end_row();
                    for (id, name) in rows(mods) {
                        let id = id.as_str();
                        let (r, _) = ui.allocate_exact_size(vec2(170.0, 26.0), Sense::hover());
                        let g = super::one_line(ui.painter(), &name, font.clone(), m.theme.color("text"), r.width());
                        ui.painter().galley(pos2(r.min.x, r.center().y - g.size().y / 2.0), g, egui::Color32::WHITE);
                        m.tip(ui, r, &name, "");
                        let pinned = cfg.pinned.iter().any(|p| p == id);
                        for (k, _) in MODES.iter().enumerate() {
                            let on = !cfg.hidden[k].iter().any(|p| p == id);
                            let s = kit::Btn { lit: on && !pinned, cursor: false, off: pinned };
                            if kit::clicked(
                                &kit::button(ui, m, if on || pinned { "Shown" } else { "Hidden" }, 84.0, s),
                                s,
                            ) {
                                if on {
                                    cfg.hidden[k].push(id.to_string());
                                } else {
                                    cfg.hidden[k].retain(|p| p != id);
                                }
                                changed = true;
                            }
                        }
                        let s = kit::Btn { lit: pinned, cursor: false, off: false };
                        if kit::clicked(&kit::button(ui, m, if pinned { "Pinned" } else { "Pin" }, 84.0, s), s) {
                            if pinned {
                                cfg.pinned.retain(|p| p != id);
                            } else {
                                cfg.pinned.push(id.to_string());
                            }
                            changed = true;
                        }
                        ui.end_row();
                    }
                });
            });
            ui.add_space(8.0);
            ui.horizontal(|ui| {
                ui.spacing_mut().item_spacing.x = 6.0;
                let s = kit::Btn { lit: cfg.fades, cursor: false, off: false };
                if kit::clicked(&kit::button(ui, m, if cfg.fades { "Fades: On" } else { "Fades: Off" }, 0.0, s), s) {
                    cfg.fades = !cfg.fades;
                    changed = true;
                }
                let plain = kit::Btn { lit: false, cursor: false, off: false };
                if kit::clicked(&kit::button(ui, m, "Reset", 0.0, plain), plain) {
                    *cfg = ModernModes::default();
                    changed = true;
                }
                if kit::clicked(&kit::button(ui, m, "Close", 0.0, plain), plain) {
                    close = true;
                }
            });
        },
    );
    // Escape closes it in the key chain (client/mod.rs), so it reaches nothing under it.
    if close {
        *open = false;
    }
    changed
}

#[cfg(test)]
mod tests {
    use super::{Mode, shows};
    use crate::config::ModernModes;

    #[test]
    fn defaults_and_pins() {
        let mut c = ModernModes::default();
        // The location panel hides while engaged (user, 2026-11-01), as before the modes.
        assert!(!shows(&c, Mode::Combat, "where"));
        assert!(shows(&c, Mode::Exploration, "where"));
        assert!(shows(&c, Mode::Combat, "party"));
        c.pinned.push("where".into());
        assert!(shows(&c, Mode::Combat, "where"));
    }
}
