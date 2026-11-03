//! Persisted settings and the app's data locations.

use anyhow::Result;
use serde::{Deserialize, Serialize};
use std::path::PathBuf;

/// `base`/vana-client, moved there from the project's old name (ffxi-linux) the first time.
fn app_dir(base: Option<PathBuf>) -> PathBuf {
    let base = base.unwrap_or_else(|| PathBuf::from("."));
    let dir = base.join("vana-client");
    let old = base.join("ffxi-linux");
    if !dir.exists() && old.is_dir() {
        let _ = std::fs::rename(&old, &dir);
    }
    dir
}

pub fn data_dir() -> PathBuf {
    app_dir(dirs::data_dir())
}

/// A character's saved chat lines (the modern chat's history): in the data dir, or beside an FFXI_CONFIG copy.
pub fn chat_history_path(name: &str) -> PathBuf {
    let dir = match std::env::var_os("FFXI_CONFIG") {
        Some(p) => PathBuf::from(p).with_file_name("chat"),
        None => data_dir().join("chat"),
    };
    dir.join(format!("{name}.json"))
}

/// A character's training regime state (client/regime.rs), beside the chat history.
pub fn regime_path(name: &str) -> PathBuf {
    let dir = match std::env::var_os("FFXI_CONFIG") {
        Some(p) => PathBuf::from(p).with_file_name("regime"),
        None => data_dir().join("regime"),
    };
    dir.join(format!("{name}.json"))
}

/// The client's log: in the data dir, or beside an FFXI_CONFIG copy (test runs keep their own).
pub fn log_path() -> PathBuf {
    match std::env::var_os("FFXI_CONFIG") {
        Some(p) => PathBuf::from(p).with_file_name("vana-client.log"),
        None => data_dir().join("vana-client.log"),
    }
}

/// A test run's copy of the config (FFXI_CONFIG): saving it never touches the user's file.
pub fn is_copy() -> bool {
    std::env::var_os("FFXI_CONFIG").is_some()
}

/// FFXI_CONFIG points test runs at a copy, so they never write the user's file.
fn config_path() -> PathBuf {
    std::env::var_os("FFXI_CONFIG").map(PathBuf::from).unwrap_or_else(|| app_dir(dirs::config_dir()).join("config.json"))
}

/// A login that worked: the server, the account (the Square Enix ID for PlayOnline), PlayOnline's member ID, and its
/// own Remember password with the password(s) sealed for that server and account (secret.rs).
#[derive(Clone, Default, Serialize, Deserialize)]
#[serde(default)]
pub struct SavedLogin {
    pub server: String,
    pub username: String,
    pub pol_id: String,
    pub remember_password: bool,
    pub saved_password: String,
}

/// A named server (not retail): its name goes in the login screen's Server field, and its address and ports are used
/// to connect. Ports left out fall back to the config's own (`auth_port` and the rest).
#[derive(Clone, Default, Serialize, Deserialize)]
#[serde(default)]
pub struct NamedServer {
    pub name: String,
    pub host: String,
    pub auth_port: Option<u16>,
    pub data_port: Option<u16>,
    pub view_port: Option<u16>,
    pub profile_port: Option<u16>,
    pub irc_port: Option<u16>,
    /// The friend list, presence and mail through the server's profile service (xi_profile); unset follows
    /// `social_named_only`.
    pub social: Option<bool>,
    /// The loader version this server checks for ("2.1.2"); unset keeps the config's.
    pub loader_version: Option<String>,
}

/// `ui_scale`'s Auto.
pub const UI_SCALE_AUTO: u32 = 1;

fn ui_scale_auto() -> u32 {
    UI_SCALE_AUTO
}

/// The classic UI's stretch for `ui_scale` at this window size; None leaves it to the Menu Size.
pub fn ui_scale_factor(ui_scale: u32, window: [u32; 2]) -> Option<f32> {
    match ui_scale {
        0 => None,
        UI_SCALE_AUTO => Some((window[1] as f32 / 1080.0).max(1.0)),
        p => Some((p as f32 / 100.0).clamp(0.5, 4.0)),
    }
}

fn era_lock_on() -> bool {
    true
}

