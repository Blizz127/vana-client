//! Gamepad support: gilrs (Linux evdev, Windows Gaming Input) read once a frame and turned into what the keyboard
//! already does. Nothing here has logic of its own: a button is a key event or a held DIK key (the same state the
//! window's keys feed, client/input.rs), a stick is an axis the key functions' movement and camera read. With no pad
//! connected, or the setting off, nothing changes.
//!
//! The default layout follows retail's PC gamepad as far as the client's own key functions go. Only the layout of
//! retail's pad block (FUN_1011fbc0's compact records, the Config's Gamepad row) is sourced; which button reaches which
//! key is a choice and marked *(inferred)* in MODLOG.md.
//!
//! | Button            | In the field                       | In a window / menu / event | In a text field        |
//! |-------------------|------------------------------------|----------------------------|------------------------|
//! | Left stick        | move                               | cursor (as the D-pad)      | caret (as the D-pad)   |
//! | Right stick       | camera                             | -                          | -                      |
//! | D-pad             | left / right: previous / next target (Shift+Tab / Tab), up: ourselves (F1), down: the one-button rotation (/rotation) | arrows | arrows (caret, history) |
//! | A / Cross         | Enter: talk, confirm, action menu  | Enter                      | Enter (send)           |
//! | B / Circle        | Escape: cancel, clear target       | Escape                     | Escape                 |
//! | X / Square        | main menu (-)                      | -                          | Backspace              |
//! | Y / Triangle      | Num*: lock-on / heal               | Num*                       | Space                  |
//! | LB / RB           | Num+ (log / window view), Num- (page) | the same                | -                      |
//! | LT / RT (held)    | Ctrl / Alt: the macro palettes     | the same                   | the same               |
//! | Select / Back     | Space: open the chat line          | -                          | Tab (auto-translate)   |
//! | Start             | Pause: the log-out prompt          | - (main menu)              | on-screen keyboard     |
//! | Left stick click  | Num/: walk / run                   | -                          | -                      |
//! | Right stick click | the /map command (opens the map)   | the map up: Escape (closes it); the battle menu up: /rotation | - |
//!
//! While LT or RT is held the D-pad and A / B work the palette (Left / Right the cell, Up / Down the set, A runs it,
//! B closes it), which is the client's own palette code reading the arrows, Enter and Escape.
//!
//! While the built-in on-screen keyboard (client/osk.rs) is up it has the pad whole (`Ctx::Osk`, `osk_binding`): the
//! D-pad and left stick move its cursor, A types the key under it, B is Backspace (repeating), X Space, Y turns the key
//! page, Start sends Enter to the field, Select closes it. With it closed over a text field, Start brings it back.
//!
//! The character-creation name entry is a text field too (`Ctx::Name`): X is Backspace there, and LB keeps its retail
//! Num+ (the random name), which the other text fields drop. With the map window up (`Ctx::Map`) the right stick is its
//! zoom (up zooms in; `Out.zoom`, read only as axis 0x7c, never by the camera) and the buttons are a window's.
//!
//! D-pad Down in the field had nothing in the client: it runs /rotation (ours, client/rotation.rs), as R3 does with the
//! battle menu up (the D-pad is its cursor there). Unbound: key functions 0xb7..0xba (the second pad
//! word, inferred to be the gamepad) are not wired.

use egui::{Event, Key, Modifiers};

/// Stick defaults (config `gamepad_deadzone`, `gamepad_camera_speed`).
pub const DEFAULT_DEADZONE: f32 = 0.2;
pub const DEFAULT_CAMERA_SPEED: f32 = 1.0;
/// The deadzone's bounds: a hand-edited config cannot make the rescale divide by zero.
pub const MAX_DEADZONE: f32 = 0.8;
/// Raw stick length that counts as fully pushed. Worn sticks and some pads top out near 0.9; the movement code only
/// runs at more than 0.9, so a plain `(m - dz) / (1 - dz)` would walk forever there.
const SATURATION: f32 = 0.95;
/// A stick as a D-pad (menus), after its deadzone.
const STICK_AS_DPAD: f32 = 0.6;
/// A trigger read as a button.
const TRIGGER: f32 = 0.5;
/// OS-style key repeat of the arrows, in seconds (retail repeats after 18 ticks, then every 4: input.rs).
const REPEAT_DELAY: f32 = 0.3;
const REPEAT_EVERY: f32 = 0.07;

/// The pad's buttons by place, as gilrs names them (South is A on an Xbox pad, Cross on a PlayStation one).
#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub enum Btn {
    South,
    East,
    West,
    North,
    LeftBumper,
    RightBumper,
    LeftTrigger,
    RightTrigger,
    Select,
    Start,
    LeftThumb,
    RightThumb,
    DPadUp,
    DPadDown,
    DPadLeft,
    DPadRight,
}

/// Every button; `Snapshot` and the mapper index by a button's place here (`Btn as usize`, kept in step by a test).
pub const BUTTONS: [Btn; 16] = [
    Btn::South,
    Btn::East,
    Btn::West,
    Btn::North,
    Btn::LeftBumper,
    Btn::RightBumper,
    Btn::LeftTrigger,
    Btn::RightTrigger,
    Btn::Select,
    Btn::Start,
    Btn::LeftThumb,
    Btn::RightThumb,
    Btn::DPadUp,
    Btn::DPadDown,
    Btn::DPadLeft,
    Btn::DPadRight,
];

/// What the game around the pad is doing this frame.
#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub enum Ctx {
    /// Walking about: no window has the keys.
    Field,
    /// A window, menu, event or the login / lobby screens.
    Menu,
    /// Only the action menu (playermo) is up, as it is all through a fight: its keys are the Menu's, but the sticks
    /// still walk and turn the camera, as the keyboard's movement keys do.
    Action,
    /// A text field has the keys (the chat line, the login's fields).
    Typing,
    /// The character-creation name entry: a text field (Typing's buttons) that also keeps LB's random name (Num+, as
    /// retail's key function does there), which no other text field has.
    Name,
    /// The map window is up: a window (Menu's buttons) whose right stick zooms and whose R3 closes it.
    Map,
    /// Our own on-screen keyboard (client/osk.rs) is up over a text field and takes the pad whole: every button is
    /// one of its keys (see `osk_binding`), nothing reaches the game, no DIK is held and the sticks do not walk.
    Osk,
}

/// What a button does: an egui key event (for the windows, which read those), DIK keys held while it is down (for the
/// key functions), and the text a typed key also sends.
#[derive(Clone, Copy, PartialEq, Debug)]
pub struct Binding {
    pub key: Option<Key>,
    pub dik: &'static [u8],
    /// The key repeats while held, as the OS repeats a held key. Only the arrows: Enter, Escape and the rest act once.
    pub repeat: bool,
    pub text: Option<&'static str>,
    /// A chat command the press runs (R3: /map).
    pub command: Option<&'static str>,
}

