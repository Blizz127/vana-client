//! A launcher's read-only friends feed: one HTTPS GET of a snapshot URL the launcher handed over (VANA_LOGIN_FILE's
//! "friends_feed"), with a bearer token, polled on a background thread while the player is in the world. The snapshot
//! fills the Friend List (client/friends.rs) when the game server has no profile service. Nothing is ever written back.

use serde::{Deserialize, Deserializer};
use std::path::PathBuf;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Arc, mpsc};
use std::time::Duration;

/// How often the snapshot is fetched, and how often after a failure.
const POLL: Duration = Duration::from_secs(20);
const BACKOFF: Duration = Duration::from_secs(60);
const TIMEOUT: Duration = Duration::from_secs(10);
/// A snapshot is a short list of names; anything larger is not one.
const MAX_BODY: u64 = 2 * 1024 * 1024;

/// Where the bearer token comes from.
#[derive(Clone, PartialEq, Eq)]
pub enum TokenSource {
    /// Given in the login file: it cannot be refreshed, so a 401 ends the feed.
    Inline(String),
    /// A file the launcher keeps current (the token, or JSON {"token": ...}); the client only reads it.
    File(PathBuf),
}

/// Where the feed is and the token that opens it. The token is never printed.
#[derive(Clone, PartialEq, Eq)]
pub struct FeedCred {
    pub url: String,
    pub token: TokenSource,
}

impl std::fmt::Debug for FeedCred {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        let kind = match self.token {
            TokenSource::Inline(_) => "<redacted>",
            TokenSource::File(_) => "<redacted: from a file>",
        };
        f.debug_struct("FeedCred").field("url", &"<hidden>").field("token", &kind).finish()
    }
}

/// A token file's content: the bare token, or JSON {"token": ...}. Empty: none.
fn parse_token(text: &str) -> Option<String> {
    let t = text.trim();
    let token = if t.starts_with('{') { serde_json::from_str::<serde_json::Value>(t).ok()?.get("token")?.as_str()?.trim().to_string() } else { t.to_string() };
    (!token.is_empty()).then_some(token)
}

impl TokenSource {
    /// The token now (a file is read afresh each time; unreadable, oversized or empty: none).
    pub fn read(&self) -> Option<String> {
        match self {
            Self::Inline(t) => Some(t.clone()),
            Self::File(p) => {
                if std::fs::metadata(p).ok()?.len() > 16 * 1024 {
                    return None;
                }
                parse_token(&std::fs::read_to_string(p).ok()?)
            }
        }
    }

    fn refreshable(&self) -> bool {
        matches!(self, Self::File(_))
    }
}

impl FeedCred {
    fn https(url: &str) -> Option<String> {
        let url = url.trim();
        (url.len() > "https://".len() && url.get(..8).is_some_and(|p| p.eq_ignore_ascii_case("https://"))).then(|| url.to_string())
    }

    /// A feed with its token inline: https only (the token travels in a header) and a non-empty token.
    pub fn new(url: &str, token: &str) -> Option<Self> {
        let token = token.trim();
        Some(Self { url: Self::https(url)?, token: TokenSource::Inline((!token.is_empty()).then(|| token.to_string())?) })
    }

    /// A feed whose token the launcher keeps in a file.
    pub fn with_token_file(url: &str, path: &str) -> Option<Self> {
        let path = path.trim();
        Some(Self { url: Self::https(url)?, token: TokenSource::File((!path.is_empty()).then(|| PathBuf::from(path))?) })
    }

    /// The optional "friends_feed" of a launcher's login file: {"url", "token"} or {"url", "token_file"} (the file
    /// wins when both are there); anything malformed is no feed.
    pub fn from_login(file: &serde_json::Value) -> Option<Self> {
        let f = file.get("friends_feed")?;
        let url = f.get("url")?.as_str()?;
        match f.get("token_file").and_then(|v| v.as_str()) {
            Some(p) => Self::with_token_file(url, p),
            None => Self::new(url, f.get("token")?.as_str()?),
        }
    }
}

/// One game a friend is in now.
#[derive(Clone, Debug, Default, Deserialize, PartialEq)]
#[serde(default)]
pub struct InGame {
    pub app_id: Option<String>,
    pub title: Option<String>,
    pub character: Option<String>,
    pub zone: Option<String>,
}