/// Ours (not retail): the optional post-processing over the drawn 3D scene, before the 2D layer (render/post.rs). All off by
/// default; with every option off no pass, pipeline or texture exists. A `graphics` object of its own, so the launcher's
/// merge of config.json keeps it.
#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
#[serde(default)]
pub struct GraphicsCfg {
    /// FXAA 3.11 (luma edge search) on the scene.
    pub fxaa: bool,
    /// Bloom: bright parts of the scene above `bloom_threshold` (0..1, in the picture's brightness) blurred and added back at
    /// `bloom_intensity` (0..2).
    pub bloom: bool,
    pub bloom_intensity: f32,
    pub bloom_threshold: f32,
    /// A filmic (ACES-fitted) curve on the scene with an `exposure` multiplier (0.25..4, 1 = as drawn); the scene is 8-bit, so
    /// this is a grade, not HDR.
    pub tonemap: bool,
    pub exposure: f32,
    /// Contrast-adaptive sharpening (AMD CAS style), strength 0..1; 0 = off.
    pub sharpen: f32,
    /// Saturation, 1 = as drawn, 0 = grey, up to 2.
    pub saturation: f32,
}

impl Default for GraphicsCfg {
    fn default() -> Self {
        Self { fxaa: false, bloom: false, bloom_intensity: 0.4, bloom_threshold: 0.85, tonemap: false, exposure: 1.0, sharpen: 0.0, saturation: 1.0 }
    }
}

impl GraphicsCfg {
    pub fn bloom_on(&self) -> bool {
        self.bloom && self.bloom_intensity > 0.001
    }
    pub fn sharpen_on(&self) -> bool {
        self.sharpen > 0.005
    }
    pub fn saturation_on(&self) -> bool {
        (self.saturation - 1.0).abs() > 0.005
    }
    /// Anything the composite pass does (everything but FXAA).
    pub fn composite_on(&self) -> bool {
        self.bloom_on() || self.tonemap || self.sharpen_on() || self.saturation_on()
    }
    /// Whether the post pass runs at all; false = the render path is exactly the one without it.
    pub fn active(&self) -> bool {
        self.fxaa || self.composite_on()
    }
}

/// Server names compare without case or outer spaces ("PlayOnline", "playonline").
fn same_server(a: &str, b: &str) -> bool {
    a.trim().eq_ignore_ascii_case(b.trim())
}

#[derive(Clone, Serialize, Deserialize)]
#[serde(default)]
pub struct Config {
    /// Holds the "FINAL FANTASY XI" folder, laid out as the Windows installer does.
    pub game_dir: PathBuf,
    pub installed: bool,

