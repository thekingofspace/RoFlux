use std::path::{Component, Path, PathBuf};

use mlua::{Lua, Result, Table, Value};

fn resolve(root: &Path, relative: &str) -> Option<PathBuf> {
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

fn deny(relative: &str) -> mlua::Error {
    mlua::Error::runtime(format!("\"{relative}\" is outside the project"))
}

pub fn install(lua: &Lua, roflux: &Table, root: PathBuf) -> Result<()> {
    let base = root.clone();

    roflux.set(
        "root",
        lua.create_function(move |_, ()| Ok(base.to_string_lossy().replace('\\', "/")))?,
    )?;

    let base = root.clone();

    roflux.set(
        "read",
        lua.create_function(move |_, relative: String| {
            let path = resolve(&base, &relative).ok_or_else(|| deny(&relative))?;

            match std::fs::read_to_string(&path) {
                Ok(body) => Ok(Some(body)),
                Err(_) => Ok(None),
            }
        })?,
    )?;

    let base = root.clone();

    roflux.set(
        "exists",
        lua.create_function(move |_, relative: String| {
            let path = resolve(&base, &relative).ok_or_else(|| deny(&relative))?;
            Ok(path.exists())
        })?,
    )?;

    let base = root.clone();

    roflux.set(
        "isDirectory",
        lua.create_function(move |_, relative: String| {
            let path = resolve(&base, &relative).ok_or_else(|| deny(&relative))?;
            Ok(path.is_dir())
        })?,
    )?;

    let base = root.clone();

    roflux.set(
        "list",
        lua.create_function(move |lua, relative: String| {
            let path = resolve(&base, &relative).ok_or_else(|| deny(&relative))?;
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

    roflux.set(
        "walk",
        lua.create_function(move |lua, relative: String| {
            let path = resolve(&base, &relative).ok_or_else(|| deny(&relative))?;
            let listing = lua.create_table()?;
            let mut found = Vec::new();

            for entry in walkdir::WalkDir::new(&path).sort_by_file_name() {
                let Ok(entry) = entry else {
                    continue;
                };

                if !entry.file_type().is_file() {
                    continue;
                }

                let shown = entry
                    .path()
                    .strip_prefix(&base)
                    .unwrap_or(entry.path())
                    .to_string_lossy()
                    .replace('\\', "/");

                found.push(shown);
            }

            for name in found {
                listing.push(name)?;
            }

            Ok(listing)
        })?,
    )?;

    let base = root.clone();

    roflux.set(
        "json",
        lua.create_function(move |lua, relative: String| {
            let path = resolve(&base, &relative).ok_or_else(|| deny(&relative))?;

            let Ok(body) = std::fs::read_to_string(&path) else {
                return Ok(Value::Nil);
            };

            let decoded: serde_json::Value = serde_json::from_str(body.trim_start_matches('\u{feff}'))
                .map_err(|error| mlua::Error::runtime(format!("{relative}: {error}")))?;

            mlua::LuaSerdeExt::to_value(lua, &decoded)
        })?,
    )?;

    Ok(())
}
