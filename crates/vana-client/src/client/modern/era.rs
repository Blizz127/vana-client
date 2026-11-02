//! Ours (not retail): the Expansions view and the new expansion notice over client/era.rs, which keeps the table and
//! the keys (Enter or Escape closes). The view lists each expansion with Locked or Unlocked from the lobby's bitmask;
//! the notice is a small alert once, the first time a bit appears that the last login of this server and account did
//! not have.

use super::super::{World, era};
use super::craft::button;
use super::{Panels, Title};
use egui::{Align2, FontId, Sense, pos2, vec2};

const W: f32 = 330.0;
const ROW: f32 = 28.0;

pub fn draw(p: &mut Panels, w: &mut World) {
    if !w.modern {
        return;
    }
    let m = p.m;
    let mut done = false;
    if w.era_view {
        let rows = era::rows(w.lobby_expansions);
        let note = match (era::era_of(w.lobby_expansions), w.era_lock) {
            (era::Era::Base, true) => "Base game: the era lock hides later systems (Extras).",
            (era::Era::Base, false) => "Base game (the era lock is off).",
            (era::Era::Expanded, _) => "Expansions on: retail's windows.",
        };
        p.panel("expansions", Some(Title { icon: Some("icons/info"), text: "Expansions", note: None }), W + 44.0, |ui| {
            for (name, on) in &rows {
                let (r, _) = ui.allocate_exact_size(vec2(W, ROW), Sense::hover());
                super::rows::face(ui.painter(), m, r, if *on { "controls/list_row_normal" } else { "controls/list_row_disabled" }, egui::Color32::WHITE);
                let font = FontId::proportional(m.theme.small);
                ui.painter().text(pos2(r.min.x + 24.0, r.center().y), Align2::LEFT_CENTER, *name, font.clone(), if *on { m.theme.color("text") } else { m.theme.color("muted") });
                ui.painter().text(pos2(r.max.x - 14.0, r.center().y), Align2::RIGHT_CENTER, if *on { "Unlocked" } else { "Locked" }, font, if *on { m.theme.color("gold") } else { m.theme.color("muted") });
                ui.add_space(2.0);
            }
            ui.add_space(6.0);
            ui.label(egui::RichText::new(note).size(m.theme.small).color(m.theme.color("muted")));
            ui.add_space(6.0);
            done = button(ui, m, "OK", 110.0, true, false);
        });
    } else if let Some(text) = era::notice(w.era_new) {
        p.framed("expansions", Some(Title { icon: Some("icons/info"), text: "Expansions", note: None }), W + 44.0, "window_alert", |ui| {
            ui.label(egui::RichText::new(text).size(m.theme.ui).color(m.theme.color("gold")));
            ui.add_space(8.0);
            done = button(ui, m, "OK", 110.0, true, false);
        });
    }
    if done {
        w.sounds.push(crate::audio::Ui::Select as u32);
        era::close(w);
    }
}
