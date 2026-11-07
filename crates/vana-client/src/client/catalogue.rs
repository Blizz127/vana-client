//! The mod catalogue (not retail): a list of mods kept on GitHub (catalogue/mods.json in the client's repository),
//! each version pinned by its archives' SHA-256, offered on the Mods page with Install or Update.

use crate::modpack;
use anyhow::{Context, Result, bail};
use serde::Deserialize;
use std::io::Read;
use std::path::Path;
use std::sync::atomic::{AtomicU32, Ordering};

/// The list's format this client reads.
const FORMAT: u32 = 1;

/// In a folder the catalogue installed: the version.
const MARK: &str = ".catalogue";

/// Hosts an archive may come from (VANA_MOD_CATALOGUE lifts this for test lists).
const HOSTS: [&str; 3] = ["https://github.com/", "https://raw.githubusercontent.com/", "https://codeload.github.com/"];

#[derive(Clone, Debug, Deserialize)]
pub struct Entry {
    /// Its folder in the mods folder (a Lua mod's id).
    pub id: String,
    pub name: String,
    /// "lua" (a Lua mod) or "pack" (game files).
    #[serde(default = "lua")]
    pub kind: String,
    pub version: String,
    #[serde(default)]
    pub authors: Vec<String>,
    #[serde(default)]
    pub description: String,
    /// Unpacked in order into the one folder: a later archive's files replace an earlier one's.
    pub files: Vec<File>,
}

#[derive(Clone, Debug, Deserialize)]
pub struct File {
    pub url: String,
    pub sha256: String,
    #[serde(default)]
    pub size: u64,
}

fn lua() -> String {
    "lua".into()
}

#[derive(Deserialize)]
struct List {
    #[serde(default)]
    format: u32,
    mods: Vec<Entry>,
}

impl Entry {
    /// The archives' bytes in all (0 when the list gives no sizes).
    pub fn size(&self) -> u64 {
        self.files.iter().map(|f| f.size).sum()
    }
}

/// Where the list is read from.
pub fn url() -> String {
    format!("https://raw.githubusercontent.com/{}/master/catalogue/mods.json", super::updater::RELEASE_REPO)
}

fn check(e: &Entry, any_host: bool) -> Result<()> {
    if e.id.is_empty() || !e.id.chars().all(|c| c.is_ascii_alphanumeric() || c == '_' || c == '-') {
        bail!("id: letters, digits, _ and - only");
    }
    if e.kind != "lua" && e.kind != "pack" {
        bail!("kind is \"lua\" or \"pack\" ({:?} given)", e.kind);
    }
    if e.files.is_empty() {
        bail!("no files");
    }
    for f in &e.files {
        if !any_host && !HOSTS.iter().any(|h| f.url.starts_with(h)) {
            bail!("{}: not a GitHub address", f.url);
        }
        if f.sha256.len() != 64 || !f.sha256.bytes().all(|b| b.is_ascii_hexdigit()) {
            bail!("{}: sha256 is 64 hex digits", f.url);
        }
    }
    Ok(())
}

/// The list's entries; bad ones are left out (and logged). `any_host`: archives may come from anywhere (test lists).
pub fn parse(text: &str, any_host: bool) -> Result<Vec<Entry>> {
    let l: List = serde_json::from_str(text).context("reading the mod catalogue")?;
    if l.format > FORMAT {
        bail!("the mod catalogue's format {} is newer than this client's ({FORMAT})", l.format);
    }
    Ok(l.mods
        .into_iter()
        .filter(|e| match check(e, any_host) {
            Ok(()) => true,
            Err(err) => {
                log::warn!("mod catalogue: {}: {err:#}", e.id);
                false
            }
        })
        .collect())
}

