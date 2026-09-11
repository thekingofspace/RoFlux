use std::io::Write as _;
use std::path::{Component, Path, PathBuf};
use std::time::UNIX_EPOCH;

use globset::GlobBuilder;
use mlua::{Function, Lua, Result, Table};

pub fn resolve(root: &Path, relative: &str) -> Option<PathBuf> {
    let cleaned = relative.replace('\\', "/");
    let candidate = Path::new(&cleaned);

    if candidate.is_absolute() {
        return None;
    }

    let mut out = root.to_path_buf();

    for part in candidate.components() {
        match part {
            Component::Normal(value) => out.push(value),
            Component::CurDir => {}
            _ => return None,
        }
    }

    Some(out)
}

pub fn deny(relative: &str) -> mlua::Error {
    mlua::Error::runtime(format!("\"{relative}\" is outside the project"))
}

fn locate(root: &Path, relative: &str) -> Result<PathBuf> {
    resolve(root, relative).ok_or_else(|| deny(relative))
}

fn shown(root: &Path, path: &Path) -> String {
    path.strip_prefix(root)
        .unwrap_or(path)
        .to_string_lossy()
        .replace('\\', "/")
}

fn skipped(name: &str) -> bool {
    name.starts_with('.') || name == "target" || name == "node_modules"
}

fn files_under(root: &Path, start: &Path) -> Vec<String> {
    let mut found = Vec::new();

    let walker = walkdir::WalkDir::new(start)
        .sort_by_file_name()
        .into_iter()
        .filter_entry(|entry| entry.depth() == 0 || !skipped(&entry.file_name().to_string_lossy()));

    for entry in walker.flatten() {
        if entry.file_type().is_file() {
            found.push(shown(root, entry.path()));
        }
    }

    found
}

pub fn install(lua: &Lua, roflux: &Table, root: PathBuf) -> Result<()> {
    let fs = lua.create_table()?;

    let base = root.clone();
    fs.set(
        "root",
        lua.create_function(move |_, ()| Ok(base.to_string_lossy().replace('\\', "/")))?,
    )?;

    let base = root.clone();
    fs.set(
        "read",
        lua.create_function(move |lua, relative: String| {
            let path = locate(&base, &relative)?;

            match std::fs::read(&path) {
                Ok(bytes) => Ok(Some(lua.create_string(bytes)?)),
                Err(_) => Ok(None),
            }
        })?,
    )?;

    let base = root.clone();
    fs.set(
        "write",
        lua.create_function(move |_, (relative, text): (String, mlua::String)| {
            let path = locate(&base, &relative)?;
            let bytes = text.as_bytes().to_vec();

            if path == base || path.is_dir() {
                return Err(mlua::Error::runtime(format!("\"{relative}\" is a folder")));
            }

            if std::fs::read(&path).ok().as_deref() == Some(bytes.as_slice()) {
                return Ok(false);
            }

            if let Some(parent) = path.parent() {
                std::fs::create_dir_all(parent).map_err(mlua::Error::external)?;
            }

            std::fs::write(&path, bytes).map_err(mlua::Error::external)?;
            Ok(true)
        })?,
    )?;

    let base = root.clone();
    fs.set(
        "append",
        lua.create_function(move |_, (relative, text): (String, mlua::String)| {
            let path = locate(&base, &relative)?;

            if let Some(parent) = path.parent() {
                std::fs::create_dir_all(parent).map_err(mlua::Error::external)?;
            }

            let mut handle = std::fs::OpenOptions::new()
                .create(true)
                .append(true)
                .open(&path)
                .map_err(mlua::Error::external)?;

            handle.write_all(&text.as_bytes()).map_err(mlua::Error::external)?;
            Ok(())
        })?,
    )?;

    let base = root.clone();
    fs.set(
        "remove",
        lua.create_function(move |_, relative: String| {
            let path = locate(&base, &relative)?;

            if path == base {
                return Err(mlua::Error::runtime("roflux.fs.remove will not remove the project folder"));
            }

            if path.is_dir() {
                std::fs::remove_dir(&path).map_err(mlua::Error::external)?;
                return Ok(true);
            }

            if path.is_file() {
                std::fs::remove_file(&path).map_err(mlua::Error::external)?;
                return Ok(true);
            }

            Ok(false)
        })?,
    )?;

    let base = root.clone();
    fs.set(
        "mkdir",
        lua.create_function(move |_, relative: String| {
            let path = locate(&base, &relative)?;
            std::fs::create_dir_all(&path).map_err(mlua::Error::external)?;
            Ok(())
        })?,
    )?;

    let base = root.clone();
    fs.set(
        "exists",
        lua.create_function(move |_, relative: String| Ok(locate(&base, &relative)?.exists()))?,
    )?;

    let base = root.clone();
    fs.set(
        "isFile",
        lua.create_function(move |_, relative: String| Ok(locate(&base, &relative)?.is_file()))?,
    )?;

    let base = root.clone();
    fs.set(
        "isDirectory",
        lua.create_function(move |_, relative: String| Ok(locate(&base, &relative)?.is_dir()))?,
    )?;

    let base = root.clone();
    fs.set(
        "list",
        lua.create_function(move |lua, relative: String| {
            let path = locate(&base, &relative)?;
            let listing = lua.create_table()?;

            let Ok(entries) = std::fs::read_dir(&path) else {
                return Ok(listing);
            };

            let mut names: Vec<String> = entries
                .filter_map(|entry| entry.ok())
                .map(|entry| entry.file_name().to_string_lossy().to_string())
                .collect();

            names.sort();

            for name in names {
                listing.push(name)?;
            }

            Ok(listing)
        })?,
    )?;

    let base = root.clone();
    fs.set(
        "walk",
        lua.create_function(move |lua, relative: String| {
            let path = locate(&base, &relative)?;
            lua.create_sequence_from(files_under(&base, &path))
        })?,
    )?;

    let base = root.clone();
    fs.set(
        "glob",
        lua.create_function(move |lua, pattern: String| {
            let matcher = GlobBuilder::new(&pattern)
                .literal_separator(true)
                .build()
                .map_err(|error| mlua::Error::runtime(format!("bad glob \"{pattern}\": {error}")))?
                .compile_matcher();

            let matched: Vec<String> = files_under(&base, &base)
                .into_iter()
                .filter(|path| matcher.is_match(path))
                .collect();

            lua.create_sequence_from(matched)
        })?,
    )?;

    let base = root.clone();
    fs.set(
        "stat",
        lua.create_function(move |lua, relative: String| {
            let path = locate(&base, &relative)?;

            let Ok(meta) = std::fs::metadata(&path) else {
                return Ok(None);
            };

            let modified = meta
                .modified()
                .ok()
                .and_then(|time| time.duration_since(UNIX_EPOCH).ok())
                .map(|since| since.as_secs_f64())
                .unwrap_or(0.0);

            let stat = lua.create_table()?;
            stat.set("size", meta.len())?;
            stat.set("modified", modified)?;
            stat.set("isFile", meta.is_file())?;
            stat.set("isDirectory", meta.is_dir())?;
            Ok(Some(stat))
        })?,
    )?;

    for name in ["root", "read", "exists", "isDirectory", "list", "walk"] {
        roflux.set(name, fs.get::<Function>(name)?)?;
    }

    roflux.set("fs", fs)?;

    Ok(())
}