    pub server: String,
    /// The login's account; the Square Enix ID for PlayOnline.
    pub username: String,
    /// PlayOnline's member ID (8 characters), for the PlayOnline server.
    pub pol_id: String,
    /// Logins that worked, most recent first: the login screen's Server and Account lists (not retail).
    pub logins: Vec<SavedLogin>,
    /// The login screen's Remember password (not retail), and the password sealed for this server and account
    /// (secret.rs; hex, empty when none).
    pub remember_password: bool,
    pub saved_password: String,
    pub auth_port: u16,
    pub data_port: u16,
    pub view_port: u16,
    pub profile_port: u16,
    pub irc_port: u16,
    /// Named servers with their own address and ports (not retail; `resolved`).
    pub named_servers: Vec<NamedServer>,
    /// Not retail: only named servers with `social` set get the friend list, presence and mail; every other server
    /// gets none of them (no connection to its profile ports).
    pub social_named_only: bool,
    /// Not retail: the xiloader version reported at login ("2.1.2"); empty = the client's own (net::auth).
    pub loader_version: String,
    /// Version string sent to the lobby; LSB rejects clients older than its CLIENT_VER.
    pub client_version: String,
    /// cpal output device id ("pipewire:..."); empty = the system default.
    pub audio_device: String,
    /// Frame limit in frames per second (one of FRAME_LIMITS), 0 = unlimited. Not a retail option;
    /// game ticks stay at 60 Hz and motions at 30 frames a second whatever this is.
    pub frame_limit: u32,
    /// Anisotropic filtering for scenery, models and the creator (1 = off, up to 16). Not a retail option.
    pub anisotropy: u16,
    /// How far scenery, actors and effects draw, in percent of retail's distance (the zone's, scaled by the
    /// Clipping setting); 0 = no limit. Not a retail option.
    pub draw_distance: u32,
    /// Party and alliance rows show TP (retail config 0xae bit 0, default off; ours on, as the add-ons do).
    pub party_tp: bool,
    /// Extra: the map overlay (Ctrl / Alt + O; the add-ons' map overlay) and its opacity 0..1.
    pub map_overlay: bool,
    pub map_overlay_opacity: f32,
    /// Extra: Synthesize asks how many and repeats.
    pub synth_amount: bool,
    /// Extra (the timestamp add-on): retail's chat timestamps (config 0xb5) on every log line; seconds while 0xb5 is
    /// off.
    pub stamp_all_lines: bool,
    /// Extra (the distance / target-info add-ons): the target's distance in the target window, and its HP percent in the
    /// classic one (the modern one shows it anyway).
    pub target_distance: bool,
    pub target_hpp: bool,
    /// Not retail (Settings' Lamp Lights): real point lights at the zones' lamps in place of their baked lamplight
    /// (client/lamps.rs).
    pub lamp_lights: bool,
    /// Extra (the clock add-ons): Earth time, the moon and the next day beside the Vana'diel clock (client/clock.rs).
    pub earth_clock: bool,
    /// Ours (not retail, client/era.rs): while the server's lobby bits name no expansion the client hides the windows of
    /// later systems, offers the base jobs only and caps its own level fields at 60. Always on and never read from the
    /// file: what a character sees follows only what its server reports (a server unlocks by sending the bits).
    #[serde(skip, default = "era_lock_on")]
    pub era_lock: bool,
    /// Ours (not retail): the classic UI's scale. 0 = the Menu Size (0037 / 0038) as retail, 1 = Auto (100% up to
    /// 1080 lines, then the window's height over 1080), else a percent. It keeps the window's shape.
    #[serde(default = "ui_scale_auto")]
    pub ui_scale: u32,
    /// Ours: the map (and search) server address to use instead of the one the lobby (and each zone change) names, its ports
    /// kept; for a server reached through a proxy or a NAT that hands out an address the client cannot reach.
    pub map_host: Option<std::net::Ipv4Addr>,
    /// The lobby's expansion bits at the last login by server and account (`era::seen_key`): a bit set that was not
    /// there then is announced once.
    pub expansions_seen: std::collections::BTreeMap<String, u32>,
    /// Extra (the trust chatter filters): trusts' party lines (battle message 711) are not printed.
    pub hide_trust_speech: bool,
    /// Extra (Battlemod's filters): "readies" / "starts casting" lines only for us and monsters.
    pub hide_ready_lines: bool,
    /// Extras (Battlemod's simplify and colours, client/battlemod.rs): battle lines in their short form; names in
    /// battle lines coloured by who they are.
    pub short_battle: bool,
    pub battle_name_colours: bool,
    /// Extra (the text auto-advance add-ons): an event message waiting for a key goes on by itself after this many
    /// seconds; 0 off.
    pub auto_advance: u32,
    /// Extra (the Timers add-on): the timers window, its dock (0 left, 1 right, 2 top), its drawer out, folded
    /// sections (a bit each).
    pub timers: bool,
    pub timers_dock: u32,
    pub timers_out: bool,
    pub timers_folded: u8,
    /// Extra (ours): the training regime window (client/regime.rs) and its drawer out.
    pub regime: bool,
    pub regime_out: bool,
    /// Extra (the skillchain add-ons): in a party, the chains it can make and the open one on our target.
    pub skillchain_helper: bool,
    /// Ours (client/rotation.rs): the one-button rotation presses itself while engaged; each session starts so, and
    /// /autocast on | off flips only the session.
    pub rotation_autocast: bool,
    /// Extra (the minimap add-ons): the minimap, its place (0 top right, 1 top left), size (0..2) and the map pixels
    /// across (the wheel's zoom).
    pub minimap: bool,
    /// Ours: the modern UI's minimap (on unless turned off; the classic UI keeps `minimap`, an Extra off by default), and
    /// whether the minimap shows a zone's map without its key item (the map window keeps retail's rule).
    pub modern_minimap: bool,
    pub minimap_unowned: bool,
    pub minimap_dock: u32,
    pub minimap_size: u32,
    pub minimap_span: f32,
    /// Not retail (client/gamepad.rs): gamepad input on; the sticks' deadzone as a share of their travel (0..0.8) and
    /// the right stick's camera speed as a multiple of the keys'.
    pub gamepad: bool,
    pub gamepad_deadzone: f32,
    pub gamepad_camera_speed: f32,
    /// Not retail (client/controls.rs): the keyboard and mouse scheme. 0 Original (retail's keyboard as the game
    /// Config's Keyboard type sets it), 1 FFXI WASD (retail's keyboard type 2), 2 Modern (WASD and the mouse as in
    /// WoW, the default). `controls_ad_turn`: under Modern, A / D turn the character and Q / E strafe (default: A / D
    /// strafe and Q / E turn).
    pub controls: u32,
    pub controls_ad_turn: bool,
    /// Ours: resting's ticks as timed on the first rest seen, [first heal, interval, the server's look period] in
    /// seconds (client/resttick.rs).
    pub rest_tick: Option<[f32; 3]>,
    /// The drawn cursor's size (config 0021 off) in percent of retail's pixels on screen; 0 = auto (grows with the
    /// window height from 720). Not retail: it was sized for 640 x 480. The .ani cursors keep their own size.
    pub cursor_size: u32,
    /// Ours (user, 2026-10-25): containers whose sort window's Auto stays on, bit = container: a new item there sorts
    /// it again. Retail's Auto sorts once; Manual turns ours off.
    pub auto_sort: u32,
    /// The "FINAL FANTASY XI Config" tool's values by registry name (HKLM\...\FinalFantasyXI\0000..0043,
    /// read at start-up by FUN_10016c30); missing ones take TOOL_DEFAULTS.
    pub tool: std::collections::BTreeMap<String, u32>,
    /// Projection aspect from the config ratio (0x43 / 0xab, FUN_100147a0) instead of the window's. Not retail's
    /// default: retail always used the ratio.
    pub retail_aspect: bool,
    /// The monitor full screen and borderless go on, by its name (empty = the first). Not retail: Wayland can't
    /// tell which monitor is the main one.
    pub monitor: String,
    /// The graphics adapter by name (empty = the high-performance one); read at start-up. Not retail.
    pub gpu: String,
    /// Set once a software adapter (WARP, llvmpipe) was first seen and the background was halved for it. Not retail.
    pub software_gpu_seen: bool,
    /// Ours (not retail): optional post-processing over the 3D scene, all off by default (render/post.rs).
    pub graphics: GraphicsCfg,
    /// FFXiMain's own options by config id (the in-game and lobby Config menus).
    pub game: crate::gamecfg::GameConfig,
    /// DAT overlays (not retail; dat::overlay): folders under mods_dir(), highest priority first.
    pub mods: Vec<ModRef>,
    /// Not retail (docs/modern-ui.md): the modern UI layer instead of the retail HUD windows it replaces, its panels'
    /// places by character, then panel, and the chat window's font size in points.
    pub modern_ui: bool,
    /// The modern layer's size in percent of its 1080-line design.
    pub modern_scale: u32,
    /// How opaque the modern windows' backgrounds are (0.1 ..= 1).
    pub modern_opacity: f32,
    pub modern_places: std::collections::BTreeMap<String, ModernLayout>,
    pub modern_chat_font: f32,
    /// The modern edge windows folded to their tabs, by panel (the minimap, Wide Scan).
    pub modern_folded: std::collections::BTreeMap<String, bool>,
    /// The Wide Scan flyout's kinds shown: 1 players, 2 NPCs, 4 monsters.
    pub modern_scan_kinds: u8,
    /// The modern chat's All tab shows the battle lines too (the Battle tab has them alone).
    pub modern_battle_in_all: bool,
    /// The modern chat merges an action's lines that differ only in their number (BattleMod's condensing).
    pub modern_condense: bool,
    /// The list search's recent picks by character, newest first (listsearch.rs).
    pub modern_recent: std::collections::BTreeMap<String, Vec<String>>,
}

