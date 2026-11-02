//! Ours (not retail): the era lock, and the Expansions view.
//!
//! A server tells the client which expansions it runs only through the lobby's expansions bitmask (`Lobby.expansions`,
//! u32 @0x20 of the lobby reply: bit 0 the base game, bits 1..11 the expansions in release order). When no expansion bit
//! is on the server runs the base game's era, and the client hides what did not exist then: the windows of later
//! systems (mounts, Trust, Unity, Merit / Job / Alter Ego Points, Master Levels, Records of Eminence, the Search
//! menu's Unity and Monstrosity rows) are greyed, the Search menu offers the base jobs only and stops its level fields at
//! 60. Nothing is invented: only the client's own windows change, whatever the server sends. With any expansion bit on,
//! or with the config's `era_lock` off, retail behaviour is unchanged.
//!
//! The era is keyed on the lobby's bits as sent, not on `World.expansions` (those and the installed DATs), so a player
//! whose game folder lacks an expansion's files still plays the server's era.

use super::World;

/// The expansions by lobby bit, in release order (the lobby's generateExpansionBitmask; MODLOG.md "Lobby title screen").
pub const EXPANSIONS: [(u32, &str); 11] = [
    (1 << 1, "Rise of the Zilart"),
    (1 << 2, "Chains of Promathia"),
    (1 << 3, "Treasures of Aht Urhgan"),
    (1 << 4, "Wings of the Goddess"),
    (1 << 5, "A Crystalline Prophecy"),
    (1 << 6, "A Moogle Kupo d'Etat"),
    (1 << 7, "A Shantotto Ascension"),
    (1 << 8, "Vision of Abyssea"),
    (1 << 9, "Scars of Abyssea"),
    (1 << 10, "Heroes of Abyssea"),
    (1 << 11, "Seekers of Adoulin"),
];

/// Every expansion bit (the base bit left out).
pub const EXPANSION_MASK: u32 = 0xffe;

/// The era the bits describe.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Era {
    /// No expansion: the base game.
    Base,
    /// Any expansion on: retail's own behaviour.
    Expanded,
}

pub fn era_of(bits: u32) -> Era {
    if bits & EXPANSION_MASK == 0 { Era::Base } else { Era::Expanded }
}

/// The client features that did not exist in the base era.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Feature {
    Mounts,
    Trust,
    Unity,
    MeritPoints,
    JobPoints,
    MasterLevels,
    AlterEgoPoints,
    RecordsOfEminence,
    Monstrosity,
}

pub fn has(era: Era, _feature: Feature) -> bool {
    // Every feature listed is later than the base game; the table is here so one can be given back by a bit.
    era == Era::Expanded
}

/// The level cap the client shows itself (its Search level fields): 60 in the base era, else retail's 99.
pub fn level_cap(era: Era) -> u8 {
    if era == Era::Base { 60 } else { 99 }
}

/// The base jobs, by job id (items::JOBS): WAR MNK WHM BLM RDM THF PLD DRK BST BRD RNG.
pub const BASE_JOBS: std::ops::RangeInclusive<u8> = 1..=11;

pub fn job_offered(era: Era, job: u8) -> bool {
    era == Era::Expanded || BASE_JOBS.contains(&job)
}

/// The lock is on: the config switch is on and the server's bits describe the base era.
pub fn locked(w: &World) -> bool {
    w.era_lock && era_of(w.lobby_expansions) == Era::Base
}

/// The feature is not available now (the era lock hides it).
pub fn hidden(w: &World, f: Feature) -> bool {
    locked(w) && !has(Era::Base, f)
}

/// The level cap for the client's own level fields under the lock.
pub fn cap(w: &World) -> u8 {
    if locked(w) { level_cap(Era::Base) } else { level_cap(Era::Expanded) }
}

/// Whether the client offers a job in its own lists under the lock.
pub fn job_on(w: &World, job: u8) -> bool {
    !locked(w) || job_offered(Era::Base, job)
}

/// The key of a server and account in the config's last-seen bits.
pub fn seen_key(server: &str, account: &str) -> String {
    format!("{}|{}", server.trim().to_ascii_lowercase(), account.trim().to_ascii_lowercase())
}

/// The expansion bits on now that were not at the last login of this server and account. With no earlier login on
/// record (`prev` None) there is nothing to compare: the bits become the baseline and none is new, so a first login
/// does not announce every expansion the server already had. The base bit is never an expansion.
pub fn new_bits(prev: Option<u32>, now: u32) -> u32 {
    match prev {
        Some(p) => now & EXPANSION_MASK & !p,
        None => 0,
    }
}

/// The names of the expansions in `bits`, release order.
pub fn names(bits: u32) -> Vec<&'static str> {
    EXPANSIONS.iter().filter(|e| bits & e.0 != 0).map(|e| e.1).collect()
}

/// The one-time notice's text for the new bits ("New expansion available: A, B").
pub fn notice(bits: u32) -> Option<String> {
    let n = names(bits);
    (!n.is_empty()).then(|| format!("New expansion available: {}", n.join(", ")))
}

/// Each expansion with whether the server has it on: the Expansions view's rows.
pub fn rows(bits: u32) -> Vec<(&'static str, bool)> {
    EXPANSIONS.iter().map(|e| (e.1, bits & e.0 != 0)).collect()
}

/// /expansions in the log, for both interfaces: each expansion and its state, the era, whether the lock is on.
pub fn print(w: &mut World) {
    w.chat.push("Expansions:".to_string());
    for (name, on) in rows(w.lobby_expansions) {
        w.chat.push(format!("  {name}: {}", if on { "Unlocked" } else { "Locked" }));
    }
    let era = match (era_of(w.lobby_expansions), w.era_lock) {
        (Era::Base, true) => "base game (era lock on)",
        (Era::Base, false) => "base game (era lock off)",
        (Era::Expanded, _) => "expansions on",
    };
    w.chat.push(format!("Era: {era}"));
}

