//! Ours (not retail): the era lock's row removal in the DAT-drawn (classic) windows.
//!
//! A classic window draws its rows straight from the layout's children (the sprite of each at the child's place, the
//! hand at the cursor child, the cursor links between them). The base era drops some of those rows, so the layout
//! itself is rewritten the way a menu with fewer rows would be laid out: the dropped children go, the others slide
//! up into the freed places (each keeps its own x and takes the y of the place its position in the list had), the
//! cursor links that named a dropped child follow that child's own link to the next one still there, and the frame
//! shrinks by the freed height. Every reader (the draw, the hit tests, the links, `window_rect`) then sees one layout.
//!
//! Nothing is guessed about the file: a layout whose rows are not one column in the order given, or lack a child, is
//! left alone (`Pack::Refused`), and the caller keeps the row, disabled, as it did before. The rewrite is made from
//! the pristine layout each time, so lifting the lock puts back exactly the file's own.

use crate::dat::ui::Menu;
use std::collections::HashMap;

/// Where a window's rows come from, top to bottom.
#[derive(Clone, Debug, PartialEq, Eq)]
pub enum Rows {
    /// The child ids in the order the window's code lists them.
    Ids(Vec<u16>),
    /// The chain of the layout's own down links from this child, until it repeats or ends.
    Chain(u16),
}

/// One window to rewrite: the rows to drop, and a frame height to clip to where the window has no row children.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Spec {
    pub name: &'static str,
    pub rows: Rows,
    pub hidden: Vec<u16>,
    /// A window drawn in code over its frame (quest00): the frame's new height, no child moved.
    pub clip: Option<u16>,
}