/// A modern UI panel's place: its left and top (or, for the panels that grow upward, its bottom `b`) as fractions of the
/// screen, so it keeps its place whatever the Interface Size or the resolution; for the chat window its room in points
/// (0: the default); or docked on another panel.
#[derive(Clone, Debug, Default, PartialEq, Serialize, Deserialize)]
#[serde(default)]
pub struct ModernPlace {
    pub x: f32,
    pub y: f32,
    pub w: f32,
    pub h: f32,
    pub b: f32,
    pub dock: Option<ModernDock>,
    /// An edge window let go away from the edges: it stands at x / y with its whole frame.
    pub float: bool,
    /// An edge window held by the top (1) or the bottom (2) edge, x its left; 0 the left or right edge by x's sign.
    pub edge: u8,
}

/// A panel sitting on another: `gap` points between its bottom and the other's top, `dx` from the other's left, or
/// from its right (`right`) for one placed from the right edge, whose left moves as it folds or grows.
#[derive(Clone, Debug, Default, PartialEq, Serialize, Deserialize)]
pub struct ModernDock {
    pub to: String,
    pub gap: f32,
    pub dx: f32,
    #[serde(default)]
    pub right: bool,
}

/// A character's panel places by panel id.
pub type ModernLayout = std::collections::BTreeMap<String, ModernPlace>;

