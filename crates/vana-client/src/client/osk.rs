//! The on-screen keyboard for text fields while a gamepad is in use (not retail). `request(field)` is the one hook: the
//! app calls it when a text field gains focus and the pad was the last device used (`Edge`).
//!
//! What it does today: under Steam (the `SteamAppId` / `SteamGameId` it sets for the games it starts, a non-Steam
//! shortcut included) it opens Steam's own keyboard with the `steam://open/keyboard` URL, through the system's URL
//! handler (xdg-open on Linux, ShellExecute on Windows), without waiting for it and ignoring a failure. Outside Steam
//! it does nothing.
//!
//! TODO: outside Steam there is no keyboard yet. The Windows touch keyboard (TabTip.exe) cannot be raised safely from a
//! full-screen window, Linux has no common one, and a keyboard of our own (egui buttons over the focused field, fed
//! through the same events as the window's keys) is more than this change.

/// The field that took the focus: what a richer keyboard would lay out for (a password hides its keys' echo, the chat
/// line offers the slash commands).
#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub enum Field {
    /// The login screen's fields.
    Login,
    /// The chat line.
    Chat,
    /// Any other field (searches, event inputs, names).
    Other,
}

/// Steam's keyboard URL (Big Picture / Steam Deck text entry).
const STEAM_KEYBOARD: &str = "steam://open/keyboard";

/// Whether the game was started by Steam: `env` reads an environment variable.
pub fn under_steam(env: impl Fn(&str) -> Option<String>) -> bool {
    ["SteamAppId", "SteamGameId"].iter().any(|k| env(k).is_some_and(|v| !v.trim().is_empty()))
}

/// Raises the on-screen keyboard for `field`, if one can be. Never blocks, never fails.
pub fn request(field: Field) {
    if !under_steam(|k| std::env::var(k).ok()) {
        log::debug!("osk: no keyboard to raise for {field:?} (not under Steam)");
        return;
    }
    log::info!("osk: Steam keyboard for {field:?}");
    open_url(STEAM_KEYBOARD);
}

#[cfg(windows)]
fn open_url(url: &str) {
    use windows_sys::Win32::UI::Shell::ShellExecuteW;
    use windows_sys::Win32::UI::WindowsAndMessaging::SW_SHOWNORMAL;
    let wide: Vec<u16> = url.encode_utf16().chain(std::iter::once(0)).collect();
    let verb: Vec<u16> = "open".encode_utf16().chain(std::iter::once(0)).collect();
    // SAFETY: both strings are NUL-terminated and outlive the call; the rest are null (no window, parameters or
    // directory). ShellExecuteW starts the handler without waiting.
    unsafe {
        ShellExecuteW(std::ptr::null_mut(), verb.as_ptr(), wide.as_ptr(), std::ptr::null(), std::ptr::null(), SW_SHOWNORMAL);
    }
}

#[cfg(not(windows))]
fn open_url(url: &str) {
    use std::process::{Command, Stdio};
    let started = Command::new("xdg-open").arg(url).stdin(Stdio::null()).stdout(Stdio::null()).stderr(Stdio::null()).spawn();
    match started {
        // Reaped off-thread so the child does not linger as a zombie.
        Ok(mut child) => {
            std::thread::spawn(move || _ = child.wait());
        }
        Err(e) => log::debug!("osk: xdg-open: {e}"),
    }
}

/// A text field opening, once: the keyboard goes up on the frame a field gains focus with the pad the last device
/// used, never again while it stays open or when the keyboard and mouse were used.
#[derive(Default)]
pub struct Edge {
    was: bool,
}

impl Edge {
    /// `open`: a text field has the keys now; `pad`: the pad was the last device. True on the frame to raise it.
    pub fn update(&mut self, open: bool, pad: bool) -> bool {
        let rose = open && !self.was;
        self.was = open;
        rose && pad
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn steam_is_told_by_its_variables() {
        let with = |name: &'static str, v: &'static str| move |k: &str| (k == name).then(|| v.to_string());
        assert!(under_steam(with("SteamAppId", "480")));
        assert!(under_steam(with("SteamGameId", "12345678")));
        assert!(!under_steam(with("SteamAppId", "")));
        assert!(!under_steam(with("SteamAppId", "  ")));
        assert!(!under_steam(|_| None));
        assert!(!under_steam(with("Steam", "1")));
    }

    #[test]
    fn raised_once_per_opening_and_only_for_the_pad() {
        let mut e = Edge::default();
        assert!(!e.update(false, true));
        assert!(e.update(true, true));
        // Still open: not again, every frame.
        assert!(!e.update(true, true));
        assert!(!e.update(false, true));
        // The keyboard opened it: no on-screen keyboard.
        assert!(!e.update(true, false));
        assert!(!e.update(false, false));
        assert!(e.update(true, true));
    }
}