/// The outcome of a rewrite.
#[derive(Debug)]
pub enum Pack {
    /// Nothing to drop.
    Same,
    Packed(Menu),
    /// Why the layout was not touched.
    Refused(&'static str),
}

/// The layout's down links (child byte 3, the one statcom2's Down key follows) from `start`, each child once.
pub fn chain(m: &Menu, start: u16) -> Vec<u16> {
    let mut out = Vec::new();
    let mut at = start;
    while at != 0 && at != 0xff && !out.contains(&at) {
        let Some(e) = m.elements.iter().skip(1).find(|e| e.id == at) else { break };
        out.push(at);
        at = e.links[3] as u16;
    }
    out
}

/// A child by id (children only; the window is element 0).
fn find(m: &Menu, id: u16) -> Option<usize> {
    (1..m.elements.len()).find(|&i| m.elements[i].id == id)
}

/// The layout with the `hidden` rows of `order` dropped and the rest packed up. `order` lists every row top to bottom
/// (hidden ones included).
pub fn repack(orig: &Menu, order: &[u16], hidden: &[u16]) -> Pack {
    if !order.iter().any(|id| hidden.contains(id)) {
        return Pack::Same;
    }
    let Some(slots) = order.iter().map(|&id| find(orig, id).map(|i| orig.elements[i].y)).collect::<Option<Vec<i16>>>() else {
        return Pack::Refused("a row is not a child of the layout");
    };
    if slots.windows(2).any(|p| p[0] >= p[1]) {
        return Pack::Refused("the rows are not one column in list order");
    }
    let keep: Vec<u16> = order.iter().copied().filter(|id| !hidden.contains(id)).collect();
    if keep.is_empty() {
        return Pack::Refused("no row would be left");
    }
    let delta = slots[slots.len() - 1] - slots[keep.len() - 1];
    let Some(h) = orig.elements[0].h.checked_sub(delta as u16).filter(|&h| h > 0) else {
        return Pack::Refused("the frame would vanish");
    };
    let mut m = orig.clone();
    // Each kept row takes the place its position in the list had.
    for (k, &id) in keep.iter().enumerate() {
        if let Some(i) = find(&m, id) {
            m.elements[i].y = slots[k];
        }
    }
    // The links that name a dropped row follow that row's own link of the same slot until a row that stays (or none:
    // 0 / 0xff, as the file has it).
    for e in m.elements.iter_mut().skip(1) {
        for slot in 0..4 {
            let gone = |id: u16| hidden.contains(&id) && order.contains(&id);
            let mut to = e.links[slot] as u16;
            for _ in 0..=order.len() {
                if !gone(to) {
                    break;
                }
                to = find(orig, to).map_or(0xff, |i| orig.elements[i].links[slot] as u16);
            }
            // A ring of dropped rows only (none can be, a row stays): no link.
            e.links[slot] = if gone(to) { 0xff } else { to as u8 };
        }
    }
    let mut n = 0;
    m.elements.retain(|e| {
        n += 1;
        n == 1 || !(hidden.contains(&e.id) && order.contains(&e.id))
    });
    // The window: a shorter frame; one anchored to the bottom of the screen keeps its bottom edge.
    m.elements[0].h = h;
    if m.elements[0].head[0x13] & 2 != 0 {
        m.elements[0].y += delta;
    }
    Pack::Packed(m)
}

/// The layout with its frame clipped to `h` (a window whose rows the code draws).
pub fn clip(orig: &Menu, h: u16) -> Pack {
    if h == 0 || h >= orig.elements[0].h {
        return Pack::Same;
    }
    let mut m = orig.clone();
    let delta = (orig.elements[0].h - h) as i16;
    m.elements[0].h = h;
    if m.elements[0].head[0x13] & 2 != 0 {
        m.elements[0].y += delta;
    }
    Pack::Packed(m)
}

/// The rewrite a spec asks of this layout.
pub fn apply(orig: &Menu, spec: &Spec) -> Pack {
    match (&spec.rows, spec.clip) {
        (_, Some(h)) => clip(orig, h),
        (Rows::Ids(ids), None) => repack(orig, ids, &spec.hidden),
        (Rows::Chain(start), None) => repack(orig, &chain(orig, *start), &spec.hidden),
    }
}

/// The rewrites made so far: the file's own menus they replaced, and what each asked for and whether it was made.
#[derive(Default)]
pub struct Layouts {
    orig: HashMap<String, Menu>,
    applied: HashMap<String, (Spec, bool)>,
}

impl Layouts {
    /// Puts the menus `specs` name in the shape they ask and every other one back as the file has it. Returns the
    /// windows rewritten. A spec already made is not made again; a layout that is not as listed is left alone (logged).
    pub fn sync(&mut self, menus: &mut [Menu], specs: &[Spec]) -> Vec<&'static str> {
        let stale: Vec<String> = self.applied.keys().filter(|k| !specs.iter().any(|s| s.name == k.as_str())).cloned().collect();
        for name in stale {
            self.applied.remove(&name);
            self.restore(menus, &name);
        }
        let mut done = Vec::new();
        for spec in specs {
            if let Some((_, made)) = self.applied.get(spec.name).filter(|a| &a.0 == spec) {
                if *made {
                    done.push(spec.name);
                }
                continue;
            }
            self.restore(menus, spec.name);
            let key = spec.name.to_ascii_lowercase();
            let made = match menus.iter_mut().find(|m| m.name == key) {
                Some(slot) => match apply(slot, spec) {
                    Pack::Packed(m) => {
                        log::info!("era lock: {} laid out without its later-era rows", spec.name);
                        self.orig.insert(key, std::mem::replace(slot, m));
                        true
                    }
                    Pack::Refused(why) => {
                        log::warn!("era lock: {} left as the file has it ({why})", spec.name);
                        false
                    }
                    Pack::Same => false,
                },
                None => false,
            };
            if made {
                done.push(spec.name);
            }
            self.applied.insert(spec.name.to_string(), (spec.clone(), made));
        }
        done
    }

    /// The file's own layout of a window that had been rewritten.
    fn restore(&mut self, menus: &mut [Menu], name: &str) {
        if let Some(orig) = self.orig.remove(&name.to_ascii_lowercase())
            && let Some(slot) = menus.iter_mut().find(|m| m.name == orig.name)
        {
            *slot = orig;
        }
    }
}

