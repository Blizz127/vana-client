//! The catalogues (not retail), kept on GitHub in the client's repository, each version pinned by its files' SHA-256:
//! catalogue/dats.json the DAT packs as archives (the DATs page's Available tab), catalogue/mods.json our standard
//! Lua mods as their files in the repository (assets/mods; Settings > Mods, Download Standard Mods). No mod comes
//! with the client.

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
    /// Archives unpacked in order into the one folder (a later one's files replace an earlier one's), or a mod's files
    /// each put at its `path`.
    pub files: Vec<File>,
}

#[derive(Clone, Debug, Deserialize)]
pub struct File {
    pub url: String,
    pub sha256: String,
    #[serde(default)]
    pub size: u64,
    /// A file of the mod (not an archive): where it goes in the mod's folder.
    #[serde(default)]
    pub path: Option<String>,
}

/// A mod file's place in its folder: relative, no "..", no drive or backslash.
fn safe_path(p: &str) -> bool {
    !p.is_empty()
        && !p.starts_with('/')
        && !p.contains(['\\', ':'])
        && p.split('/').all(|c| !c.is_empty() && c != "." && c != "..")
}

fn lua() -> String {
    "lua".into()
}

#[derive(Deserialize)]
struct Listed {
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

/// Which list: the DAT packs' or the standard mods'.
#[derive(Clone, Copy, PartialEq, Debug)]
pub enum List {
    Dats,
    Mods,
}

impl List {
    /// Its file in catalogue/ (and the copy kept from the last fetch).
    fn file(self) -> &'static str {
        match self {
            List::Dats => "dats.json",
            List::Mods => "mods.json",
        }
    }

    /// The test runs' stand-in list (a URL or a file).
    fn env(self) -> &'static str {
        match self {
            List::Dats => "VANA_DAT_CATALOGUE",
            List::Mods => "VANA_MOD_CATALOGUE",
        }
    }
}

/// Where a list is read from.
pub fn url(list: List) -> String {
    format!("https://raw.githubusercontent.com/{}/master/catalogue/{}", super::updater::RELEASE_REPO, list.file())
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
        if f.path.as_deref().is_some_and(|p| !safe_path(p)) {
            bail!("{}: a path inside the mod's folder", f.url);
        }
    }
    if e.files.iter().any(|f| f.path.is_some()) && (e.kind != "lua" || e.files.iter().any(|f| f.path.is_none())) {
        bail!("a Lua mod's files each with a path, or archives only");
    }
    Ok(())
}

