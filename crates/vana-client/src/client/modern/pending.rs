//! The `chip` element of a mod's window (the bundled Pending Actions mod's): a dot, the action and its target, a note
//! at the right in the tone's colour (0 waiting, 1 refused, 2 quiet) and a detail line under it.

use egui::{Align2, FontId, Sense, pos2, vec2};

pub(super) fn chip(ui: &mut egui::Ui, m: &super::Modern, text: &str, note: &str, tone: u8, detail: &str) {
    let (r, _) = ui.allocate_exact_size(vec2(ui.available_width(), m.theme.ui + 6.0), Sense::hover());
    let font = FontId::proportional(m.theme.ui);
    let colour = if tone == 1 { m.theme.color("hp") } else { m.theme.color("muted") };
    // A dot in the state's colour, the action, the state at the right.
    ui.painter().circle_filled(
        pos2(r.min.x + 5.0, r.center().y),
        4.0,
        if tone == 0 { m.theme.color("focus") } else { colour },
    );
    ui.painter().text(pos2(r.min.x + 16.0, r.center().y), Align2::LEFT_CENTER, text, font, m.theme.color("text"));
    ui.painter().text(
        pos2(r.max.x, r.center().y),
        Align2::RIGHT_CENTER,
        note,
        FontId::proportional(m.theme.small),
        colour,
    );
    if !detail.is_empty() {
        ui.add_space(2.0);
        ui.label(egui::RichText::new(detail).size(m.theme.small).color(colour));
    }
}