/// Enter or Escape while the Expansions view or the notice is up: closes it (the view first). Other keys go on.
pub fn key(w: &mut World, key: egui::Key) {
    w.sounds.push(if key == egui::Key::Enter { crate::audio::Ui::Select } else { crate::audio::Ui::Cancel } as u32);
    close(w);
}

/// Closes the Expansions view, else the notice.
pub fn close(w: &mut World) {
    if w.era_view {
        w.era_view = false;
    } else {
        w.era_new = 0;
    }
}

/// A key is the Expansions view's or the notice's to take.
pub fn active(w: &World) -> bool {
    w.era_view || w.era_new != 0
}

#[cfg(test)]
mod tests {
    use super::*;

    /// Lobby bit 0: the base game.
    const BASE_BIT: u32 = 1;

    #[test]
    fn base_when_no_expansion_bit() {
        assert_eq!(era_of(0), Era::Base);
        assert_eq!(era_of(BASE_BIT), Era::Base);
        assert_eq!(era_of(BASE_BIT | 0x2), Era::Expanded);
        assert_eq!(era_of(0x800), Era::Expanded);
        // Every expansion bit alone leaves the base era.
        for (bit, _) in EXPANSIONS {
            assert_eq!(era_of(bit), Era::Expanded, "{bit:#x}");
        }
        // Bits above the 11 are not expansions.
        assert_eq!(era_of(0xffff_f000), Era::Base);
    }

    #[test]
    fn expansion_table_is_the_lobby_bits() {
        let mut all = 0;
        for (i, (bit, name)) in EXPANSIONS.iter().enumerate() {
            assert_eq!(*bit, 1 << (i + 1));
            assert!(!name.is_empty());
            all |= bit;
        }
        assert_eq!(all, EXPANSION_MASK);
        assert_eq!(EXPANSION_MASK & BASE_BIT, 0);
    }

    #[test]
    fn base_features_jobs_and_cap() {
        for f in [Feature::Mounts, Feature::Trust, Feature::Unity, Feature::MeritPoints, Feature::JobPoints, Feature::MasterLevels, Feature::AlterEgoPoints, Feature::RecordsOfEminence, Feature::Monstrosity] {
            assert!(!has(Era::Base, f), "{f:?}");
            assert!(has(Era::Expanded, f), "{f:?}");
        }
        assert_eq!(level_cap(Era::Base), 60);
        assert_eq!(level_cap(Era::Expanded), 99);
        // WAR .. RNG are offered, SAM (12) onwards are not, while expansions leave every job.
        assert_eq!((1..=22).filter(|&j| job_offered(Era::Base, j)).collect::<Vec<_>>(), (1..=11).collect::<Vec<_>>());
        assert!((1..=22).all(|j| job_offered(Era::Expanded, j)));
        // The base jobs are the first eleven of the client's job names.
        let names: Vec<&str> = (1..=11).map(|j| super::super::items::JOBS[j]).collect();
        assert_eq!(names, ["WAR", "MNK", "WHM", "BLM", "RDM", "THF", "PLD", "DRK", "BST", "BRD", "RNG"]);
    }

    #[test]
    fn first_login_is_a_baseline() {
        assert_eq!(new_bits(None, 0xfff), 0);
        assert_eq!(new_bits(None, 0), 0);
    }

    #[test]
    fn a_new_bit_is_reported_once() {
        // Zilart appears after a login with base only.
        assert_eq!(new_bits(Some(BASE_BIT), BASE_BIT | 0x2), 0x2);
        // The next login, with the same bits stored, has nothing new.
        assert_eq!(new_bits(Some(BASE_BIT | 0x2), BASE_BIT | 0x2), 0);
        // Two at once, and one already known.
        assert_eq!(new_bits(Some(0x2), 0x2 | 0x8 | 0x10), 0x8 | 0x10);
        // A bit that went away is not new; the base bit never is.
        assert_eq!(new_bits(Some(0x2 | 0x4), 0x2), 0);
        assert_eq!(new_bits(Some(0), BASE_BIT), 0);
        // Bits past the table are ignored.
        assert_eq!(new_bits(Some(0), 0x1000), 0);
    }

    #[test]
    fn notice_names_the_new_bits() {
        assert_eq!(notice(0), None);
        assert_eq!(notice(0x2).as_deref(), Some("New expansion available: Rise of the Zilart"));
        assert_eq!(notice(0x2 | 0x800).as_deref(), Some("New expansion available: Rise of the Zilart, Seekers of Adoulin"));
        assert_eq!(names(0x8 | BASE_BIT), ["Treasures of Aht Urhgan"]);
    }

    #[test]
    fn rows_follow_the_bitmask() {
        let r = rows(BASE_BIT | 0x4);
        assert_eq!(r.len(), 11);
        assert_eq!(r.iter().filter(|x| x.1).map(|x| x.0).collect::<Vec<_>>(), ["Chains of Promathia"]);
        assert!(rows(BASE_BIT).iter().all(|x| !x.1));
    }

    #[test]
    fn seen_key_is_per_server_and_account() {
        assert_eq!(seen_key(" Host ", "Name"), seen_key("host", "name"));
        assert_ne!(seen_key("a", "x"), seen_key("b", "x"));
        assert_ne!(seen_key("a", "x"), seen_key("a", "y"));
    }
}