const DIK_ENTER: u8 = 0x1c;
const DIK_ESCAPE: u8 = 0x01;
const DIK_MINUS: u8 = 0x0c;
const DIK_BACKSPACE: u8 = 0x0e;
const DIK_TAB: u8 = 0x0f;
const DIK_SHIFT: u8 = 0x2a;
const DIK_CTRL: u8 = 0x1d;
const DIK_ALT: u8 = 0x38;
const DIK_SPACE: u8 = 0x39;
const DIK_F1: u8 = 0x3b;
const DIK_NUM_MUL: u8 = 0x37;
const DIK_NUM_MINUS: u8 = 0x4a;
const DIK_NUM_PLUS: u8 = 0x4e;
const DIK_NUM_DIV: u8 = 0xb5;
const DIK_PAUSE: u8 = 0xc5;
const DIK_UP: u8 = 0xc8;
const DIK_LEFT: u8 = 0xcb;
const DIK_RIGHT: u8 = 0xcd;
const DIK_DOWN: u8 = 0xd0;

const fn bind(key: Option<Key>, dik: &'static [u8]) -> Option<Binding> {
    Some(Binding { key, dik, repeat: false, text: None, command: None })
}

const fn arrow(key: Key, dik: &'static [u8]) -> Option<Binding> {
    Some(Binding { key: Some(key), dik, repeat: true, text: None, command: None })
}

/// The on-screen keyboard's buttons (`Ctx::Osk`). The keys are the keyboard's own vocabulary, not the game's: the
/// events go to the keyboard (client/osk.rs `pad_event`), never into the window's input. D-pad: Arrow keys (move the
/// cursor, repeating); A Enter (type the key under the cursor); B Backspace (repeating); X Space; Y Tab (the next key
/// page); Start F2 (send Enter to the field); Select Escape (close the keyboard).
fn osk_binding(b: Btn) -> Option<Binding> {
    use Btn::*;
    match b {
        South => bind(Some(Key::Enter), &[]),
        East => arrow(Key::Backspace, &[]),
        West => bind(Some(Key::Space), &[]),
        North => bind(Some(Key::Tab), &[]),
        Start => bind(Some(Key::F2), &[]),
        Select => bind(Some(Key::Escape), &[]),
        DPadUp => arrow(Key::ArrowUp, &[]),
        DPadDown => arrow(Key::ArrowDown, &[]),
        DPadLeft => arrow(Key::ArrowLeft, &[]),
        DPadRight => arrow(Key::ArrowRight, &[]),
        _ => None,
    }
}

/// The default mapping (the table in the module docs).
pub fn binding(b: Btn, ctx: Ctx) -> Option<Binding> {
    use Btn::*;
    if ctx == Ctx::Osk {
        return osk_binding(b);
    }
    // R3: the retail "/map" command (the client has it: textcmd.rs MAP, which opens the map window) walking about, and
    // Escape (the map's own close key) with the map up, so it toggles it.
    if b == RightThumb {
        return match ctx {
            Ctx::Field => Some(Binding { key: None, dik: &[], repeat: false, text: None, command: Some("/map") }),
            Ctx::Map => bind(Some(Key::Escape), &[DIK_ESCAPE]),
            // Ours: with the battle menu up the D-pad is its cursor, so R3 is the one-button rotation there.
            Ctx::Action => Some(Binding { key: None, dik: &[], repeat: false, text: None, command: Some("/rotation") }),
            _ => None,
        };
    }
    let ctx = if matches!(ctx, Ctx::Action | Ctx::Map) { Ctx::Menu } else { ctx };
    let typing = matches!(ctx, Ctx::Typing | Ctx::Name);
    match (b, ctx) {
        (South, _) => bind(Some(Key::Enter), &[DIK_ENTER]),
        (East, _) => bind(Some(Key::Escape), &[DIK_ESCAPE]),
        (West, Ctx::Typing | Ctx::Name) => bind(Some(Key::Backspace), &[DIK_BACKSPACE]),
        (West, _) => bind(Some(Key::Minus), &[DIK_MINUS]),
        (North, Ctx::Typing | Ctx::Name) => Some(Binding { key: Some(Key::Space), dik: &[DIK_SPACE], repeat: false, text: Some(" "), command: None }),
        (North, _) => bind(None, &[DIK_NUM_MUL]),
        // The name entry's random name (Num+, mod.rs creator step 5) is the one bumper a text field keeps.
        (LeftBumper, Ctx::Name) => bind(None, &[DIK_NUM_PLUS]),
        (LeftBumper, _) if !typing => bind(None, &[DIK_NUM_PLUS]),
        (RightBumper, _) if !typing => bind(None, &[DIK_NUM_MINUS]),
        // The palette modifiers: held, they are Ctrl / Alt, and the client opens palette 1 / 2 itself.
        (LeftTrigger, _) => bind(None, &[DIK_CTRL]),
        (RightTrigger, _) => bind(None, &[DIK_ALT]),
        (Select, Ctx::Field) => Some(Binding { key: Some(Key::Space), dik: &[DIK_SPACE], repeat: false, text: Some(" "), command: None }),
        (Select, Ctx::Typing | Ctx::Name) => bind(Some(Key::Tab), &[DIK_TAB]),
        (Start, Ctx::Field) => bind(None, &[DIK_PAUSE]),
        (Start, Ctx::Menu) => bind(Some(Key::Minus), &[DIK_MINUS]),
        (LeftThumb, Ctx::Field) => bind(None, &[DIK_NUM_DIV]),
        (DPadLeft, Ctx::Field) => bind(None, &[DIK_SHIFT, DIK_TAB]),
        (DPadRight, Ctx::Field) => bind(None, &[DIK_TAB]),
        (DPadUp, Ctx::Field) => bind(None, &[DIK_F1]),
        (DPadUp, _) => arrow(Key::ArrowUp, &[DIK_UP]),
        // Ours: the one-button rotation (client/rotation.rs).
        (DPadDown, Ctx::Field) => Some(Binding { key: None, dik: &[], repeat: false, text: None, command: Some("/rotation") }),
        (DPadDown, _) => arrow(Key::ArrowDown, &[DIK_DOWN]),
        (DPadLeft, _) => arrow(Key::ArrowLeft, &[DIK_LEFT]),
        (DPadRight, _) => arrow(Key::ArrowRight, &[DIK_RIGHT]),
        _ => None,
    }
}