/// One friend of the snapshot. Every field is optional; unknown ones are ignored.
#[derive(Clone, Debug, Default, Deserialize, PartialEq)]
#[serde(default)]
pub struct FeedFriend {
    pub username: Option<String>,
    pub state: Option<String>,
    pub game: Option<String>,
    pub playing: Option<serde_json::Value>,
    #[serde(deserialize_with = "lenient")]
    pub in_game: Vec<InGame>,
    pub role: Option<String>,
}

/// The snapshot. `incoming` and `outgoing` (requests) are read but not shown; the two flags say what the service
/// fills in (absent: unknown).
#[derive(Clone, Debug, Default, Deserialize, PartialEq)]
#[serde(default)]
pub struct Snapshot {
    #[serde(deserialize_with = "lenient")]
    pub friends: Vec<FeedFriend>,
    #[serde(deserialize_with = "lenient")]
    pub incoming: Vec<serde_json::Value>,
    #[serde(deserialize_with = "lenient")]
    pub outgoing: Vec<serde_json::Value>,
    pub playing_supported: Option<bool>,
    pub in_game_supported: Option<bool>,
}

/// A list (or null) whose bad elements are dropped instead of failing the whole snapshot.
fn lenient<'de, D: Deserializer<'de>, T: serde::de::DeserializeOwned>(d: D) -> Result<Vec<T>, D::Error> {
    let items = Option::<Vec<serde_json::Value>>::deserialize(d).unwrap_or(None);
    Ok(items.unwrap_or_default().into_iter().filter_map(|v| serde_json::from_value(v).ok()).collect())
}

impl Snapshot {
    /// A JSON object (a list or a bare value is not a snapshot).
    pub fn parse(body: &[u8]) -> Result<Self, serde_json::Error> {
        match serde_json::from_slice::<serde_json::Value>(body)? {
            v @ serde_json::Value::Object(_) => serde_json::from_value(v),
            _ => Err(serde::de::Error::custom("not an object")),
        }
    }
}

impl FeedFriend {
    /// The Friend List's status: 0 offline, 1 online, 2 away (anything else is offline).
    pub fn status(&self) -> u8 {
        match self.state.as_deref().map(str::trim) {
            Some(s) if s.eq_ignore_ascii_case("online") => 1,
            Some(s) if s.eq_ignore_ascii_case("away") => 2,
            _ => 0,
        }
    }

    /// What the list's location column says: "<character> - <zone>" of the first game they are in, else the game's
    /// title while they are online or away, else nothing.
    pub fn location(&self) -> String {
        let text = |s: &Option<String>| s.as_deref().map(str::trim).filter(|s| !s.is_empty()).map(str::to_string);
        if let Some(g) = self.in_game.first() {
            let place = match (text(&g.character), text(&g.zone)) {
                (Some(c), Some(z)) => Some(format!("{c} - {z}")),
                (c, z) => c.or(z),
            };
            if let Some(p) = place.or_else(|| text(&g.title)) {
                return p;
            }
        }
        if self.status() != 0 { text(&self.game).unwrap_or_default() } else { String::new() }
    }
}

enum Fetch {
    /// The token is no longer accepted: it is never sent again.
    Expired,
    /// Anything else; the reason carries no URL or token.
    Failed(String),
}

fn fetch(agent: &ureq::Agent, url: &str, token: &str) -> Result<Snapshot, Fetch> {
    // Marked sensitive so the http types never print it.
    let mut auth = ureq::http::HeaderValue::from_str(&format!("Bearer {token}")).map_err(|_| Fetch::Failed("unusable token".into()))?;
    auth.set_sensitive(true);
    let mut resp = agent.get(url).header("Authorization", auth).header("Accept", "application/json").call().map_err(|e| {
        Fetch::Failed(match e {
            ureq::Error::Timeout(_) => "timed out".into(),
            ureq::Error::HostNotFound | ureq::Error::ConnectionFailed | ureq::Error::Io(_) => "connection failed".into(),
            _ => "request failed".into(),
        })
    })?;
    match resp.status().as_u16() {
        401 | 403 => return Err(Fetch::Expired),
        200..=299 => {}
        s => return Err(Fetch::Failed(format!("status {s}"))),
    }
    let body = resp.body_mut().with_config().limit(MAX_BODY).read_to_vec().map_err(|_| Fetch::Failed("unreadable body".into()))?;
    Snapshot::parse(&body).map_err(|_| Fetch::Failed("not a snapshot".into()))
}