#[derive(Clone, Debug, Serialize, Deserialize, PartialEq)]
pub struct ModRef {
    pub name: String,
    pub enabled: bool,
}

/// Where mod folders live.
pub fn mods_dir() -> PathBuf {
    data_dir().join("mods")
}

/// The enabled mods' folders, highest priority first (none with FFXI_NO_MODS set).
pub fn enabled_mod_dirs() -> Vec<PathBuf> {
    if std::env::var_os("FFXI_NO_MODS").is_some() {
        return Vec::new();
    }
    Config::load().mods.iter().filter(|m| m.enabled).map(|m| mods_dir().join(&m.name)).filter(|d| d.is_dir()).collect()
}

/// Merged overlay DATs (rebuilt when a source changes).
pub fn merged_dir() -> PathBuf {
    app_dir(dirs::cache_dir()).join("merged")
}

/// Config-tool values with our defaults (FFXiMain's own default in the comment where it differs).
pub const TOOL_DEFAULTS: &[(&str, u32)] = &[
    ("0000", 1),    // MIP mapping (FFXiMain 0)
    ("0001", 1280), // window width (FFXiMain 640, the tool 800)
    ("0002", 800),  // window height (480 / 600)
    ("0003", 0),    // background width, 0 = the window's (FFXiMain 512, the tool 800)
    ("0004", 0),    // background height (512 / 600)
    ("0007", 1),    // sound
    ("0011", 2),    // environment animation (FFXiMain 1)
    ("0017", 1),    // bump mapping (FFXiMain 0)
    ("0018", 1),    // texture compression
    ("0019", 1),    // map compression
    ("0021", 0),    // hardware mouse
    ("0022", 0),    // opening movie (ours: skipped unless asked for; retail 1)
    ("0023", 0),    // simplified character creation
    ("0028", 0),    // gamma base 0.0
    ("0029", 12),   // sound effect channels
    ("0030", 0),    // 3D LCD mode
    ("0034", 1),    // window mode (FFXiMain 0 full screen)
    ("0035", 1),    // sound in the background (FFXiMain 0)
    ("0036", 0),    // font quality
    ("0037", 0),    // UI width, 0 = the window's
    ("0038", 0),    // UI height
    ("0040", 0),    // graphics stabilization
    ("0043", 0),    // screenshots at screen size
];

/// Choices for `frame_limit` (0 = unlimited).
pub const FRAME_LIMITS: [u32; 14] = [30, 60, 75, 90, 100, 120, 144, 165, 180, 200, 240, 300, 360, 0];

