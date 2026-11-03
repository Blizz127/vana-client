//! Tests of the HUD's default places (theme.rs SCREEN_GAP / PANEL_GAP, mod.rs default_place): the panels as the layer
//! leaves them after a few frames, with no GPU (egui lays out and tessellates on the CPU), at the window sizes the
//! client runs at and Interface Size's extremes.

use super::shot::{EFFECTS, Opts, sample};
use super::theme::{BELOW_BAR, PANEL_GAP, SCREEN_GAP};
use super::{Layout, Modern};
use egui::{Pos2, Rect, vec2};
use std::collections::HashMap;

/// The panels' rects (points) after eight frames of the shot's sample HUD, the screen in points, the top bar's span.
fn layout_of(width: u32, height: u32, scale: u32, layout: &mut Layout) -> (HashMap<String, Rect>, Rect, Option<Rect>) {
    let ctx = egui::Context::default();
    let m = Modern::new(&ctx);
    let zoom = m.theme.zoom(height as f32, scale);
    ctx.set_zoom_factor(zoom);
    let opts = Opts { chat_font: 15.0, font: None, list: false, rows: None, borders: None, opacity: 0.85, kit: false, panel: None, panel_row: 1 };
    let screen = Rect::from_min_size(Pos2::ZERO, vec2(width as f32, height as f32) / zoom);
    for frame in 0..8 {
        let raw = egui::RawInput { screen_rect: Some(screen), time: Some(frame as f64 * 0.5), ..Default::default() };
        let _ = ctx.run_ui(raw, |ui| {
            // Frame 0 only sets the screen (egui's first frame has its default one).
            if frame > 0 {
                sample(&m, ui.ctx(), layout, &opts, true);
            }
        });
    }
    let rects = m.rects.borrow().clone();
    let bar = m.top_bar.get().map(|b| b.0);
    (rects, screen, bar)
}