/// After a 401 / 403 with `used`: the token to go on with. `read` is the token source, `pause` waits a minute and says
/// whether to go on (false: stopped). The first look is at once; while the token is still `used` (or there is none)
/// nothing is sent to the URL, and the source is looked at again after each pause.
fn next_token(mut read: impl FnMut() -> Option<String>, used: &str, mut pause: impl FnMut() -> bool) -> Option<String> {
    loop {
        if let Some(t) = read().filter(|t| t != used) {
            return Some(t);
        }
        if !pause() {
            return None;
        }
    }
}

/// The last token the service turned away. It outlives a poller: a new world (another character, a login after a
/// logout) starts from the same login file's token and must not send it again.
static REJECTED: std::sync::Mutex<Option<String>> = std::sync::Mutex::new(None);

fn reject(token: &str) {
    *REJECTED.lock().unwrap_or_else(|e| e.into_inner()) = Some(token.to_string());
}

fn rejected(token: &str) -> bool {
    REJECTED.lock().unwrap_or_else(|e| e.into_inner()).as_deref() == Some(token)
}

/// The running poller. Dropping it (the world is gone: logout) stops the thread.
pub struct Feed {
    pub snapshots: mpsc::Receiver<Snapshot>,
    stop: Arc<AtomicBool>,
}

impl Drop for Feed {
    fn drop(&mut self) {
        self.stop.store(true, Ordering::Relaxed);
    }
}

/// Polls every 20 s, every 60 s while failing. After a 401 / 403 the old token is not sent again: an inline token
/// ends the feed (one note in the log); a token file is read again and the polling waits, off the network, until the
/// launcher has put a new token in it.
pub fn spawn(cred: FeedCred) -> Feed {
    let (tx, rx) = mpsc::channel();
    let stop = Arc::new(AtomicBool::new(false));
    let flag = stop.clone();
    std::thread::spawn(move || {
        // Redirects are not followed: the token goes to the given URL and nowhere else.
        let agent: ureq::Agent = ureq::Agent::config_builder()
            .timeout_global(Some(TIMEOUT))
            .max_redirects(0)
            .http_status_as_error(false)
            .user_agent(concat!("vana-client/", env!("CARGO_PKG_VERSION")))
            .build()
            .into();
        // Waits; false once stopped.
        let sleep = |d: Duration| {
            let until = std::time::Instant::now() + d;
            while std::time::Instant::now() < until {
                if flag.load(Ordering::Relaxed) {
                    return false;
                }
                std::thread::sleep(Duration::from_millis(200));
            }
            !flag.load(Ordering::Relaxed)
        };
        let mut token = cred.token.read();
        let mut failing = false;
        while !flag.load(Ordering::Relaxed) {
            // A token file that is not there yet (or empty) is looked at again in a minute.
            let Some(t) = token.take() else {
                if !sleep(BACKOFF) {
                    return;
                }
                token = cred.token.read();
                continue;
            };
            let got = if rejected(&t) { Err(Fetch::Expired) } else { fetch(&agent, &cred.url, &t) };
            let wait = match got {
                Ok(s) => {
                    if failing {
                        log::info!("friends feed: back");
                    }
                    failing = false;
                    if tx.send(s).is_err() {
                        return;
                    }
                    POLL
                }
                Err(Fetch::Expired) => {
                    reject(&t);
                    log::warn!("friends feed: sign-in expired");
                    if !cred.token.refreshable() {
                        return;
                    }
                    token = next_token(|| cred.token.read(), &t, || sleep(BACKOFF));
                    if token.is_none() {
                        return;
                    }
                    log::info!("friends feed: new token");
                    continue;
                }
                Err(Fetch::Failed(why)) => {
                    if !failing {
                        log::warn!("friends feed: {why}");
                    }
                    failing = true;
                    BACKOFF
                }
            };
            token = Some(t);
            if !sleep(wait) {
                return;
            }
        }
    });
    Feed { snapshots: rx, stop }
}