impl Default for Config {
    fn default() -> Self {
        Self {
            game_dir: data_dir().join("game"),
            installed: false,
            server: "127.0.0.1".into(),
            username: String::new(),
            pol_id: String::new(),
            logins: Vec::new(),
            remember_password: false,
            saved_password: String::new(),
            auth_port: 54231,
            data_port: 54230,
            view_port: 54001,
            profile_port: 51220,
            irc_port: 51240,
            named_servers: Vec::new(),
            social_named_only: false,
            loader_version: String::new(),
            client_version: "30261006_0".into(),
            audio_device: String::new(),
            frame_limit: 300,
            anisotropy: 16,
            draw_distance: 0,
            party_tp: true,
            map_overlay: false,
            map_overlay_opacity: 0.6,
            synth_amount: false,
            stamp_all_lines: false,
            target_distance: false,
            target_hpp: false,
            earth_clock: false,
            era_lock: true,
            ui_scale: UI_SCALE_AUTO,
            map_host: None,
            expansions_seen: Default::default(),
            lamp_lights: true,
            hide_trust_speech: false,
            hide_ready_lines: false,
            short_battle: false,
            battle_name_colours: false,
            auto_advance: 0,
            timers: false,
            timers_dock: 0,
            timers_out: true,
            timers_folded: 0,
            regime: false,
            skillchain_helper: false,
            rotation_autocast: true,
            regime_out: true,
            minimap: false,
            modern_minimap: true,
            minimap_unowned: true,
            minimap_dock: 0,
            minimap_size: 1,
            minimap_span: 160.0,
            gamepad: true,
            gamepad_deadzone: crate::client::gamepad::DEFAULT_DEADZONE,
            gamepad_camera_speed: crate::client::gamepad::DEFAULT_CAMERA_SPEED,
            controls: 2,
            controls_ad_turn: false,
            rest_tick: None,
            cursor_size: 0,
            auto_sort: 0,
            mods: Vec::new(),
            modern_ui: true,
            modern_scale: 60,
            modern_opacity: 0.85,
            modern_places: Default::default(),
            modern_chat_font: 15.0,
            modern_folded: Default::default(),
            modern_scan_kinds: 7,
            modern_battle_in_all: true,
            modern_condense: true,
            modern_recent: Default::default(),
            tool: Default::default(),
            retail_aspect: false,
            monitor: String::new(),
            gpu: String::new(),
            software_gpu_seen: false,
            graphics: Default::default(),
            game: Default::default(),
        }
    }
}

impl Config {
    /// The cursor's on-screen scale for a window `height` pixels high.
    pub fn cursor_scale(&self, height: u32) -> f32 {
        match self.cursor_size {
            0 => ((height as f32 / 720.0) * 2.0).round().max(2.0) / 2.0,
            n => n as f32 / 100.0,
        }
    }

    pub fn load() -> Self {
        let mut c: Self = std::fs::read(config_path()).ok().and_then(|b| serde_json::from_slice(&b).ok()).unwrap_or_default();
        // A config from before the lists: its one login starts them.
        if c.logins.is_empty() && !c.server.trim().is_empty() && !c.username.trim().is_empty() {
            c.remember_login();
        }
        c.gamepad_deadzone = c.gamepad_deadzone.clamp(0.0, crate::client::gamepad::MAX_DEADZONE);
        c.gamepad_camera_speed = c.gamepad_camera_speed.clamp(0.1, 5.0);
        c.controls = c.controls.min(2);
        c
    }

    /// A copy to connect with: when `server` names one of `named_servers`, its address and ports replace the
    /// config's. Saved logins and passwords stay keyed by the name.
    pub fn resolved(&self) -> Self {
        let mut c = self.clone();
        if let Some(n) = self.named_servers.iter().find(|n| same_server(&n.name, &self.server)) {
            c.server = n.host.trim().to_string();
            c.auth_port = n.auth_port.unwrap_or(c.auth_port);
            c.data_port = n.data_port.unwrap_or(c.data_port);
            c.view_port = n.view_port.unwrap_or(c.view_port);
            c.profile_port = n.profile_port.unwrap_or(c.profile_port);
            c.irc_port = n.irc_port.unwrap_or(c.irc_port);
            if let Some(v) = &n.loader_version {
                c.loader_version = v.clone();
            }
        }
        c
    }

    /// The loader version to report: `loader_version` as "major.minor.patch", or None for the client's own.
    pub fn loader_version(&self) -> Option<[u8; 3]> {
        let v: Vec<u8> = self.loader_version.trim().split('.').map(|p| p.parse().ok()).collect::<Option<_>>()?;
        v.try_into().ok()
    }

    /// Whether this login uses the server's profile service (friend list, presence, mail).
    pub fn social_enabled(&self) -> bool {
        let named = self.named_servers.iter().find(|n| same_server(&n.name, &self.server));
        named.and_then(|n| n.social).unwrap_or(!self.social_named_only)
    }

    /// The servers logged in to, most recent first, then the named servers not logged in to yet.
    pub fn servers(&self) -> Vec<String> {
        let mut out: Vec<String> = Vec::new();
        for l in self.logins.iter().map(|l| &l.server).chain(self.named_servers.iter().map(|n| &n.name)) {
            if !l.trim().is_empty() && !out.iter().any(|s| same_server(s, l)) {
                out.push(l.clone());
            }
        }
        out
    }

    /// The accounts logged in with on a server, most recent first.
    pub fn accounts(&self, server: &str) -> Vec<String> {
        self.logins.iter().filter(|l| same_server(&l.server, server)).map(|l| l.username.clone()).collect()
    }