/// The list: fetched, else the copy kept from the last fetch. VANA_MOD_CATALOGUE: another list (a URL or a file).
pub fn fetch() -> Result<Vec<Entry>> {
    let over = std::env::var("VANA_MOD_CATALOGUE").ok();
    let kept = crate::config::catalogue_dir().join("mods.json");
    let got = match over.as_deref() {
        Some(p) if !p.starts_with("http") => std::fs::read_to_string(p).with_context(|| p.to_string()),
        Some(u) => super::updater::get_text(u),
        None => super::updater::get_text(&url()),
    };
    match got {
        Ok(text) => {
            let list = parse(&text, over.is_some())?;
            if over.is_none() {
                let _ = std::fs::create_dir_all(kept.parent().unwrap_or(Path::new(".")));
                let _ = std::fs::write(&kept, &text);
            }
            Ok(list)
        }
        Err(e) if over.is_none() => {
            log::info!("mod catalogue: {e:#}; using the last copy");
            parse(&std::fs::read_to_string(&kept).map_err(|_| e)?, false)
        }
        Err(e) => Err(e),
    }
}

/// The version installed in `root/id`: the catalogue's mark, else its mod.toml's; "" for a folder with neither.
pub fn installed(root: &Path, id: &str) -> Option<String> {
    let dir = root.join(id);
    if !dir.is_dir() {
        return None;
    }
    if let Ok(v) = std::fs::read_to_string(dir.join(MARK)) {
        return Some(v.trim().to_string());
    }
    let text = std::fs::read_to_string(dir.join("mod.toml")).ok();
    Some(text.and_then(|t| modpack::lua_manifest(&t, id).ok()).map_or_else(String::new, |m| m.1))
}

/// Whether to offer the entry: Some(false) to install, Some(true) to update (a newer version than `have`).
pub fn offer(e: &Entry, have: Option<&str>) -> Option<bool> {
    match have {
        None => Some(false),
        Some(v) if !v.is_empty() && super::updater::newer(&e.version, v) => Some(true),
        _ => None,
    }
}

fn sha256(path: &Path) -> Result<String> {
    let mut f = std::fs::File::open(path)?;
    let mut ctx = ring::digest::Context::new(&ring::digest::SHA256);
    let mut buf = vec![0u8; 1 << 20];
    loop {
        let n = f.read(&mut buf)?;
        if n == 0 {
            break;
        }
        ctx.update(&buf[..n]);
    }
    Ok(hex::encode(ctx.finish()))
}

/// The archive kind's extension from its address (a GitHub source zip has none: zip).
fn ext(url: &str) -> &'static str {
    let last = url.rsplit('/').next().unwrap_or("").to_ascii_lowercase();
    ["7z", "rar"].into_iter().find(|x| last.ends_with(&format!(".{x}"))).unwrap_or("zip")
}