/// A radial deadzone with rescale: nothing inside `dz`, then the length grows from 0 to 1 by `SATURATION` of the raw
/// push (the direction is kept; a square pad's corners do not run faster).
pub fn deadzone(x: f32, y: f32, dz: f32) -> (f32, f32) {
    let dz = if dz.is_finite() { dz.clamp(0.0, MAX_DEADZONE) } else { DEFAULT_DEADZONE };
    let m = x.hypot(y);
    if !m.is_finite() || m <= dz || m == 0.0 {
        return (0.0, 0.0);
    }
    let scaled = ((m - dz) / (SATURATION - dz)).clamp(0.0, 1.0);
    (x / m * scaled, y / m * scaled)
}

/// The movement axes (4 X, 5 Y, FUN_1011fe30: X right, Y positive backward) from the left stick (gilrs: y up).
pub fn stick_to_move(x: f32, y_up: f32, dz: f32) -> (f32, f32) {
    let (x, y) = deadzone(x, y_up, dz);
    (x, -y)
}

/// The camera axes (6 X right, 7 Y positive down, as the arrow keys give them) from the right stick; `speed` scales
/// them after the deadzone (config `gamepad_camera_speed`).
pub fn stick_to_camera(x: f32, y_up: f32, dz: f32, speed: f32) -> (f32, f32) {
    let speed = if speed.is_finite() { speed.clamp(0.1, 5.0) } else { DEFAULT_CAMERA_SPEED };
    let (x, y) = deadzone(x, y_up, dz);
    (x * speed, -y * speed)
}

/// What a frame reads off the pad.
#[derive(Clone, Copy, Debug, Default, PartialEq)]
pub struct Snapshot {
    pub buttons: [bool; BUTTONS.len()],
    /// Raw sticks, y up (gilrs).
    pub left: (f32, f32),
    pub right: (f32, f32),
}

impl Snapshot {
    pub fn set(&mut self, b: Btn, on: bool) {
        self.buttons[b as usize] = on;
    }

    pub fn get(&self, b: Btn) -> bool {
        self.buttons[b as usize]
    }
}

/// The settings that shape the sticks.
#[derive(Clone, Copy, Debug)]
pub struct Tuning {
    pub deadzone: f32,
    pub camera_speed: f32,
}

impl Default for Tuning {
    fn default() -> Self {
        Self { deadzone: DEFAULT_DEADZONE, camera_speed: DEFAULT_CAMERA_SPEED }
    }
}

/// One frame's output: the egui events for the windows, the DIK keys held for the key functions, the sticks for the
/// movement and camera axes (move x / y, camera x / y) and whether a button went down.
#[derive(Default, Debug)]
pub struct Out {
    pub events: Vec<Event>,
    pub keys: Vec<u8>,
    pub sticks: [f32; 4],
    pub pressed: bool,
    /// Start was pressed over a text field: bring the on-screen keyboard back (Select closed it).
    pub open_osk: bool,
    /// Chat commands to run (R3's /map).
    pub commands: Vec<&'static str>,
    /// The map's zoom axis (the right stick's Y, negative zooms in), with the map up.
    pub zoom: f32,
}

/// Turns snapshots into events and held keys, tracking what is down. A button keeps the binding it was pressed with
/// until it is released, so a window opening under a held button does not change its key.
#[derive(Default)]
pub struct Mapper {
    bound: [Option<Binding>; BUTTONS.len()],
    down: [bool; BUTTONS.len()],
    held_for: [f32; BUTTONS.len()],
}

fn key_event(key: Key, pressed: bool, repeat: bool) -> Event {
    Event::Key { key, physical_key: None, pressed, repeat, modifiers: Modifiers::NONE }
}

impl Mapper {
    /// `dt` in seconds. A default snapshot (no pad, unplugged, window unfocused) releases everything held.
    pub fn step(&mut self, s: &Snapshot, ctx: Ctx, tuning: Tuning, dt: f32) -> Out {
        let mut out = Out::default();
        let mut now = s.buttons;
        // A held trigger is a palette: the D-pad works it with arrows, and the character stands (Ctrl / Alt held
        // take no movement keys either).
        let palette = s.get(Btn::LeftTrigger) || s.get(Btn::RightTrigger);
        if ctx == Ctx::Map {
            // Over the map the right stick zooms (stick up: in), at the camera's deadzone but not its speed.
            out.zoom = stick_to_camera(s.right.0, s.right.1, tuning.deadzone, 1.0).1;
        }
        let walks = matches!(ctx, Ctx::Field | Ctx::Action) && !palette;
        let ctx = if matches!(ctx, Ctx::Field | Ctx::Action) && palette { Ctx::Menu } else { ctx };
        if !walks {
            // The left stick walks no longer; it moves the cursor.
            let (x, y) = deadzone(s.left.0, s.left.1, tuning.deadzone);
            for (b, on) in [(Btn::DPadLeft, x <= -STICK_AS_DPAD), (Btn::DPadRight, x >= STICK_AS_DPAD), (Btn::DPadUp, y >= STICK_AS_DPAD), (Btn::DPadDown, y <= -STICK_AS_DPAD)] {
                now[b as usize] |= on;
            }
        } else {
            let (mx, my) = stick_to_move(s.left.0, s.left.1, tuning.deadzone);
            let (cx, cy) = stick_to_camera(s.right.0, s.right.1, tuning.deadzone, tuning.camera_speed);
            out.sticks = [mx, my, cx, cy];
        }
        for (i, &b) in BUTTONS.iter().enumerate() {
            match (now[i], self.down[i]) {
                (true, false) => {
                    self.down[i] = true;
                    self.held_for[i] = 0.0;
                    self.bound[i] = binding(b, ctx);
                    if b == Btn::Start && matches!(ctx, Ctx::Typing | Ctx::Name) {
                        out.open_osk = true;
                        out.pressed = true;
                    }
                    if let Some(bd) = self.bound[i] {
                        out.pressed = true;
                        if let Some(k) = bd.key {
                            out.events.push(key_event(k, true, false));
                        }
                        if let Some(t) = bd.text {
                            out.events.push(Event::Text(t.to_string()));
                        }
                        if let Some(c) = bd.command {
                            out.commands.push(c);
                        }
                    }
                }
                (false, true) => {
                    self.down[i] = false;
                    if let Some(Binding { key: Some(k), .. }) = self.bound[i].take() {
                        out.events.push(key_event(k, false, false));
                    }
                }
                (true, true) => {
                    if let Some(Binding { key: Some(k), repeat: true, .. }) = self.bound[i] {
                        let before = self.held_for[i];
                        self.held_for[i] += dt;
                        let fires = |t: f32| if t < REPEAT_DELAY { 0 } else { ((t - REPEAT_DELAY) / REPEAT_EVERY) as u32 + 1 };
                        for _ in fires(before)..fires(self.held_for[i]) {
                            out.events.push(key_event(k, true, true));
                        }
                    }
                }
                (false, false) => {}
            }
        }
        for bd in self.bound.iter().flatten() {
            for &k in bd.dik {
                if !out.keys.contains(&k) {
                    out.keys.push(k);
                }
            }
        }
        out
    }