    /// The saved login for a server and account; with no account, the server's most recent.
    pub fn saved_login(&self, server: &str, username: Option<&str>) -> Option<&SavedLogin> {
        self.logins.iter().find(|l| same_server(&l.server, server) && username.is_none_or(|u| l.username == u))
    }

    /// Makes a saved login the form's: its server, account, PlayOnline ID, Remember password and sealed passwords.
    pub fn use_login(&mut self, l: &SavedLogin) {
        self.server = l.server.clone();
        self.username = l.username.clone();
        self.pol_id = l.pol_id.clone();
        self.remember_password = l.remember_password;
        self.saved_password = l.saved_password.clone();
    }

    /// The form's login, first in the lists (after a login that worked, or a change to its Remember password).
    pub fn remember_login(&mut self) {
        let l = SavedLogin {
            server: self.server.trim().to_string(),
            username: self.username.trim().to_string(),
            pol_id: self.pol_id.clone(),
            remember_password: self.remember_password,
            saved_password: self.saved_password.clone(),
        };
        self.logins.retain(|o| !(same_server(&o.server, &l.server) && o.username == l.username));
        self.logins.insert(0, l);
    }

    /// Drops a saved login (with its password); with no account, every login of the server.
    pub fn forget_login(&mut self, server: &str, username: Option<&str>) {
        self.logins.retain(|l| !(same_server(&l.server, server) && username.is_none_or(|u| l.username == u)));
    }

    pub fn save(&self) -> Result<()> {
        let path = config_path();
        std::fs::create_dir_all(path.parent().unwrap())?;
        std::fs::write(path, serde_json::to_vec_pretty(self)?)?;
        Ok(())
    }

    pub fn ffxi_dir(&self) -> PathBuf {
        self.game_dir.join("FINAL FANTASY XI")
    }

    /// A Config-tool value (registry name "0000".."0043").
    pub fn tool(&self, name: &str) -> u32 {
        self.tool.get(name).copied().or_else(|| TOOL_DEFAULTS.iter().find(|d| d.0 == name).map(|d| d.1)).unwrap_or(0)
    }

    /// Sets a Config-tool value; the default is not stored.
    pub fn set_tool(&mut self, name: &str, v: u32) {
        if TOOL_DEFAULTS.iter().any(|d| d.0 == name && d.1 == v) {
            self.tool.remove(name);
        } else {
            self.tool.insert(name.to_string(), v);
        }
    }

    /// Window size (0001 / 0002).
    pub fn window_size(&self) -> [u32; 2] {
        [self.tool("0001"), self.tool("0002")].map(|v| v.clamp(320, 16384))
    }

    /// Window mode 0034: 0 full screen, 1 windowed, 2 borderless at the window size, 3 borderless at the
    /// desktop size.
    pub fn window_mode(&self) -> u32 {
        self.tool("0034").min(3)
    }

    /// The scene's size for a window of `window` pixels (0003 / 0004; 0 = the window's, not retail).
    pub fn background(&self, window: [u32; 2]) -> [u32; 2] {
        match [self.tool("0003"), self.tool("0004")] {
            [w, h] if w > 0 && h > 0 => [w.min(8192), h.min(8192)],
            _ => window,
        }
    }

    /// The UI layout size (0037 / 0038, 0 = the window's): laid out there and stretched to the window.
    pub fn ui_size(&self, window: [u32; 2]) -> [u32; 2] {
        // Ours: UI Scale lays the UI out at the window's size over the scale, so it keeps the window's shape.
        if let Some(k) = ui_scale_factor(self.ui_scale, window) {
            return [((window[0] as f32 / k).round() as u32).max(320), ((window[1] as f32 / k).round() as u32).max(240)];
        }
        match [self.tool("0037"), self.tool("0038")] {
            [w, h] if w >= 320 && h >= 240 => [w.min(window[0].max(320) * 4), h.min(window[1].max(240) * 4)],
            _ => window,
        }
    }

    /// Gamma base 0028 (an f32 in the DWORD, -1..1).
    pub fn gamma_base(&self) -> f32 {
        f32::from_bits(self.tool("0028")).clamp(-1.0, 1.0)
    }

