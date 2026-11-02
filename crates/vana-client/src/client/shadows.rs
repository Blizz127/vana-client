//! Retail's actor ground shadows, the CPU half (render/shadow.rs draws them; MODLOG "Actor ground shadows"): which
//! actors cast and how (FUN_100c9da0's mode gate, config 0x3a), a light-state slot per caster, the silhouette layers.

use super::ground::Ground;
use crate::render::shadow::MAX_CASTERS;
use glam::Vec3;
use std::collections::{HashMap, HashSet};

/// What the actor loop gathers per drawn skinned actor: its drawn position, box corners (world), the farthest
/// corner's view depth.
#[derive(Clone, Copy)]
pub struct Seen {
    pub pos: Vec3,
    pub corners: [Vec3; 8],
    pub depth: f32,
}

/// Each caster's light-state slot (render/shadow.rs `state`), freed when it stops casting.
#[derive(Default)]
pub struct Slots {
    by_id: HashMap<u32, u32>,
}

impl Slots {
    /// This frame's casters keep their slots; new ones take a free one (fresh); the rest are freed.
    fn assign(&mut self, ids: &[u32]) -> Vec<(u32, bool)> {
        self.by_id.retain(|id, _| ids.contains(id));
        let mut used: Vec<bool> = vec![false; MAX_CASTERS];
        for &s in self.by_id.values() {
            used[s as usize] = true;
        }
        ids.iter()
            .map(|id| match self.by_id.get(id) {
                Some(&s) => (s, false),
                None => {
                    let s = used.iter().position(|u| !u).unwrap_or(0) as u32;
                    used[s as usize] = true;
                    self.by_id.insert(*id, s);
                    (s, true)
                }
            })
            .collect()
    }
}

/// The view depth at which a blob turns into the quad (retail's 20), and the one the quad goes back to the blob
/// under. Retail tests a bare `depth >= 20` every frame; an actor standing near 20 (its skeleton box's farthest
/// corner moves with every animation frame, and the camera turns) then swapped between the small blob and the quad
/// twice its width from one frame to the next. *(ours: a 2-yalm band, no retail equivalent)*
pub const FAR_DEPTH: f32 = 20.0;
pub const NEAR_DEPTH: f32 = 18.0;

/// The casters in the quad's range: past `FAR_DEPTH`, until back under `NEAR_DEPTH`. *(ours, see above)*
#[derive(Default)]
pub struct Far {
    ids: HashSet<u32>,
}

impl Far {
    /// Whether `id` at view `depth` is far this frame; remembered for the next.
    pub fn test(&mut self, id: u32, depth: f32) -> bool {
        let far = depth >= FAR_DEPTH || (depth >= NEAR_DEPTH && self.ids.contains(&id));
        if far {
            self.ids.insert(id);
        } else {
            self.ids.remove(&id);
        }
        far
    }

    /// Forgets the actors not seen this frame.
    fn keep(&mut self, seen: &HashMap<u32, Seen>) {
        self.ids.retain(|id| seen.contains_key(id));
    }
}

/// FUN_100c9da0's mode: 1 silhouette, 0 projected blob (2, the quad, when `far`: past view depth 20), 2 quad, None
/// no shadow. What the mode gate reads of the world: the ground, config 0x3a (0 Normal, 1 Off, 2 High), our id, the zone,
/// whether an actor exists, an actor's no-shadow / no-blob latches, and the silhouette layers this frame can have.
pub struct Ctx<'a> {
    pub ground: &'a Ground,
    pub setting: u32,
    pub me: u32,
    pub zone: u16,
    pub has: &'a dyn Fn(u32) -> bool,
    pub flags: &'a dyn Fn(u32) -> (bool, bool),
    pub layers: u32,
}

pub fn mode(c: &Ctx, id: u32, s: &Seen, eye: Vec3, far: bool) -> Option<u8> {
    use super::chair::CHAIR;
    use super::fishrod::ROD;
    use super::indi::AURA;
    use super::ride::ANIMAL;
    let (kind, covered) = c.ground.surface(s.pos);
    let (off, noblob) = (c.flags)(id);
    // Al'Taieu's surfaces 8 / 9, +0x66c 0, and an actor's feet more than 2 above the eye.
    if (c.zone == 33 && matches!(kind, 8 | 9)) || off || c.setting == 1 || s.pos.y - eye.y < -2.0 {
        return None;
    }
    // +0x670 drops the blobs (modes 0 / 2), not the silhouette.
    let blob = || (!noblob).then_some(if covered || far { 2 } else { 0 });
    if c.setting == 2 {
        return Some(1);
    }
    let me = c.me;
    match id {
        // Ours: the silhouette, or our mount's while riding.
        _ if id == me => (!(c.has)(me | ANIMAL)).then_some(1),
        // FUN_100cbde0: our chair a silhouette, others' chairs none.
        _ if id == me | ANIMAL || id == me | ROD || id == me | CHAIR => Some(1),
        _ if id & (ROD | AURA | CHAIR) != 0 => None,
        _ if id & ANIMAL != 0 => blob(),
        // Others' riders have none.
        _ if (c.has)(id | ANIMAL) => None,
        _ => blob(),
    }
}