    /// Whether any button is held (tests).
    #[cfg(test)]
    pub fn any_down(&self) -> bool {
        self.down.iter().any(|&d| d)
    }
}

/// The gilrs side: finds the pads, follows plugs and unplugs, reads the one in use. Not exercised by the tests (no
/// hardware): everything after `Snapshot` is.
#[derive(Default)]
pub struct Pads {
    gilrs: Option<gilrs::Gilrs>,
    /// Starting gilrs failed once (logged); not tried again.
    failed: bool,
    active: Option<gilrs::GamepadId>,
    mapper: Mapper,
    /// The last thing used was the pad (a button went down) rather than the keyboard or mouse.
    used: bool,
}

impl Pads {
    /// Whether the pad was the last device used: text fields raise the on-screen keyboard only then.
    pub fn in_use(&self) -> bool {
        self.used
    }

    /// The keyboard or mouse was used.
    pub fn other_input(&mut self) {
        self.used = false;
    }

    /// One frame: reads the pad (`enabled` off drops gilrs altogether; an unfocused window reads nothing, as the pad
    /// reports even when another window has the focus) and maps it.
    pub fn frame(&mut self, enabled: bool, focused: bool, ctx: Ctx, tuning: Tuning, dt: f32) -> Out {
        let snap = if enabled { self.read(focused) } else { self.stop() };
        let out = self.mapper.step(&snap, ctx, tuning, dt);
        if out.pressed {
            self.used = true;
        }
        out
    }

    fn stop(&mut self) -> Snapshot {
        if self.gilrs.take().is_some() {
            log::info!("gamepad: off");
        }
        self.active = None;
        Snapshot::default()
    }

