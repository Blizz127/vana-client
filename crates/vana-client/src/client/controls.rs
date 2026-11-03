//! Ours (not retail): the Controls choice of Settings. Three schemes for the keyboard and mouse, independent of the
//! interface style:
//!
//! - Modern: WASD and the mouse as in WoW (the default). W / S walk forward / back, A / D strafe (or turn: the "A / D"
//!   row), Q / E the other pair; the right button held is mouselook (the character faces where the camera looks and
//!   A / D / Q / E strafe), both buttons run forward, a right click on an actor interacts as Enter on the target does.
//!   Retail's compact keyboard (keyboard type 1 / 2) is off under it, so the other letters keep no retail function.
//! - FFXI WASD: retail's keyboard type 2 (compact keys, Q / E turn, Shift faces the camera) whatever the Config says.
//! - Original: retail's keyboard as the Config's Keyboard type sets it, nothing of ours on the keys.
//!
//! The mouse as before (left drag orbits the camera, the wheel zooms, a left click targets, a right drag looks, both
//! buttons run) is the same in all three. Modern's own: the keys, and the right click that interacts (the right button
//! then leaves the target as it is after a look drag; retail's right click clears it). The pure rules live here so they
//! can be tested without a window.

use std::time::Duration;

/// The Controls row's choices (config `controls`).
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Scheme {
    Original,
    FfxiWasd,
    Modern,
}

impl Scheme {
    pub fn from_config(v: u32) -> Self {
        match v {
            0 => Self::Original,
            1 => Self::FfxiWasd,
            _ => Self::Modern,
        }
    }

    /// The keyboard type (config 0x42: 0 full, 1 / 2 compact) the key functions run under. Modern turns the compact
    /// keyboard off (its own WASD replaces the compact stick); FFXI WASD is type 2; Original is what the Config says.
    pub fn keyboard_type(self, config: u32) -> u32 {
        match self {
            Self::Original => config,
            Self::FfxiWasd => 2,
            Self::Modern => 0,
        }
    }
}

/// The Modern keys held now, by role (their keys come from Key Assignment, see input.rs `modern_keys`).
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub struct Keys {
    /// W, S, A, D: the compact stick's up, down, left and right.
    pub fwd: bool,
    pub back: bool,
    pub left: bool,
    pub right: bool,
    /// Q and E: the type 2 turn keys.
    pub q: bool,
    pub e: bool,
}

/// What the Modern keys and buttons ask of the movement this frame: `ax` strafe (right positive), `ay` forward
/// (negative, as the movement axes are), `turn` the character's turn (right positive, as retail's 0xaa).
#[derive(Clone, Copy, Debug, Default, PartialEq)]
pub struct Intent {
    pub ax: f32,
    pub ay: f32,
    pub turn: f32,
}

/// The Modern scheme's movement. A / D strafe and Q / E turn, or with `ad_turn` the other way round. The right button
/// held (mouselook: the character already faces the camera) makes all four strafe, as WoW does. Both buttons run
/// forward.
pub fn intent(ad_turn: bool, k: Keys, left_button: bool, right_button: bool) -> Intent {
    let axis = |p: bool, n: bool| p as i32 as f32 - n as i32 as f32;
    let both = left_button && right_button;
    let (a_d, q_e) = (axis(k.right, k.left), axis(k.e, k.q));
    let (mut side, mut turn) = if ad_turn { (q_e, a_d) } else { (a_d, q_e) };
    if right_button {
        side += turn;
        turn = 0.0;
    }
    Intent { ax: side.clamp(-1.0, 1.0), ay: axis(k.back, k.fwd || both), turn }
}

/// A right button release that interacts rather than ends a mouselook: it moved less than a few pixels and was not
/// held long.
pub fn is_click(moved: f64, held: Option<Duration>) -> bool {
    moved < CLICK_MOVE && held.is_some_and(|h| h < CLICK_TIME)
}

/// Pixels of look motion, and time, below which a right button press and release is a click.
const CLICK_MOVE: f64 = 6.0;
const CLICK_TIME: Duration = Duration::from_millis(350);

/// The mouse buttons and where they went down (what the world's clicks and drags read).
#[derive(Default)]
pub struct Pointer {
    /// The left, right (a look drag, mouselook) and middle buttons.
    pub left: bool,
    pub right: bool,
    pub middle: bool,
    /// Where (and when) the left button went down, and the right one: the drag rule (FUN_10125040).
    pub press_at: Option<(f64, f64)>,
    pub press_time: Option<std::time::Instant>,
    pub right_press: Option<((f64, f64), std::time::Instant)>,
    /// Where the right button went down (the camera arrow's reference).
    pub drag_from: Option<(f64, f64)>,
    /// Look motion since the right button went down (pixels, or raw counts while the pointer is locked).
    pub right_moved: f64,
}

impl Pointer {
    pub fn any_down(&self) -> bool {
        self.left || self.right || self.middle
    }

    /// Focus changed: no button is held and no drag is under way (the window gets no releases while it is away, and a
    /// stale both-buttons state kept the character running).
    pub fn clear(&mut self) {
        *self = Self::default();
    }
}

/// Focus lost or gained: the buttons, the drag and the mouselook state all cleared. The caller gives the pointer back
/// (App::lose_focus).
pub fn lose_focus(ptr: &mut Pointer, mouse_look: &mut bool) {
    ptr.clear();
    *mouse_look = false;
}

#[cfg(test)]
mod tests {
    use super::*;