/// This frame's casters among the drawn actors `seen`: (id, mode, what was seen), ours first then nearest, the
/// silhouettes past the layers turned to blobs.
pub fn modes(c: &Ctx, far: &mut Far, seen: &HashMap<u32, Seen>, eye: Vec3) -> Vec<(u32, u8, Seen)> {
    far.keep(seen);
    // Every seen actor takes its turn through `far`, shadow or not, so its band memory is current.
    let tested: Vec<(u32, bool, &Seen)> = seen.iter().map(|(&id, s)| (id, far.test(id, s.depth), s)).collect();
    let mut list: Vec<(u32, u8, Seen)> = tested.into_iter().filter_map(|(id, f, s)| Some((id, mode(c, id, s, eye, f)?, *s))).collect();
    list.sort_by(|a, b| (a.0 != c.me).cmp(&(b.0 != c.me)).then(a.2.pos.distance(eye).total_cmp(&b.2.pos.distance(eye))));
    list.truncate(MAX_CASTERS);
    let mut layer = 0u32;
    for (id, m, s) in &mut list {
        if *m == 1 {
            if layer < c.layers {
                layer += 1;
            } else {
                let (_, covered) = c.ground.surface(s.pos);
                *m = if (c.flags)(*id).1 { 3 } else if covered || far.ids.contains(id) { 2 } else { 0 };
            }
        }
    }
    list.retain(|l| l.1 != 3);
    list
}

/// The casters to draw: `modes` of the actors drawn this frame (`actors`), their light slots and layers.
pub fn casters<'a>(slots: &mut Slots, ground: &Ground, modes: Vec<(u32, u8, Seen)>, actors: &HashMap<u32, &'a crate::render::ActorGpu>) -> Vec<crate::render::shadow::Caster<'a>> {
    let list: Vec<(u32, u8, Seen)> = modes.into_iter().filter(|m| actors.contains_key(&m.0)).collect();
    let ids: Vec<u32> = list.iter().map(|l| l.0).collect();
    let slots = slots.assign(&ids);
    let mut next_layer = 0u32;
    list.into_iter()
        .zip(slots)
        .map(|((id, m, s), (state, fresh))| {
            let layer = if m == 1 {
                next_layer += 1;
                next_layer - 1
            } else {
                0
            };
            crate::render::shadow::Caster {
                mode: m,
                pos: s.pos,
                corners: s.corners,
                lights: actors.get(&id).map_or([0; 4], |a| a.lights),
                state,
                fresh,
                cells: (m != 2).then(|| ground.decal_range(s.pos)).flatten(),
                actor: if m == 1 { actors.get(&id).copied() } else { None },
                layer,
            }
        })
        .collect()
}

/// "system  kage_tex" from file 0x1b8c (ROM/27/81: folder `maru`, image `kage`).
pub fn kage_texture(index: &crate::dat::DatIndex) -> Option<crate::dat::zone::Texture> {
    let bytes = index.read(0x1b8c).ok()?;
    let chunks = crate::dat::chunks(&bytes).ok()?;
    chunks.iter().filter(|c| c.kind == 0x20).filter_map(|c| crate::dat::zone::parse_img(c.data).ok()).find(|t| t.name.trim().ends_with("kage_tex")).or_else(|| chunks.iter().filter(|c| c.kind == 0x20).find_map(|c| crate::dat::zone::parse_img(c.data).ok()))
}

#[cfg(test)]
mod tests {
    use super::{Far, Seen, Slots};
    use glam::Vec3;
    use std::collections::HashMap;

    /// Retail's bare `depth >= 20` swaps the blob and the quad on every wobble around 20; ours turns far at 20 and
    /// back only under 18.
    #[test]
    fn far_band() {
        let mut f = Far::default();
        assert!(!f.test(1, 19.9));
        assert!(f.test(1, 20.0));
        // Wobbling inside the band keeps the quad.
        assert!(f.test(1, 19.5) && f.test(1, 18.0) && f.test(1, 19.99));
        assert!(!f.test(1, 17.99));
        // Back near, it needs 20 again.
        assert!(!f.test(1, 19.9) && f.test(1, 20.1));
        // An actor starting inside the band is near (it was never far); each id has its own memory.
        assert!(!f.test(2, 19.0) && f.test(1, 19.0));
    }

    #[test]
    fn far_forgets_unseen() {
        let mut f = Far::default();
        assert!(f.test(7, 25.0));
        let seen: HashMap<u32, Seen> = HashMap::from([(8, Seen { pos: Vec3::ZERO, corners: [Vec3::ZERO; 8], depth: 0.0 })]);
        f.keep(&seen);
        // 7 went out of sight: back to the blob until 20.
        assert!(!f.test(7, 19.0));
    }

    #[test]
    fn slots_kept_and_freed() {
        let mut s = Slots::default();
        assert_eq!(s.assign(&[7, 9]), vec![(0, true), (1, true)]);
        // 7 keeps its slot, 9's is freed and taken by 11.
        assert_eq!(s.assign(&[7, 11]), vec![(0, false), (1, true)]);
        assert_eq!(s.assign(&[11]), vec![(1, false)]);
    }
}