#[cfg(test)]
mod tests {
    use super::*;

    const FULL: &str = r#"{"friends":[
        {"username":"alice","state":"online","game":"Example Game","playing":{"x":1},
         "in_game":[{"app_id":"a1","title":"Example Game","character":"Aria","zone":"Port Example","since":1700000000}],"role":"admin","future":true},
        {"username":"bob","state":"away","game":null,"playing":null,"in_game":[],"role":null},
        {"username":"carol","state":"offline"}],
        "incoming":[{"username":"dave"}],"outgoing":["erin"],"playing_supported":true,"in_game_supported":false,"extra":{"a":1}}"#;

    #[test]
    fn parses_a_full_snapshot() {
        let s = Snapshot::parse(FULL.as_bytes()).unwrap();
        assert_eq!(s.friends.len(), 3);
        assert_eq!(s.incoming.len(), 1);
        assert_eq!(s.outgoing.len(), 1);
        assert_eq!((s.playing_supported, s.in_game_supported), (Some(true), Some(false)));
        let a = &s.friends[0];
        assert_eq!(a.username.as_deref(), Some("alice"));
        assert_eq!(a.role.as_deref(), Some("admin"));
        assert!(a.playing.is_some());
        assert_eq!(a.in_game[0].app_id.as_deref(), Some("a1"));
        assert_eq!(s.friends[1].game, None);
    }

    #[test]
    fn parses_minimal_and_unknown_documents() {
        assert_eq!(Snapshot::parse(b"{}").unwrap(), Snapshot::default());
        let s = Snapshot::parse(br#"{"friends":[{"username":"x"},{}],"other":[1,2]}"#).unwrap();
        assert_eq!(s.friends.len(), 2);
        assert_eq!(s.friends[0].status(), 0);
        assert_eq!(s.friends[1].username, None);
        assert_eq!(s.playing_supported, None);
        // Nulls and wrong types drop the element, not the snapshot.
        let s = Snapshot::parse(br#"{"friends":[{"username":"x","in_game":null},{"username":5},"junk"],"incoming":null}"#).unwrap();
        assert_eq!(s.friends.len(), 1);
        assert!(s.friends[0].in_game.is_empty());
        assert!(Snapshot::parse(b"[]").is_err());
        assert!(Snapshot::parse(b"nonsense").is_err());
    }

    #[test]
    fn maps_states_to_statuses() {
        let st = |s: Option<&str>| FeedFriend { state: s.map(Into::into), ..Default::default() }.status();
        assert_eq!((st(Some("offline")), st(Some("online")), st(Some("away"))), (0, 1, 2));
        assert_eq!((st(Some("Online")), st(Some("busy")), st(None)), (1, 0, 0));
    }

    #[test]
    fn says_where_a_friend_is() {
        let s = Snapshot::parse(FULL.as_bytes()).unwrap();
        assert_eq!(s.friends[0].location(), "Aria - Port Example");
        // No game in progress: the game's title, only while they are around.
        let f = |state: &str, game: Option<&str>| FeedFriend { state: Some(state.into()), game: game.map(Into::into), ..Default::default() };
        assert_eq!(f("online", Some("Example Game")).location(), "Example Game");
        assert_eq!(f("away", Some("Example Game")).location(), "Example Game");
        assert_eq!(f("offline", Some("Example Game")).location(), "");
        assert_eq!(f("online", None).location(), "");
        // A half-filled entry still says what it has.
        let g = |c: Option<&str>, z: Option<&str>, t: Option<&str>| FeedFriend {
            state: Some("online".into()),
            in_game: vec![InGame { character: c.map(Into::into), zone: z.map(Into::into), title: t.map(Into::into), ..Default::default() }],
            ..Default::default()
        };
        assert_eq!(g(Some("Aria"), None, None).location(), "Aria");
        assert_eq!(g(None, Some("Port Example"), None).location(), "Port Example");
        assert_eq!(g(None, None, Some("Example Game")).location(), "Example Game");
    }

    #[test]
    fn redacts_the_token_in_debug() {
        let c = FeedCred::new("https://example.invalid/feed", "s3cret-token").unwrap();
        for text in [format!("{c:?}"), format!("{c:#?}"), format!("{:?}", Some(c.clone()))] {
            assert!(!text.contains("s3cret-token"), "{text}");
            assert!(text.contains("redacted"));
        }
        let d = TokenSource::Inline("s3cret-token".into());
        assert!(!format!("{:?}", FeedCred { url: "https://example.invalid/f".into(), token: d }).contains("s3cret-token"));
    }

    #[test]
    fn reads_the_feed_from_a_login_file() {
        let v = |s: &str| serde_json::from_str::<serde_json::Value>(s).unwrap();
        let c = FeedCred::from_login(&v(r#"{"username":"u","password":"p","friends_feed":{"url":"https://example.invalid/f","token":"t"}}"#)).unwrap();
        assert_eq!(c.url, "https://example.invalid/f");
        assert_eq!(c.token.read().as_deref(), Some("t"));
        assert!(!c.token.refreshable());
        assert!(FeedCred::from_login(&v(r#"{"username":"u","password":"p"}"#)).is_none());
        assert!(FeedCred::from_login(&v(r#"{"friends_feed":{"url":"http://example.invalid/f","token":"t"}}"#)).is_none());
        assert!(FeedCred::from_login(&v(r#"{"friends_feed":{"url":"https://example.invalid/f","token":""}}"#)).is_none());
        assert!(FeedCred::from_login(&v(r#"{"friends_feed":{"url":"https://example.invalid/f"}}"#)).is_none());
        assert!(FeedCred::from_login(&v(r#"{"friends_feed":"nope"}"#)).is_none());
    }

    #[test]
    fn reads_a_token_file_afresh() {
        let dir = std::env::temp_dir().join(format!("friends-feed-test-{}", std::process::id()));
        std::fs::create_dir_all(&dir).unwrap();
        let path = dir.join("token");
        let v = serde_json::json!({"friends_feed": {"url": "https://example.invalid/f", "token_file": path.to_str().unwrap(), "token": "ignored"}});
        let c = FeedCred::from_login(&v).unwrap();
        assert!(c.token.refreshable());
        // Not there yet, then a bare token with its newline, then JSON, then an empty file and a JSON without one.
        assert_eq!(c.token.read(), None);
        std::fs::write(&path, "first-token\n").unwrap();
        assert_eq!(c.token.read().as_deref(), Some("first-token"));
        std::fs::write(&path, r#"{"token": "second-token", "extra": 1}"#).unwrap();
        assert_eq!(c.token.read().as_deref(), Some("second-token"));
        std::fs::write(&path, "  \n").unwrap();
        assert_eq!(c.token.read(), None);
        std::fs::write(&path, r#"{"nope": 1}"#).unwrap();
        assert_eq!(c.token.read(), None);
        let _ = std::fs::remove_dir_all(&dir);
        assert!(!format!("{c:?}").contains("friends-feed-test"));
        assert!(FeedCred::from_login(&serde_json::json!({"friends_feed": {"url": "https://example.invalid/f", "token_file": ""}})).is_none());
    }

    #[test]
    fn remembers_the_rejected_token_across_pollers() {
        assert!(!rejected("token-a"));
        reject("token-a");
        assert!(rejected("token-a"));
        assert!(!rejected("token-b"));
    }

    #[test]
    fn takes_a_changed_token_at_once() {
        let mut pauses = 0;
        let t = next_token(
            || Some("new".into()),
            "old",
            || {
                pauses += 1;
                true
            },
        );
        assert_eq!((t.as_deref(), pauses), (Some("new"), 0));
    }

    #[test]
    fn pauses_while_the_token_is_unchanged() {
        // The file still has the expired token twice (and is gone once), then the launcher renews it.
        let mut reads = vec![Some("new"), None, Some("old"), Some("old")];
        let mut pauses = 0;
        let t = next_token(
            || reads.pop().flatten().map(String::from),
            "old",
            || {
                pauses += 1;
                true
            },
        );
        assert_eq!((t.as_deref(), pauses), (Some("new"), 3));
        assert!(reads.is_empty());
    }

    #[test]
    fn stops_pausing_when_told_to() {
        let mut reads = 0;
        let t = next_token(
            || {
                reads += 1;
                Some("old".into())
            },
            "old",
            || false,
        );
        assert_eq!((t, reads), (None, 1));
    }
}