/// The list's entries; bad ones are left out (and logged). `any_host`: archives may come from anywhere (test lists).
pub fn parse(text: &str, any_host: bool) -> Result<Vec<Entry>> {
    let l: Listed = serde_json::from_str(text).context("reading the mod catalogue")?;
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

/// A list: fetched, else the copy kept from the last fetch; only its kind's entries (packs or Lua mods).
/// VANA_DAT_CATALOGUE / VANA_MOD_CATALOGUE: another list (a URL or a file).
pub fn fetch(list: List) -> Result<Vec<Entry>> {
    let want = |e: &Entry| (e.kind == "pack") == (list == List::Dats);
    fetch_all(list).map(|v| v.into_iter().filter(want).collect())
}

fn fetch_all(list: List) -> Result<Vec<Entry>> {
    let over = std::env::var(list.env()).ok();
    let kept = crate::config::catalogue_dir().join(list.file());
    let got = match over.as_deref() {
        Some(p) if !p.starts_with("http") => std::fs::read_to_string(p).with_context(|| p.to_string()),
        Some(u) => super::updater::get_text(u),
        None => super::updater::get_text(&url(list)),
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

/// A standard mod's files downloaded and checked into `work`, each at its path.
fn fetch_files(e: &Entry, work: &Path, progress: &AtomicU32) -> Result<()> {
    let n = e.files.len().max(1) as u64;
    for (k, f) in e.files.iter().enumerate() {
        let rel = f.path.as_deref().unwrap_or_default();
        let file = work.join(rel);
        if let Some(dir) = file.parent() {
            std::fs::create_dir_all(dir)?;
        }
        super::updater::download(&f.url, &file, &|_, _| {})?;
        if sha256(&file)? != f.sha256.to_ascii_lowercase() {
            bail!("{} is not the file the catalogue names (its SHA-256 differs); not installed", f.url);
        }
        progress.store(((k as u64 + 1) * 1000 / n).min(999) as u32, Ordering::Relaxed);
    }
    if !work.join("mod.toml").is_file() {
        bail!("{} has no mod.toml", e.id);
    }
    Ok(())
}

/// Downloads, checks and unpacks an entry's archives (or puts its files) into `root/<id>` (an older copy replaced).
/// `progress` counts per mille: each archive's download is four fifths of its share, its unpacking the rest. A standard
/// Lua mod is given the permissions it asks for. Returns the folder's name.
pub fn install(e: &Entry, root: &Path, progress: &AtomicU32) -> Result<String> {
    if e.files.iter().any(|f| f.path.is_some()) {
        std::fs::create_dir_all(root)?;
        let work = modpack::work_dir(root, &e.id)?;
        if let Err(err) = fetch_files(e, &work, progress) {
            let _ = std::fs::remove_dir_all(&work);
            return Err(err);
        }
        std::fs::write(work.join(MARK), &e.version)?;
        modpack::place(&work, &root.join(&e.id))?;
        super::lua::grant_manifest(&root.join(&e.id));
        progress.store(1000, Ordering::Relaxed);
        log::info!("mods: installed {} {} from the standard mods", e.id, e.version);
        return Ok(e.id.clone());
    }
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
            let of =
                |done: u64, all: u64, share: u64| (done.min(all) as u128 * share as u128 / all.max(1) as u128) as u64;
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
            modpack::unpack(&pack, &work, &mut |done, all| {
                at(base + part * 4 / 5 + of(done, all, part - part * 4 / 5))
            })?;
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

    /// The repository's lists read whole under the GitHub-only rule: DAT packs in dats.json, Lua mods in mods.json.
    #[test]
    fn committed_list() {
        for (text, pack) in [
            (include_str!("../../../../catalogue/dats.json"), true),
            (include_str!("../../../../catalogue/mods.json"), false),
        ] {
            let n = serde_json::from_str::<serde_json::Value>(text).unwrap()["mods"].as_array().unwrap().len();
            let got = parse(text, false).unwrap();
            assert_eq!(got.len(), n);
            assert!(got.iter().all(|e| (e.kind == "pack") == pack));
        }
    }

    /// Every standard mod (assets/mods) is listed with each of its files at its SHA-256, as GitHub serves them from
    /// master. VANA_WRITE_CATALOGUE=1 writes the list anew (the DAT packs' entries kept).
    #[test]
    fn standard_mods_listed() {
        let crate_dir = Path::new(env!("CARGO_MANIFEST_DIR"));
        let list_path = crate_dir.join("../../catalogue/mods.json");
        let mut list: serde_json::Value = serde_json::from_str(&std::fs::read_to_string(&list_path).unwrap()).unwrap();
        let want = standard_entries(&crate_dir.join("assets/mods"));
        let lua = |l: &serde_json::Value| {
            l["mods"].as_array().unwrap().iter().filter(|e| e["kind"] == "lua").cloned().collect::<Vec<_>>()
        };
        if std::env::var_os("VANA_WRITE_CATALOGUE").is_some() {
            let packs: Vec<serde_json::Value> =
                list["mods"].as_array().unwrap().iter().filter(|e| e["kind"] != "lua").cloned().collect();
            list["mods"] = packs.into_iter().chain(want).collect();
            std::fs::write(&list_path, serde_json::to_string_pretty(&list).unwrap() + "\n").unwrap();
            return;
        }
        assert!(
            lua(&list) == want,
            "catalogue/mods.json is out of date: VANA_WRITE_CATALOGUE=1 cargo test standard_mods_listed"
        );
        assert_eq!(
            parse(&serde_json::to_string(&list).unwrap(), false).unwrap().iter().filter(|e| e.kind == "lua").count(),
            want.len()
        );
    }

    fn standard_entries(mods: &Path) -> Vec<serde_json::Value> {
        #[derive(Deserialize)]
        struct M {
            name: String,
            version: String,
            #[serde(default)]
            description: String,
            #[serde(default)]
            authors: Vec<String>,
        }
        fn walk(root: &Path, dir: &Path, out: &mut Vec<String>) {
            for e in std::fs::read_dir(dir).unwrap().flatten() {
                let p = e.path();
                if e.file_name().to_string_lossy().starts_with('.') {
                    continue;
                }
                if p.is_dir() {
                    walk(root, &p, out);
                } else {
                    out.push(p.strip_prefix(root).unwrap().to_string_lossy().replace('\\', "/"));
                }
            }
        }
        let mut ids: Vec<String> = std::fs::read_dir(mods)
            .unwrap()
            .flatten()
            .filter(|e| e.path().join("mod.toml").is_file())
            .map(|e| e.file_name().to_string_lossy().into_owned())
            .collect();
        ids.sort();
        ids.iter()
            .map(|id| {
                let dir = mods.join(id);
                let m: M = toml::from_str(&std::fs::read_to_string(dir.join("mod.toml")).unwrap()).unwrap();
                let mut rels = Vec::new();
                walk(&dir, &dir, &mut rels);
                rels.sort();
                let files: Vec<serde_json::Value> = rels
                    .iter()
                    .map(|rel| {
                        let p = dir.join(rel);
                        let url = format!("https://raw.githubusercontent.com/{}/master/crates/vana-client/assets/mods/{id}/{rel}", super::super::updater::RELEASE_REPO);
                        serde_json::json!({"path": rel, "url": url, "sha256": sha256(&p).unwrap(), "size": std::fs::metadata(&p).unwrap().len()})
                    })
                    .collect();
                serde_json::json!({"id": id, "name": m.name, "kind": "lua", "version": m.version, "authors": m.authors, "description": m.description, "files": files})
            })
            .collect()
    }

    /// A standard mod's files: each needs a safe path; archives and files do not mix.
    #[test]
    fn mod_files_checked() {
        let f = |path: &str| {
            format!(
                r#"{{"url": "https://raw.githubusercontent.com/a/b/master/x", "sha256": "00112233445566778899aabbccddeeff00112233445566778899aabbccddeeff", "path": "{path}"}}"#
            )
        };
        let list = |files: &str| {
            format!(r#"{{"format": 1, "mods": [{{"id": "m", "name": "M", "version": "1.0.0", "files": [{files}]}}]}}"#)
        };
        assert_eq!(parse(&list(&format!("{}, {}", f("init.lua"), f("src/a.lua"))), false).unwrap().len(), 1);
        for bad in ["../x.lua", "/etc/x", "src/../../x", "c:x"] {
            assert!(parse(&list(&f(bad)), false).unwrap().is_empty(), "{bad}");
        }
        assert!(!safe_path("a\\b") && !safe_path("") && !safe_path("a//b") && safe_path("src/a.lua"));
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