/// The panels of the HUD's default places, with few effects and with a party's worth (four rows of icons): all on the
/// screen's margin, none over another or under the top bar, the chat window ending short of the party column (it ran
/// under the party window's rows, its gear and grip over them: the user's report, 2026-11-03), the Timers' place under
/// the effect icons, and the minimap (an edge window drawn by extras.rs at its default place, up to its largest size)
/// clear of the party column wherever the screen has the room for both. The combinations with no such room are printed.
#[test]
fn default_hud_does_not_overlap() {
    let mut cramped = Vec::new();
    for (w, h) in [(1280, 800), (1920, 1080), (2560, 1440), (3840, 2160)] {
        for scale in [50, 60, 100, 150] {
            for effects in [4, 32] {
                EFFECTS.with(|n| n.set(effects));
                let (rects, screen, bar) = layout_of(w, h, scale, &mut Layout::new());
                let at = format!("{w}x{h} at {scale}% with {effects} effects");
                let bar = bar.unwrap_or_else(|| panic!("{at}: no top bar"));
                let of = |id: &str| *rects.get(id).unwrap_or_else(|| panic!("{at}: no {id} panel: {rects:?}"));
                let ids = ["chat", "where", "party", "target", "cast"];
                for id in ids {
                    let r = of(id);
                    assert!(r.min.x >= screen.min.x + SCREEN_GAP - 1.0 && r.max.x <= screen.max.x - SCREEN_GAP + 1.0, "{at}: {id} {r:?} off the screen's margin {screen:?}");
                    assert!(r.max.y <= screen.max.y - SCREEN_GAP + 1.0, "{at}: {id} {r:?} past the bottom margin");
                    assert!(r.min.y >= bar.max.y, "{at}: {id} {r:?} under the top bar {bar:?}");
                }
                // The effect icons have no frame: what they draw is inside their margin.
                let status = of("status").shrink2(vec2(super::MARGIN.left as f32, super::MARGIN.top as f32));
                assert!(status.min.y >= bar.max.y, "{at}: status {status:?} under the top bar {bar:?}");
                let all = ids.iter().map(|id| (*id, of(id))).chain([("status", status)]).collect::<Vec<_>>();
                for (i, (a, ra)) in all.iter().enumerate() {
                    for (b, rb) in &all[i + 1..] {
                        // Docked panels share a border: a point of it does not count.
                        assert!(!ra.shrink(1.0).intersects(rb.shrink(1.0)), "{at}: {a} {ra:?} over {b} {rb:?}");
                    }
                }
                let (chat, party, target) = (of("chat"), of("party"), of("target"));
                assert!(chat.max.x <= party.min.x - PANEL_GAP + 0.5, "{at}: chat {chat:?} runs into the party window {party:?}");
                // The chat window takes the room: no more than a gap short of the party column.
                assert!(chat.max.x >= party.min.x - 2.0 * PANEL_GAP, "{at}: chat {chat:?} leaves room left of {party:?}");
                assert!(target.max.y <= party.min.y, "{at}: target {target:?} over party {party:?}");
                // The Timers (left edge, extras.rs) start under the effect icons.
                let timers = super::default_place("timers", screen.size());
                assert!(timers.y * screen.height() >= status.max.y, "{at}: the Timers' place {timers:?} over the effect icons {status:?}");
                // The minimap: flush right under the top bar, as wide as its largest size on screen (its layout pixels are
                // screen pixels, `zoom` points each) with its heading and margins.
                let zoom = w as f32 / screen.width();
                let d = super::super::minimap::SIZES[2] / zoom;
                let mini = Rect::from_min_max(egui::pos2(screen.max.x - d - 30.0, BELOW_BAR), egui::pos2(screen.max.x, BELOW_BAR + d + 70.0));
                let place = super::default_place("minimap", screen.size());
                assert!(place.y * screen.height() >= bar.max.y, "{at}: the minimap's place {place:?} under the top bar {bar:?}");
                let column = target.union(party);
                let room = screen.max.y - SCREEN_GAP - mini.max.y;
                if column.height() + PANEL_GAP <= room {
                    assert!(!mini.intersects(column), "{at}: minimap {mini:?} over the right column {column:?}");
                } else {
                    cramped.push(format!("{at}: column {:.0} high, room under the minimap {room:.0}", column.height()));
                }
            }
        }
    }
    EFFECTS.with(|n| n.set(0));
    println!("no room for the minimap and the five-member party's column together ({}):\n{}", cramped.len(), cramped.join("\n"));
}

/// What a player saved stays theirs, kept on the screen and, for the chat window, clear of the party window and under
/// the top bar.
#[test]
fn saved_places_stay_on_screen() {
    use crate::config::ModernPlace as Place;
    for (w, h, scale) in [(1280, 800, 100), (1920, 1080, 60), (3840, 2160, 150)] {
        let mut layout = Layout::new();
        // A chat window saved wide and tall (a bigger window, a smaller Interface Size), the party window off the right
        // edge.
        layout.insert("chat".into(), Place { x: 0.02, b: 0.99, w: 6000.0, h: 2000.0, ..Default::default() });
        layout.insert("party".into(), Place { x: 0.98, b: 0.97, ..Default::default() });
        let (rects, screen, bar) = layout_of(w, h, scale, &mut layout);
        let at = format!("{w}x{h} at {scale}%");
        let (chat, party) = (rects["chat"], rects["party"]);
        assert!(party.max.x <= screen.max.x + 1.0 && party.min.x >= screen.min.x, "{at}: party {party:?} off the screen {screen:?}");
        assert!(chat.max.x <= screen.max.x + 1.0, "{at}: chat {chat:?} off the screen {screen:?}");
        assert!(chat.max.x <= party.min.x - PANEL_GAP + 0.5, "{at}: chat {chat:?} under party {party:?}");
        assert!(chat.min.y >= bar.unwrap().max.y - 1.0, "{at}: chat {chat:?} up under the top bar");
        // The place saved is kept (not rewritten by the clamp).
        assert_eq!(layout["chat"].w, 6000.0, "{at}");
        assert_eq!(layout["chat"].h, 2000.0, "{at}");
        assert_eq!(layout["party"].x, 0.98, "{at}");
    }
}