/// Downloads, checks and unpacks an entry's archives into `root/<id>` (an older copy replaced). `progress` counts per
/// mille: each archive's download is four fifths of its share, its unpacking the rest. Returns the folder's name.
pub fn install(e: &Entry, root: &Path, progress: &AtomicU32) -> Result<String> {
    let downloads = crate::config::catalogue_dir().join("downloads");
    std::fs::create_dir_all(&downloads)?;
    std::fs::create_dir_all(root)?;
    let share = |f: &File| if e.size() > 0 { f.size } else { 1 };
    let total: u64 = e.files.iter().map(share).sum::<u64>().max(1);
    let work = modpack::work_dir(root, &e.id)?;
    let mut base = 0u64;
    let mut each = || -> Result<()> {
        for (k, f) in e.files.iter().enumerate() {
            let part = share(f);
            let file = downloads.join(format!("{}-{k}.{}", e.id, ext(&f.url)));
            let at = |x: u64| progress.store((x * 1000 / total).min(999) as u32, Ordering::Relaxed);
            let of = |done: u64, all: u64, share: u64| (done.min(all) as u128 * share as u128 / all.max(1) as u128) as u64;
            super::updater::download(&f.url, &file, &|done, all| at(base + of(done, all, part * 4 / 5)))?;
            if sha256(&file)? != f.sha256.to_ascii_lowercase() {
                let _ = std::fs::remove_file(&file);
                bail!("{} is not the file the catalogue names (its SHA-256 differs); not installed", f.url);
            }
            let pack = modpack::pack_named(&file, Some(&e.id))?;
            match (&pack.lua, e.kind == "lua") {
                (Some(_), true) if pack.slug != e.id => bail!("{} holds mod {}, not {}", f.url, pack.slug, e.id),
                (Some(_), false) => bail!("{} holds a Lua mod, not game files", f.url),
                (None, true) => bail!("{} holds no mod.toml", f.url),
                _ => {}
            }
            modpack::unpack(&pack, &work, &mut |done, all| at(base + part * 4 / 5 + of(done, all, part - part * 4 / 5)))?;
            let _ = std::fs::remove_file(&file);
            base += part;
        }
        Ok(())
    };
    if let Err(err) = each() {
        let _ = std::fs::remove_dir_all(&work);
        return Err(err);
    }
    std::fs::write(work.join(MARK), &e.version)?;
    modpack::place(&work, &root.join(&e.id))?;
    progress.store(1000, Ordering::Relaxed);
    log::info!("mods: installed {} {} from the catalogue", e.id, e.version);
    Ok(e.id.clone())
}

#[cfg(test)]
mod tests {
    use super::*;

    const LIST: &str = r#"{"format": 1, "mods": [
        {"id": "good", "name": "Good", "version": "1.2.0", "files": [{"url": "https://github.com/a/b/releases/download/v1.2.0/good.zip", "sha256": "00112233445566778899aabbccddeeff00112233445566778899aabbccddeeff", "size": 10}]},
        {"id": "elsewhere", "name": "Elsewhere", "version": "1.0.0", "files": [{"url": "https://example.com/x.zip", "sha256": "00112233445566778899aabbccddeeff00112233445566778899aabbccddeeff"}]},
        {"id": "bad/id", "name": "Bad", "version": "1.0.0", "files": [{"url": "https://github.com/a/b/x.zip", "sha256": "00112233445566778899aabbccddeeff00112233445566778899aabbccddeeff"}]},
        {"id": "nohash", "name": "No hash", "version": "1.0.0", "files": [{"url": "https://github.com/a/b/x.zip", "sha256": "abc"}]}
    ]}"#;

    /// Only GitHub archives with a full SHA-256 and a clean id are kept; a test list may name any host.
    #[test]
    fn entries_checked() {
        let ids = |v: Vec<Entry>| v.into_iter().map(|e| e.id).collect::<Vec<_>>();
        assert_eq!(ids(parse(LIST, false).unwrap()), ["good"]);
        assert_eq!(ids(parse(LIST, true).unwrap()), ["good", "elsewhere"]);
        assert!(parse(r#"{"format": 2, "mods": []}"#, false).is_err());
    }

    /// The repository's own list reads whole under the GitHub-only rule.
    #[test]
    fn committed_list() {
        let text = include_str!("../../../../catalogue/mods.json");
        let n = serde_json::from_str::<serde_json::Value>(text).unwrap()["mods"].as_array().unwrap().len();
        assert_eq!(parse(text, false).unwrap().len(), n);
    }

    #[test]
    fn offers() {
        let e = parse(LIST, false).unwrap().remove(0);
        assert_eq!(offer(&e, None), Some(false));
        assert_eq!(offer(&e, Some("1.1.9")), Some(true));
        assert_eq!(offer(&e, Some("1.2.0")), None);
        assert_eq!(offer(&e, Some("")), None);
        assert_eq!(ext("https://github.com/a/b/releases/download/v1/x.7z"), "7z");
        assert_eq!(ext("https://codeload.github.com/a/b/zip/refs/tags/v1"), "zip");
    }
}