    fn k(s: &str) -> Keys {
        Keys { fwd: s.contains('w'), back: s.contains('s'), left: s.contains('a'), right: s.contains('d'), q: s.contains('q'), e: s.contains('e') }
    }

    #[test]
    fn schemes_and_keyboard_types() {
        assert_eq!((Scheme::from_config(0), Scheme::from_config(1), Scheme::from_config(2), Scheme::from_config(9)), (Scheme::Original, Scheme::FfxiWasd, Scheme::Modern, Scheme::Modern));
        // Original keeps the Config's type, FFXI WASD is 2, Modern leaves the compact keyboard off.
        for config in 0..3 {
            assert_eq!(Scheme::Original.keyboard_type(config), config);
            assert_eq!(Scheme::FfxiWasd.keyboard_type(config), 2);
            assert_eq!(Scheme::Modern.keyboard_type(config), 0);
        }
    }

    #[test]
    fn wasd_walks_and_strafes() {
        assert_eq!(intent(false, k(""), false, false), Intent::default());
        assert_eq!(intent(false, k("w"), false, false), Intent { ay: -1.0, ..Default::default() });
        assert_eq!(intent(false, k("s"), false, false), Intent { ay: 1.0, ..Default::default() });
        assert_eq!(intent(false, k("a"), false, false), Intent { ax: -1.0, ..Default::default() });
        assert_eq!(intent(false, k("wd"), false, false), Intent { ax: 1.0, ay: -1.0, turn: 0.0 });
        // Opposite keys cancel.
        assert_eq!(intent(false, k("ws"), false, false), Intent::default());
        assert_eq!(intent(false, k("ad"), false, false), Intent::default());
    }

    #[test]
    fn q_e_turn_unless_a_d_do() {
        // A / D strafe: Q / E turn (E right, as retail's 0xaa).
        assert_eq!(intent(false, k("e"), false, false), Intent { turn: 1.0, ..Default::default() });
        assert_eq!(intent(false, k("q"), false, false), Intent { turn: -1.0, ..Default::default() });
        // A / D turn: Q / E strafe.
        assert_eq!(intent(true, k("d"), false, false), Intent { turn: 1.0, ..Default::default() });
        assert_eq!(intent(true, k("a"), false, false), Intent { turn: -1.0, ..Default::default() });
        assert_eq!(intent(true, k("q"), false, false), Intent { ax: -1.0, ..Default::default() });
        assert_eq!(intent(true, k("e"), false, false), Intent { ax: 1.0, ..Default::default() });
        // Turning while walking forward is both at once.
        assert_eq!(intent(true, k("wd"), false, false), Intent { ay: -1.0, turn: 1.0, ..Default::default() });
    }

    #[test]
    fn mouselook_strafes_with_all_four_keys() {
        for ad_turn in [false, true] {
            assert_eq!(intent(ad_turn, k("a"), false, true), Intent { ax: -1.0, ..Default::default() });
            assert_eq!(intent(ad_turn, k("d"), false, true), Intent { ax: 1.0, ..Default::default() });
            assert_eq!(intent(ad_turn, k("q"), false, true), Intent { ax: -1.0, ..Default::default() });
            assert_eq!(intent(ad_turn, k("e"), false, true), Intent { ax: 1.0, ..Default::default() });
            // Never past full: A and Q together are one strafe.
            assert_eq!(intent(ad_turn, k("aq"), false, true).ax, -1.0);
            assert_eq!(intent(ad_turn, k("w"), false, true).turn, 0.0);
        }
    }

    #[test]
    fn both_buttons_run_forward() {
        assert_eq!(intent(false, k(""), true, true), Intent { ay: -1.0, ..Default::default() });
        assert_eq!(intent(false, k(""), true, false), Intent::default());
        assert_eq!(intent(false, k(""), false, true), Intent::default());
        // Back against both buttons stands still; W with them is still forward.
        assert_eq!(intent(false, k("s"), true, true).ay, 0.0);
        assert_eq!(intent(false, k("w"), true, true).ay, -1.0);
        assert_eq!(intent(false, k("a"), true, true), Intent { ax: -1.0, ay: -1.0, turn: 0.0 });
    }

    #[test]
    fn a_right_click_is_short_and_still() {
        let ms = Duration::from_millis;
        assert!(is_click(0.0, Some(ms(80))));
        assert!(is_click(5.9, Some(ms(300))));
        assert!(!is_click(6.0, Some(ms(80))));
        assert!(!is_click(0.0, Some(ms(350))));
        assert!(!is_click(0.0, Some(ms(900))));
        // Never pressed in the window (a release alone).
        assert!(!is_click(0.0, None));
    }

    #[test]
    fn focus_loss_clears_buttons_and_mouselook() {
        let now = std::time::Instant::now();
        let mut p = Pointer {
            left: true,
            right: true,
            middle: true,
            press_at: Some((1.0, 2.0)),
            press_time: Some(now),
            right_press: Some(((3.0, 4.0), now)),
            drag_from: Some((3.0, 4.0)),
            right_moved: 40.0,
        };
        let mut look = true;
        assert!(p.any_down());
        lose_focus(&mut p, &mut look);
        assert!(!p.any_down() && !look);
        assert!(p.press_at.is_none() && p.press_time.is_none() && p.right_press.is_none() && p.drag_from.is_none());
        assert_eq!(p.right_moved, 0.0);
        // With nothing held the Modern intent is the idle one: no stuck run.
        assert_eq!(intent(false, Keys::default(), p.left, p.right), Intent::default());
    }
}