    /// The frame limit in effect: FFXI_FRAME_LIMIT overrides the file (test runs), 0 = unlimited.
    pub fn frame_limit(&self) -> u32 {
        std::env::var("FFXI_FRAME_LIMIT").ok().and_then(|v| v.parse().ok()).unwrap_or(self.frame_limit)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    /// A config from before `graphics`, and one naming only fxaa, keep every other option off / neutral.
    #[test]
    fn graphics_defaults_are_off() {
        let d = Config::default().graphics;
        assert!(!d.active() && !d.fxaa && !d.bloom && !d.tonemap && d.sharpen == 0.0 && d.saturation == 1.0 && d.exposure == 1.0);
        let c: Config = serde_json::from_str("{}").unwrap();
        assert_eq!(c.graphics, GraphicsCfg::default());
        let c: Config = serde_json::from_str(r#"{"graphics":{"fxaa":true}}"#).unwrap();
        assert!(c.graphics.fxaa && c.graphics.active() && !c.graphics.composite_on());
        assert_eq!(GraphicsCfg { fxaa: false, ..c.graphics }, GraphicsCfg::default());
        // Bloom at zero intensity, sharpen 0 and saturation 1 do nothing.
        assert!(!GraphicsCfg { bloom: true, bloom_intensity: 0.0, ..Default::default() }.active());
        assert!(GraphicsCfg { sharpen: 0.5, ..Default::default() }.composite_on());
        assert!(GraphicsCfg { saturation: 0.0, ..Default::default() }.composite_on());
    }

    #[test]
    fn ui_scale_keeps_the_window_shape_and_auto_is_retail_up_to_1080() {
        let mut c = Config::default();
        assert_eq!(c.ui_scale, UI_SCALE_AUTO);
        assert_eq!(c.ui_size([1920, 1080]), [1920, 1080]);
        assert_eq!(c.ui_size([1280, 800]), [1280, 800]);
        assert_eq!(c.ui_size([3840, 2160]), [1920, 1080]);
        assert_eq!(c.ui_size([2560, 1440]), [1920, 1080]);
        c.ui_scale = 150;
        assert_eq!(c.ui_size([1920, 1080]), [1280, 720]);
        // Menu Size: retail's 0037 / 0038 (0: the window).
        c.ui_scale = 0;
        assert_eq!(c.ui_size([3840, 2160]), [3840, 2160]);
    }

    #[test]
    fn named_server_resolves_address_and_ports() {
        let mut c = Config { server: " Example ".into(), ..Default::default() };
        c.named_servers.push(NamedServer { name: "example".into(), host: "example.invalid".into(), auth_port: Some(1), view_port: Some(3), ..Default::default() });
        let r = c.resolved();
        assert_eq!((r.server.as_str(), r.auth_port, r.data_port, r.view_port), ("example.invalid", 1, c.data_port, 3));
        assert!(c.servers().iter().any(|s| s == "example"));
        // A plain address is left alone.
        c.server = "127.0.0.1".into();
        assert_eq!(c.resolved().server, "127.0.0.1");
    }

    #[test]
    fn loader_version_parses_and_follows_the_named_server() {
        let mut c = Config::default();
        assert_eq!(c.loader_version(), None);
        c.loader_version = "2.2.0".into();
        c.named_servers.push(NamedServer { name: "old".into(), host: "example.invalid".into(), loader_version: Some("2.1.2".into()), ..Default::default() });
        assert_eq!(c.loader_version(), Some([2, 2, 0]));
        c.server = "old".into();
        assert_eq!(c.resolved().loader_version(), Some([2, 1, 2]));
        c.loader_version = "2.x".into();
        c.server = "other".into();
        assert_eq!(c.resolved().loader_version(), None);
    }

    #[test]
    fn social_follows_the_named_server() {
        let mut c = Config::default();
        c.named_servers.push(NamedServer { name: "on".into(), social: Some(true), ..Default::default() });
        c.named_servers.push(NamedServer { name: "off".into(), social: Some(false), ..Default::default() });
        c.named_servers.push(NamedServer { name: "unset".into(), ..Default::default() });
        let on = |c: &Config, s: &str| Config { server: s.into(), ..c.clone() }.social_enabled();
        assert!(on(&c, "on") && !on(&c, "off") && on(&c, "unset") && on(&c, "10.0.0.1"));
        c.social_named_only = true;
        assert!(on(&c, "on") && !on(&c, "off") && !on(&c, "unset") && !on(&c, "10.0.0.1"));
    }
}