/// The windows the base era rewrites. `locked` is the era lock (client/era.rs `locked`); lifted, nothing is.
pub fn specs(locked: bool) -> Vec<Spec> {
    use super::magic::{Cat, cat_rows_all};
    let mut out = Vec::new();
    if !locked {
        return out;
    }
    // statcom2: Merit Points 7, Job Points 8, Unity 11, Master Levels 12, Alter Ego Points 13 (client/status.rs).
    out.push(Spec { name: super::status::STATCOM, rows: Rows::Chain(1), hidden: vec![7, 8, 11, 12, 13], clip: None });
    // abimenu / abiselec: the Mount row (child 6 / 5; Pet moves up under the others).
    for menu in ["menu    abimenu", "menu    abiselec"] {
        let rows = cat_rows_all(menu);
        let hidden: Vec<u16> = rows.iter().filter(|r| r.1 == Cat::Mount).map(|r| r.0).collect();
        out.push(Spec { name: menu, rows: Rows::Ids(rows.iter().map(|r| r.0).collect()), hidden, clip: None });
    }
    // quest00: Records of Eminence's rows and panel are not drawn (client/quests.rs), the frame ends under row 2.
    out.push(Spec { name: super::quests::CHOOSER, rows: Rows::Ids(Vec::new()), hidden: Vec::new(), clip: Some(super::quests::BASE_FRAME_H) });
    out
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::dat::ui::MenuElement;

    fn el(id: u16, y: i16, links: [u8; 6]) -> MenuElement {
        MenuElement { x: 7, y, w: 100, h: 20, head: [0; 32], id, links, refs: Vec::new(), strings: Default::default() }
    }

    /// Rows `ids` at y = 10 + 20k, wrapping up / down links (bytes 2 / 3, and 0 / 1 the same).
    fn menu(ids: &[u16], frame_h: u16, anchor: u8) -> Menu {
        let mut win = el(0, 100, [0; 6]);
        win.h = frame_h;
        win.head[0x13] = anchor;
        let mut elements = vec![win];
        let n = ids.len();
        for (k, &id) in ids.iter().enumerate() {
            let (up, down) = (ids[(k + n - 1) % n] as u8, ids[(k + 1) % n] as u8);
            elements.push(el(id, 10 + 20 * k as i16, [up, down, up, down, 0, 0]));
        }
        Menu { name: "menu    test".into(), elements }
    }

    fn view(m: &Menu) -> Vec<(u16, i16, [u8; 4])> {
        m.elements.iter().skip(1).map(|e| (e.id, e.y, [e.links[0], e.links[1], e.links[2], e.links[3]])).collect()
    }

    fn packed(p: Pack) -> Menu {
        match p {
            Pack::Packed(m) => m,
            other => panic!("{other:?}"),
        }
    }

    #[test]
    fn middle_rows_go_and_the_rest_slide_up() {
        // statcom2's order: rows 12, 11, 7 and 13 dropped from 1 2 12 3 4 11 7 13.
        let ids = [1u16, 2, 12, 3, 4, 11, 7, 13];
        let m = menu(&ids, 200, 0);
        let p = packed(repack(&m, &ids, &[12, 11, 7, 13]));
        // 1 2 3 4 take the first four places, no gap.
        let v = view(&p);
        assert_eq!(v.iter().map(|r| (r.0, r.1)).collect::<Vec<_>>(), [(1, 10), (2, 30), (3, 50), (4, 70)]);
        // The links wrap over the four: 1's up is 4 (it was 13), 4's down is 1 (it was 11).
        assert_eq!(v[0].2, [4, 2, 4, 2]);
        assert_eq!(v[1].2, [1, 3, 1, 3]);
        assert_eq!(v[3].2, [3, 1, 3, 1]);
        // The frame is four rows shorter; the window stays where it was.
        assert_eq!((p.elements[0].h, p.elements[0].y), (200 - 80, 100));
    }

    #[test]
    fn links_walk_every_dropped_row_in_a_run() {
        let ids = [1u16, 2, 3, 4, 5];
        let p = packed(repack(&menu(&ids, 150, 0), &ids, &[2, 3, 4]));
        let v = view(&p);
        assert_eq!(v, [(1, 10, [5, 5, 5, 5]), (5, 30, [1, 1, 1, 1])]);
    }

    #[test]
    fn a_chain_without_wrap_keeps_its_ends() {
        let ids = [1u16, 2, 3];
        let mut m = menu(&ids, 100, 0);
        // The file's ends do not wrap: 1 has no up, 3 no down.
        (m.elements[1].links[0], m.elements[1].links[2]) = (0xff, 0xff);
        (m.elements[3].links[1], m.elements[3].links[3]) = (0xff, 0xff);
        // Dropping the last row leaves the new last row with no down, as the file's last had none.
        let p = packed(repack(&m, &ids, &[3]));
        let v = view(&p);
        assert_eq!(v[0].2, [0xff, 2, 0xff, 2]);
        assert_eq!(v[1].2, [1, 0xff, 1, 0xff]);
    }

    #[test]
    fn the_last_row_going_just_shortens() {
        // Mount at the end, as in a menu whose dropped row sits last.
        let ids = [1u16, 2, 3];
        let p = packed(repack(&menu(&ids, 80, 0), &ids, &[3]));
        assert_eq!(view(&p).iter().map(|r| (r.0, r.1)).collect::<Vec<_>>(), [(1, 10), (2, 30)]);
        assert_eq!(p.elements[0].h, 60);
    }

    #[test]
    fn a_bottom_anchored_window_keeps_its_bottom_edge() {
        let ids = [1u16, 2, 3];
        let m = menu(&ids, 80, 2);
        let p = packed(repack(&m, &ids, &[2]));
        assert_eq!((p.elements[0].y, p.elements[0].h), (120, 60));
        // y + h is the same before and after: 100 + 80 against 120 + 60.
        assert_eq!(m.elements[0].y + m.elements[0].h as i16, p.elements[0].y + p.elements[0].h as i16);
    }

    #[test]
    fn nothing_to_drop_is_the_same_layout() {
        let ids = [1u16, 2, 3];
        assert!(matches!(repack(&menu(&ids, 80, 0), &ids, &[]), Pack::Same));
        // A dropped id the window does not list.
        assert!(matches!(repack(&menu(&ids, 80, 0), &ids, &[9]), Pack::Same));
    }

    #[test]
    fn a_layout_that_is_not_as_listed_is_refused() {
        let ids = [1u16, 2, 3];
        // A listed row the file lacks.
        assert!(matches!(repack(&menu(&[1, 2], 80, 0), &ids, &[2]), Pack::Refused(_)));
        // Rows out of list order (a second column).
        let mut m = menu(&ids, 80, 0);
        m.elements[2].y = 0;
        assert!(matches!(repack(&m, &ids, &[2]), Pack::Refused(_)));
        // Everything dropped.
        assert!(matches!(repack(&menu(&ids, 80, 0), &ids, &[1, 2, 3]), Pack::Refused(_)));
        // A frame shorter than the freed span.
        assert!(matches!(repack(&menu(&ids, 30, 0), &ids, &[1, 2]), Pack::Refused(_)));
    }

    #[test]
    fn the_chain_follows_the_down_links_once() {
        let m = menu(&[1, 2, 12, 3], 100, 0);
        assert_eq!(chain(&m, 1), [1, 2, 12, 3]);
        assert_eq!(chain(&m, 12), [12, 3, 1, 2]);
        assert_eq!(chain(&m, 99), Vec::<u16>::new());
        let p = apply(&m, &Spec { name: "x", rows: Rows::Chain(1), hidden: vec![12], clip: None });
        assert_eq!(view(&packed(p)).iter().map(|r| r.0).collect::<Vec<_>>(), [1, 2, 3]);
    }

    #[test]
    fn clip_shortens_the_frame_only() {
        let m = menu(&[1, 2], 200, 0);
        let p = packed(clip(&m, 78));
        assert_eq!(p.elements[0].h, 78);
        assert_eq!(view(&p), view(&m));
        assert!(matches!(clip(&m, 300), Pack::Same));
    }

    /// The Down and Up keys (status.rs: link bytes 3 and 2) around the re-packed window: every row left, once each, and
    /// back, with none of the dropped rows on the way; Up undoes Down.
    #[test]
    fn cursor_walks_exactly_the_rows_left() {
        // statcom2's own link order, its five later-era rows dropped.
        let ids = [1u16, 2, 12, 3, 4, 5, 6, 10, 11, 9, 7, 8, 13];
        let gone = [7u16, 8, 11, 12, 13];
        let p = packed(repack(&menu(&ids, 300, 0), &ids, &gone));
        let go = |from: u16, slot: usize| p.elements.iter().find(|e| e.id == from).unwrap().links[slot] as u16;
        let mut at = 1;
        let mut seen = vec![at];
        loop {
            at = go(at, 3);
            if at == 1 {
                break;
            }
            seen.push(at);
            assert!(seen.len() <= 8, "{seen:?}");
        }
        assert_eq!(seen, [1, 2, 3, 4, 5, 6, 10, 9]);
        for &id in &seen {
            assert_eq!(go(go(id, 3), 2), id);
            assert_eq!(go(go(id, 2), 3), id);
            assert!(!gone.contains(&go(id, 2)) && !gone.contains(&go(id, 3)));
        }
        // No gap: the rows are the first eight places, 20 apart.
        let ys: Vec<i16> = seen.iter().map(|&id| p.elements.iter().find(|e| e.id == id).unwrap().y).collect();
        assert_eq!(ys, (0..8).map(|k| 10 + 20 * k).collect::<Vec<i16>>());
    }

    fn same(a: &Menu, b: &Menu) -> bool {
        a.name == b.name && a.elements.len() == b.elements.len() && a.elements.iter().zip(&b.elements).all(|(x, y)| (x.id, x.x, x.y, x.w, x.h, x.head, x.links) == (y.id, y.x, y.y, y.w, y.h, y.head, y.links))
    }

    /// Lifting the lock puts back the file's own layout exactly; a spec made is not made twice; a refused layout stays.
    #[test]
    fn lifting_the_lock_restores_the_file() {
        let ids = [1u16, 2, 3, 4];
        let mut a = menu(&ids, 120, 2);
        a.name = "menu    a".into();
        let mut b = menu(&[1, 2], 80, 0);
        b.name = "menu    b".into();
        let (a0, b0) = (a.clone(), b.clone());
        let mut menus = vec![a, b];
        let spec = |name, hidden: Vec<u16>, rows: Vec<u16>| Spec { name, rows: Rows::Ids(rows), hidden, clip: None };
        let on = [spec("menu    a", vec![2, 3], ids.to_vec()), spec("menu    b", vec![9], vec![1, 2, 9])];
        let mut l = Layouts::default();
        // a is re-packed; b lacks the row 9 its code lists, so it is refused and left alone.
        assert_eq!(l.sync(&mut menus, &on), ["menu    a"]);
        assert!(!same(&menus[0], &a0));
        assert!(same(&menus[1], &b0));
        // The same asked again changes nothing (and still reports it).
        let packed_once = menus[0].clone();
        assert_eq!(l.sync(&mut menus, &on), ["menu    a"]);
        assert!(same(&menus[0], &packed_once));
        // Lifted: the file's own, exactly.
        assert!(l.sync(&mut menus, &[]).is_empty());
        assert!(same(&menus[0], &a0) && same(&menus[1], &b0));
        // On again from the restored layout is the same re-pack.
        assert_eq!(l.sync(&mut menus, &on), ["menu    a"]);
        assert!(same(&menus[0], &packed_once));
    }

    #[test]
    fn the_lock_off_asks_for_nothing_and_on_names_the_windows() {
        assert!(specs(false).is_empty());
        let names: Vec<&str> = specs(true).iter().map(|s| s.name).collect();
        assert_eq!(names, ["menu    statcom2", "menu    abimenu", "menu    abiselec", "menu    quest00"]);
        // The ability menus drop their Mount child (6 and 5).
        let hidden: Vec<Vec<u16>> = specs(true).iter().filter(|s| s.name.contains("abi")).map(|s| s.hidden.clone()).collect();
        assert_eq!(hidden, [vec![6], vec![5]]);
    }
}