    fn read(&mut self, focused: bool) -> Snapshot {
        use gilrs::{EventType, Gilrs};
        if self.gilrs.is_none() && !self.failed {
            match Gilrs::new() {
                Ok(g) => self.gilrs = Some(g),
                Err(gilrs::Error::NotImplemented(g)) => {
                    log::info!("gamepad: not supported on this platform");
                    self.gilrs = Some(g);
                }
                Err(e) => {
                    log::warn!("gamepad: {e}");
                    self.failed = true;
                }
            }
        }
        let Some(g) = self.gilrs.as_mut() else { return Snapshot::default() };
        // Events keep gilrs's state current; the first pad found and the last one a button went down on is the one in use.
        while let Some(ev) = g.next_event() {
            match ev.event {
                EventType::Connected => {
                    log::info!("gamepad: {} connected", g.gamepad(ev.id).name());
                    self.active.get_or_insert(ev.id);
                }
                EventType::Disconnected => {
                    log::info!("gamepad: disconnected");
                    if self.active == Some(ev.id) {
                        self.active = None;
                    }
                }
                EventType::ButtonPressed(..) => self.active = Some(ev.id),
                _ => {}
            }
        }
        // A pad already there at start, or the active one gone: take any connected one.
        if self.active.is_none_or(|id| g.connected_gamepad(id).is_none()) {
            self.active = g.gamepads().next().map(|(id, _)| id);
        }
        let Some(p) = self.active.and_then(|id| g.connected_gamepad(id)).filter(|_| focused) else { return Snapshot::default() };
        use gilrs::{Axis, Button};
        let mut s = Snapshot::default();
        // Analog triggers read as buttons by value. Not the LeftZ / RightZ axes: on pads gilrs has no mapping for, those
        // are often the right stick.
        let trigger = |b: Button| p.is_pressed(b) || p.button_data(b).is_some_and(|d| d.value() > TRIGGER);
        for (b, on) in [
            (Btn::South, p.is_pressed(Button::South)),
            (Btn::East, p.is_pressed(Button::East)),
            (Btn::West, p.is_pressed(Button::West)),
            (Btn::North, p.is_pressed(Button::North)),
            (Btn::LeftBumper, p.is_pressed(Button::LeftTrigger)),
            (Btn::RightBumper, p.is_pressed(Button::RightTrigger)),
            (Btn::LeftTrigger, trigger(Button::LeftTrigger2)),
            (Btn::RightTrigger, trigger(Button::RightTrigger2)),
            (Btn::Select, p.is_pressed(Button::Select)),
            (Btn::Start, p.is_pressed(Button::Start)),
            (Btn::LeftThumb, p.is_pressed(Button::LeftThumb)),
            (Btn::RightThumb, p.is_pressed(Button::RightThumb)),
            (Btn::DPadUp, p.is_pressed(Button::DPadUp)),
            (Btn::DPadDown, p.is_pressed(Button::DPadDown)),
            (Btn::DPadLeft, p.is_pressed(Button::DPadLeft)),
            (Btn::DPadRight, p.is_pressed(Button::DPadRight)),
        ] {
            s.set(b, on);
        }
        s.left = (p.value(Axis::LeftStickX), p.value(Axis::LeftStickY));
        s.right = (p.value(Axis::RightStickX), p.value(Axis::RightStickY));
        s
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn tuning() -> Tuning {
        Tuning { deadzone: 0.2, camera_speed: 1.0 }
    }

    fn pressed(bs: &[Btn]) -> Snapshot {
        let mut s = Snapshot::default();
        for &b in bs {
            s.set(b, true);
        }
        s
    }

    fn keys(out: &Out) -> Vec<(Key, bool, bool)> {
        out.events
            .iter()
            .filter_map(|e| match e {
                Event::Key { key, pressed, repeat, modifiers, .. } => {
                    assert_eq!(*modifiers, Modifiers::NONE);
                    Some((*key, *pressed, *repeat))
                }
                _ => None,
            })
            .collect()
    }

    /// The default layout, button by button, in the three contexts.
    #[test]
    fn mapping_table() {
        use Btn::*;
        let f = |b, c| binding(b, c).map(|x| (x.key, x.dik.to_vec(), x.repeat));
        // Confirm and cancel everywhere.
        for c in [Ctx::Field, Ctx::Menu, Ctx::Typing] {
            assert_eq!(f(South, c), Some((Some(Key::Enter), vec![0x1c], false)));
            assert_eq!(f(East, c), Some((Some(Key::Escape), vec![0x01], false)));
        }
        // The main menu on X; Backspace while typing.
        assert_eq!(f(West, Ctx::Field), Some((Some(Key::Minus), vec![0x0c], false)));
        assert_eq!(f(West, Ctx::Typing), Some((Some(Key::Backspace), vec![0x0e], false)));
        // Palette modifiers: Ctrl and Alt, in every context.
        for c in [Ctx::Field, Ctx::Menu, Ctx::Typing] {
            assert_eq!(f(LeftTrigger, c), Some((None, vec![0x1d], false)));
            assert_eq!(f(RightTrigger, c), Some((None, vec![0x38], false)));
        }
        // The D-pad: target cycling in the field, arrows (repeating) elsewhere.
        assert_eq!(f(DPadRight, Ctx::Field), Some((None, vec![0x0f], false)));
        assert_eq!(f(DPadLeft, Ctx::Field), Some((None, vec![0x2a, 0x0f], false)));
        assert_eq!(f(DPadUp, Ctx::Field), Some((None, vec![0x3b], false)));
        assert_eq!(f(DPadDown, Ctx::Field), Some((None, vec![], false)));
        for c in [Ctx::Menu, Ctx::Typing, Ctx::Action] {
            assert_eq!(f(DPadUp, c), Some((Some(Key::ArrowUp), vec![0xc8], true)));
            assert_eq!(f(DPadDown, c), Some((Some(Key::ArrowDown), vec![0xd0], true)));
            assert_eq!(f(DPadLeft, c), Some((Some(Key::ArrowLeft), vec![0xcb], true)));
            assert_eq!(f(DPadRight, c), Some((Some(Key::ArrowRight), vec![0xcd], true)));
        }
        // Only the arrows repeat (and the on-screen keyboard's Backspace).
        for c in [Ctx::Field, Ctx::Menu, Ctx::Typing, Ctx::Name, Ctx::Map, Ctx::Osk] {
            for b in BUTTONS {
                if let Some(x) = binding(b, c) {
                    let arrow = x.key.is_some_and(|k| matches!(k, Key::ArrowUp | Key::ArrowDown | Key::ArrowLeft | Key::ArrowRight));
                    let backspace = c == Ctx::Osk && x.key == Some(Key::Backspace);
                    assert_eq!(x.repeat, arrow || backspace, "{b:?} {c:?}");
                }
            }
        }
        // The chat line opens on Select (with its space, as the window's key sends it) and takes Tab there.
        let sel = binding(Select, Ctx::Field).unwrap();
        assert_eq!((sel.key, sel.text), (Some(Key::Space), Some(" ")));
        assert_eq!(f(Select, Ctx::Typing), Some((Some(Key::Tab), vec![0x0f], false)));
        assert_eq!(f(Select, Ctx::Menu), None);
        assert_eq!(f(Start, Ctx::Field), Some((None, vec![0xc5], false)));
        assert_eq!(f(Start, Ctx::Menu), Some((Some(Key::Minus), vec![0x0c], false)));
        assert_eq!((f(LeftBumper, Ctx::Field), f(RightBumper, Ctx::Menu)), (Some((None, vec![0x4e], false)), Some((None, vec![0x4a], false))));
        assert_eq!(f(LeftBumper, Ctx::Typing), None);
        assert_eq!(f(North, Ctx::Field), Some((None, vec![0x37], false)));
        assert_eq!(f(LeftThumb, Ctx::Field), Some((None, vec![0xb5], false)));
        assert_eq!(f(LeftThumb, Ctx::Menu), None);
        // Start in a text field is nothing for the game: it brings the on-screen keyboard back (`osk_returns_on_start`).
        assert_eq!(f(Start, Ctx::Typing), None);
    }

    /// Snapshot and the mapper index by `Btn as usize`: the list and the discriminants must agree, and R3 is in them.
    #[test]
    fn buttons_are_indexed_by_discriminant() {
        for (i, b) in BUTTONS.iter().enumerate() {
            assert_eq!(*b as usize, i, "{b:?}");
        }
        assert!(BUTTONS.contains(&Btn::RightThumb));
        let mut s = Snapshot::default();
        s.set(Btn::RightThumb, true);
        assert!(s.get(Btn::RightThumb) && !s.get(Btn::LeftThumb) && s.buttons.len() == BUTTONS.len());
    }

    /// R3 is retail's /map: it opens the map walking about (the client's /map only opens), closes it as the map's own
    /// Escape from the map, the rotation with the battle menu up (ours), and is nothing elsewhere.
    #[test]
    fn r3_is_the_map() {
        let r3 = |c| binding(Btn::RightThumb, c);
        let field = r3(Ctx::Field).unwrap();
        assert_eq!((field.key, field.dik.to_vec(), field.command, field.text), (None, vec![], Some("/map"), None));
        let map = r3(Ctx::Map).unwrap();
        assert_eq!((map.key, map.dik.to_vec(), map.command), (Some(Key::Escape), vec![0x01], None));
        for c in [Ctx::Menu, Ctx::Typing, Ctx::Name, Ctx::Osk] {
            assert_eq!(r3(c), None, "{c:?}");
        }
        // The press hands the command out once, and sends no key to the game.
        let mut m = Mapper::default();
        let out = m.step(&pressed(&[Btn::RightThumb]), Ctx::Field, tuning(), 0.016);
        assert_eq!((out.commands.clone(), out.events.len(), out.keys.len(), out.pressed), (vec!["/map"], 0, 0, true));
        let out = m.step(&pressed(&[Btn::RightThumb]), Ctx::Field, tuning(), 0.016);
        assert!(out.commands.is_empty());
        // In the map it is Escape.
        let mut m = Mapper::default();
        let out = m.step(&pressed(&[Btn::RightThumb]), Ctx::Map, tuning(), 0.016);
        assert_eq!((keys(&out), out.commands.len()), (vec![(Key::Escape, true, false)], 0));
    }

    /// The D-pad's Down in the field is the one-button rotation (ours): the /rotation command, once per press.
    #[test]
    fn dpad_down_in_the_field_runs_the_rotation() {
        assert_eq!(binding(Btn::DPadDown, Ctx::Field).and_then(|b| b.command), Some("/rotation"));
        let mut m = Mapper::default();
        assert_eq!(m.step(&pressed(&[Btn::DPadDown]), Ctx::Field, tuning(), 0.016).commands, vec!["/rotation"]);
        // With the battle menu up, R3.
        assert_eq!(binding(Btn::RightThumb, Ctx::Action).and_then(|b| b.command), Some("/rotation"));
        assert!(m.step(&pressed(&[Btn::DPadDown]), Ctx::Field, tuning(), 0.016).commands.is_empty());
    }

    /// The character-creation name entry: a text field (X is Backspace, Y Space, Select Tab for the view, Start the
    /// keyboard) that keeps LB's random name, which the other text fields drop.
    #[test]
    fn name_entry_is_typing_plus_random_name() {
        let f = |b, c| binding(b, c).map(|x| (x.key, x.dik.to_vec(), x.repeat, x.text));
        for b in BUTTONS {
            if b == Btn::LeftBumper {
                continue;
            }
            assert_eq!(f(b, Ctx::Name), f(b, Ctx::Typing), "{b:?}");
        }
        assert_eq!(f(Btn::West, Ctx::Name), Some((Some(Key::Backspace), vec![0x0e], false, None)));
        assert_eq!(f(Btn::LeftBumper, Ctx::Name), Some((None, vec![0x4e], false, None)));
        assert_eq!(f(Btn::LeftBumper, Ctx::Typing), None);
        // Start asks for the keyboard there too; the sticks are the caret's, not walking.
        let mut m = Mapper::default();
        let mut s = pressed(&[Btn::Start]);
        s.left = (0.0, 1.0);
        let out = m.step(&s, Ctx::Name, tuning(), 0.016);
        assert!(out.open_osk);
        assert_eq!((out.sticks, keys(&out)), ([0.0; 4], vec![(Key::ArrowUp, true, false)]));
    }

    /// With the map up the right stick is its zoom (up zooms in: the negative axis, as the zoom key 0xa4's), the left
    /// stick the cursor, and the camera and walking stay still.
    #[test]
    fn map_zoom_on_the_right_stick() {
        let mut m = Mapper::default();
        let mut s = Snapshot::default();
        s.right = (0.0, 1.0);
        let out = m.step(&s, Ctx::Map, tuning(), 0.016);
        assert_eq!((out.zoom, out.sticks), (-1.0, [0.0; 4]));
        s.right = (0.0, -1.0);
        assert_eq!(m.step(&s, Ctx::Map, tuning(), 0.016).zoom, 1.0);
        // Inside the deadzone: nothing. Sideways: nothing.
        s.right = (0.1, -0.1);
        assert_eq!(m.step(&s, Ctx::Map, tuning(), 0.016).zoom, 0.0);
        s.right = (1.0, 0.0);
        assert_eq!(m.step(&s, Ctx::Map, tuning(), 0.016).zoom, 0.0);
        // The camera speed does not scale it, and no other context has a zoom.
        s.right = (0.0, 1.0);
        let fast = Tuning { deadzone: 0.2, camera_speed: 3.0 };
        assert_eq!(m.step(&s, Ctx::Map, fast, 0.016).zoom, -1.0);
        for c in [Ctx::Field, Ctx::Menu, Ctx::Action, Ctx::Typing, Ctx::Name, Ctx::Osk] {
            assert_eq!(m.step(&s, c, tuning(), 0.016).zoom, 0.0, "{c:?}");
        }
        // The map's other buttons are a window's: the left stick moves the cursor, Start the main menu.
        let mut s = pressed(&[Btn::Start]);
        s.left = (1.0, 0.0);
        let out = Mapper::default().step(&s, Ctx::Map, tuning(), 0.016);
        assert_eq!(keys(&out), vec![(Key::Minus, true, false), (Key::ArrowRight, true, false)]);
    }

    /// The on-screen keyboard's context: virtual keys for the keyboard, no DIK, nothing for the game.
    #[test]
    fn osk_mapping_table() {
        use Btn::*;
        let f = |b| binding(b, Ctx::Osk).map(|x| (x.key, x.dik.to_vec(), x.repeat, x.text));
        assert_eq!(f(South), Some((Some(Key::Enter), vec![], false, None)));
        assert_eq!(f(East), Some((Some(Key::Backspace), vec![], true, None)));
        assert_eq!(f(West), Some((Some(Key::Space), vec![], false, None)));
        assert_eq!(f(North), Some((Some(Key::Tab), vec![], false, None)));
        assert_eq!(f(Start), Some((Some(Key::F2), vec![], false, None)));
        assert_eq!(f(Select), Some((Some(Key::Escape), vec![], false, None)));
        assert_eq!(f(DPadUp), Some((Some(Key::ArrowUp), vec![], true, None)));
        assert_eq!(f(DPadDown), Some((Some(Key::ArrowDown), vec![], true, None)));
        assert_eq!(f(DPadLeft), Some((Some(Key::ArrowLeft), vec![], true, None)));
        assert_eq!(f(DPadRight), Some((Some(Key::ArrowRight), vec![], true, None)));
        // The rest do nothing, so no Ctrl / Alt, no log views, no walk toggle under the keyboard.
        for b in [LeftBumper, RightBumper, LeftTrigger, RightTrigger, LeftThumb] {
            assert_eq!(f(b), None, "{b:?}");
        }
        // No button holds a DIK key in it.
        for b in BUTTONS {
            assert!(binding(b, Ctx::Osk).is_none_or(|x| x.dik.is_empty()), "{b:?}");
        }
    }

    /// Under the keyboard neither stick walks or turns, the left one is a D-pad, and held triggers hold nothing.
    #[test]
    fn osk_takes_the_pad_whole() {
        let mut m = Mapper::default();
        let mut s = pressed(&[Btn::LeftTrigger, Btn::RightTrigger]);
        s.left = (0.0, 1.0);
        s.right = (1.0, 0.0);
        let out = m.step(&s, Ctx::Osk, tuning(), 0.016);
        assert_eq!(out.sticks, [0.0; 4]);
        assert!(out.keys.is_empty());
        assert_eq!(keys(&out), vec![(Key::ArrowUp, true, false)]);
    }

    /// Select closes the keyboard; Start, over a text field and with it closed, asks for it back (the press is the
    /// pad's, and nothing is sent to the field).
    #[test]
    fn osk_returns_on_start() {
        let mut m = Mapper::default();
        let out = m.step(&pressed(&[Btn::Start]), Ctx::Typing, tuning(), 0.016);
        assert!(out.open_osk && out.pressed && out.events.is_empty() && out.keys.is_empty());
        // Held: once. Not in the field, a menu or the keyboard.
        assert!(!m.step(&pressed(&[Btn::Start]), Ctx::Typing, tuning(), 0.016).open_osk);
        let mut m = Mapper::default();
        for c in [Ctx::Field, Ctx::Menu, Ctx::Action, Ctx::Osk] {
            assert!(!m.step(&pressed(&[Btn::Start]), c, tuning(), 0.016).open_osk, "{c:?}");
            m.step(&Snapshot::default(), c, tuning(), 0.016);
        }
    }

    /// Every DIK the table names is one the window's keys can produce (input.rs), so the key functions see it.
    #[test]
    fn mapping_uses_real_dik_codes() {
        use winit::keyboard::KeyCode as K;
        let known: Vec<u8> = [K::Enter, K::Escape, K::Minus, K::Backspace, K::Tab, K::ShiftLeft, K::ControlLeft, K::AltLeft, K::Space, K::F1, K::NumpadMultiply, K::NumpadSubtract, K::NumpadAdd, K::NumpadDivide, K::Pause, K::ArrowUp, K::ArrowDown, K::ArrowLeft, K::ArrowRight]
            .into_iter()
            .map(|k| super::super::input::dik(k).unwrap())
            .collect();
        for c in [Ctx::Field, Ctx::Menu, Ctx::Typing, Ctx::Name, Ctx::Map, Ctx::Osk] {
            for b in BUTTONS {
                for d in binding(b, c).iter().flat_map(|x| x.dik) {
                    assert!(known.contains(d), "{b:?} {c:?} {d:#x}");
                }
            }
        }
    }

    #[test]
    fn deadzone_math() {
        // Inside the deadzone: nothing, whatever the direction.
        assert_eq!(deadzone(0.19, 0.0, 0.2), (0.0, 0.0));
        assert_eq!(deadzone(0.1, 0.15, 0.2), (0.0, 0.0));
        assert_eq!(deadzone(0.0, 0.0, 0.2), (0.0, 0.0));
        // Radial: a diagonal inside the circle but past the axes' deadzone is still dead.
        assert_eq!(deadzone(0.14, 0.14, 0.2), (0.0, 0.0));
        // Just past it the push is small and grows smoothly from zero.
        let (x, _) = deadzone(0.25, 0.0, 0.2);
        assert!(x > 0.0 && x < 0.1, "{x}");
        // Full and past full push saturate at 1, direction kept.
        let (x, y) = deadzone(1.0, 1.0, 0.2);
        assert!((x.hypot(y) - 1.0).abs() < 1e-6 && (x - y).abs() < 1e-6);
        // A pad that tops out at 0.92 still runs (the movement code runs past 0.9).
        let (x, _) = deadzone(0.92, 0.0, 0.2);
        assert!(x > 0.9, "{x}");
        // Signs are kept.
        let (x, y) = deadzone(-0.6, 0.3, 0.2);
        assert!(x < 0.0 && y > 0.0);
        // The deadzone is bounded: an absurd or broken value cannot divide by zero or produce NaN.
        for dz in [-1.0, 0.0, 0.95, 1.0, 5.0, f32::NAN, f32::INFINITY] {
            let (x, y) = deadzone(0.9, 0.1, dz);
            assert!(x.is_finite() && y.is_finite(), "{dz}");
        }
        assert_eq!(deadzone(f32::NAN, 0.0, 0.2), (0.0, 0.0));
        // Monotonic along an axis.
        let mut last = 0.0;
        for i in 0..=100 {
            let (x, _) = deadzone(i as f32 / 100.0, 0.0, 0.2);
            assert!(x >= last);
            last = x;
        }
    }

    #[test]
    fn stick_vectors() {
        // Up on the stick (gilrs y +1) is forward: movement Y negative, as the keyboard's W is.
        assert_eq!(stick_to_move(0.0, 1.0, 0.2), (0.0, -1.0));
        assert_eq!(stick_to_move(1.0, 0.0, 0.2), (1.0, 0.0));
        assert_eq!(stick_to_move(0.0, -1.0, 0.2), (0.0, 1.0));
        assert_eq!(stick_to_move(0.1, 0.1, 0.2), (0.0, 0.0));
        // The camera: right is positive X, stick down positive Y (the Down arrow's sign); speed scales after the deadzone.
        assert_eq!(stick_to_camera(1.0, 0.0, 0.2, 1.0), (1.0, 0.0));
        assert_eq!(stick_to_camera(0.0, -1.0, 0.2, 2.0), (0.0, 2.0));
        assert_eq!(stick_to_camera(0.1, 0.0, 0.2, 3.0), (0.0, 0.0));
        assert!((stick_to_camera(-1.0, 1.0, 0.2, 0.5).0 + 0.5 * std::f32::consts::FRAC_1_SQRT_2).abs() < 1e-6);
        // A bad speed does not blow up the camera.
        assert!(stick_to_camera(1.0, 0.0, 0.2, f32::NAN).0.is_finite());
        assert!(stick_to_camera(1.0, 0.0, 0.2, 1e9).0 <= 5.0);
    }

    #[test]
    fn sticks_by_context() {
        let mut m = Mapper::default();
        let mut s = Snapshot::default();
        s.left = (0.0, 1.0);
        s.right = (1.0, 0.0);
        // The field: both sticks.
        let out = m.step(&s, Ctx::Field, tuning(), 0.016);
        assert_eq!(out.sticks, [0.0, -1.0, 1.0, 0.0]);
        assert!(out.events.is_empty() && out.keys.is_empty());
        // A window: no walking or camera; the left stick pushes the D-pad's arrows instead.
        let out = m.step(&s, Ctx::Menu, tuning(), 0.016);
        assert_eq!(out.sticks, [0.0; 4]);
        assert_eq!(keys(&out), vec![(Key::ArrowUp, true, false)]);
        // Back to the field with the stick still up: the arrow lifts, walking resumes.
        let out = m.step(&s, Ctx::Field, tuning(), 0.016);
        assert_eq!(keys(&out), vec![(Key::ArrowUp, false, false)]);
        assert_eq!(out.sticks[1], -1.0);
        // Typing: the cursor stick, no walking.
        s.left = (-1.0, 0.0);
        let out = m.step(&s, Ctx::Typing, tuning(), 0.016);
        assert_eq!((out.sticks, keys(&out)), ([0.0; 4], vec![(Key::ArrowLeft, true, false)]));
        // A light push on the stick moves no cursor.
        let mut m = Mapper::default();
        s.left = (0.4, 0.0);
        assert!(m.step(&s, Ctx::Menu, tuning(), 0.016).events.is_empty());
    }

    /// All through a fight the action menu is up: the sticks keep walking and turning the camera, the buttons are the
    /// menu's (arrows, Enter, Escape).
    #[test]
    fn action_menu_keeps_the_sticks() {
        let mut m = Mapper::default();
        let mut s = pressed(&[Btn::DPadDown]);
        s.left = (0.0, 1.0);
        s.right = (1.0, 0.0);
        let out = m.step(&s, Ctx::Action, tuning(), 0.016);
        assert_eq!(out.sticks, [0.0, -1.0, 1.0, 0.0]);
        assert_eq!(keys(&out), vec![(Key::ArrowDown, true, false)]);
        assert_eq!(out.keys, vec![0xd0]);
        // A and B are Enter / Escape as in any menu.
        let out = m.step(&pressed(&[Btn::DPadDown, Btn::South]), Ctx::Action, tuning(), 0.016);
        assert_eq!(keys(&out), vec![(Key::Enter, true, false)]);
        // A held palette trigger stands the character and the D-pad works the palette.
        let mut m = Mapper::default();
        let mut s = pressed(&[Btn::LeftTrigger]);
        s.left = (0.0, 1.0);
        let out = m.step(&s, Ctx::Action, tuning(), 0.016);
        assert_eq!(out.sticks, [0.0; 4]);
        assert!(out.keys.contains(&0x1d));
        // The same in the field: a trigger stands the character too.
        let mut m = Mapper::default();
        assert_eq!(m.step(&s, Ctx::Field, tuning(), 0.016).sticks, [0.0; 4]);
    }

    #[test]
    fn press_release_and_binding_sticks() {
        let mut m = Mapper::default();
        // A in the field: Enter down with its DIK held, then up.
        let out = m.step(&pressed(&[Btn::South]), Ctx::Field, tuning(), 0.016);
        assert_eq!((keys(&out), out.keys.clone(), out.pressed), (vec![(Key::Enter, true, false)], vec![0x1c], true));
        // Held: no second press (Enter acts once), the DIK stays; the context changing keeps the binding.
        let out = m.step(&pressed(&[Btn::South]), Ctx::Typing, tuning(), 0.016);
        assert_eq!((out.events.len(), out.keys.clone(), out.pressed), (0, vec![0x1c], false));
        let out = m.step(&Snapshot::default(), Ctx::Typing, tuning(), 0.016);
        assert_eq!((keys(&out), out.keys.is_empty()), (vec![(Key::Enter, false, false)], true));
        assert!(!m.any_down());
        // Select opens the chat line: the key and its text.
        let out = m.step(&pressed(&[Btn::Select]), Ctx::Field, tuning(), 0.016);
        assert!(out.events.iter().any(|e| matches!(e, Event::Text(t) if t == " ")));
    }

    #[test]
    fn dpad_repeats_like_a_held_arrow() {
        let mut m = Mapper::default();
        let s = pressed(&[Btn::DPadDown]);
        let mut presses = 0;
        let mut repeats = 0;
        let mut first_repeat = None;
        for frame in 0..120 {
            let out = m.step(&s, Ctx::Menu, tuning(), 1.0 / 60.0);
            for (_, down, rep) in keys(&out) {
                assert!(down);
                if rep {
                    repeats += 1;
                    first_repeat.get_or_insert(frame);
                } else {
                    presses += 1;
                }
            }
        }
        // Two seconds held: one press, a pause of REPEAT_DELAY, then about one repeat every REPEAT_EVERY.
        assert_eq!(presses, 1);
        assert!((17..=19).contains(&first_repeat.unwrap()), "{first_repeat:?}");
        assert!((22..=26).contains(&repeats), "{repeats}");
        // A slow frame fires the repeats it skipped, a hitch of a second included.
        let mut m = Mapper::default();
        m.step(&s, Ctx::Menu, tuning(), 0.016);
        let out = m.step(&s, Ctx::Menu, tuning(), 1.0);
        assert!(keys(&out).len() >= 10);
        // Enter, Escape and the menu key never repeat.
        let mut m = Mapper::default();
        let s = pressed(&[Btn::South, Btn::East, Btn::West]);
        m.step(&s, Ctx::Menu, tuning(), 0.016);
        assert!(m.step(&s, Ctx::Menu, tuning(), 2.0).events.is_empty());
    }

    #[test]
    fn palette_triggers_turn_the_dpad_into_arrows() {
        let mut m = Mapper::default();
        // LT held in the field: Ctrl is held and the D-pad is a cursor, not target cycling.
        let out = m.step(&pressed(&[Btn::LeftTrigger, Btn::DPadRight]), Ctx::Field, tuning(), 0.016);
        assert!(out.keys.contains(&0x1d) && out.keys.contains(&0xcd) && !out.keys.contains(&0x0f));
        assert_eq!(keys(&out), vec![(Key::ArrowRight, true, false)]);
        // The synthetic events carry no modifiers (the Ctrl / Alt letter shortcuts match on them): checked in `keys`.
        // Without a trigger the same D-pad press cycles the target, with no egui event.
        let mut m = Mapper::default();
        let out = m.step(&pressed(&[Btn::DPadRight]), Ctx::Field, tuning(), 0.016);
        assert_eq!((out.keys, out.events.len()), (vec![0x0f], 0));
    }

    /// Unplugging, losing the window's focus and switching the setting off all hand the mapper an empty snapshot:
    /// nothing stays held (a stuck Ctrl would leave the palette open), the sticks are zero.
    #[test]
    fn release_on_unplug() {
        let mut m = Mapper::default();
        let mut s = pressed(&[Btn::LeftTrigger, Btn::RightTrigger, Btn::DPadRight, Btn::South]);
        s.left = (1.0, 0.0);
        let out = m.step(&s, Ctx::Field, tuning(), 0.016);
        assert!(out.keys.contains(&0x1d) && out.keys.contains(&0x38));
        let out = m.step(&Snapshot::default(), Ctx::Field, tuning(), 0.016);
        assert!(out.keys.is_empty() && out.sticks == [0.0; 4] && !m.any_down());
        assert!(keys(&out).iter().all(|&(_, down, _)| !down));
        assert_eq!(keys(&out).len(), 2, "Enter and the arrow lift: {:?}", keys(&out));
        // Plugging in again starts clean.
        let out = m.step(&pressed(&[Btn::South]), Ctx::Field, tuning(), 0.016);
        assert_eq!(keys(&out), vec![(Key::Enter, true, false)]);
    }

    /// With no pad (the default snapshot every frame) the mapper does nothing at all.
    #[test]
    fn no_pad_changes_nothing() {
        let mut m = Mapper::default();
        for c in [Ctx::Field, Ctx::Menu, Ctx::Typing, Ctx::Name, Ctx::Map, Ctx::Osk] {
            let out = m.step(&Snapshot::default(), c, tuning(), 0.016);
            assert!(out.events.is_empty() && out.keys.is_empty() && out.sticks == [0.0; 4] && !out.pressed && !out.open_osk && out.commands.is_empty() && out.zoom == 0.0);
        }
    }
}
