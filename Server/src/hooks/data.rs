use std::path::{Path, PathBuf};

use base64::engine::general_purpose::STANDARD;
use base64::Engine;
use mlua::{Function, Lua, LuaSerdeExt, Result, Table, Value};
use serde_json::{Map, Value as Json};
use sha2::{Digest, Sha256};

use super::files::{deny, resolve};

pub fn sorted(value: Json) -> Json {
    match value {
        Json::Object(map) => {
            let mut entries: Vec<(String, Json)> = map.into_iter().collect();
            entries.sort_by(|a, b| a.0.cmp(&b.0));

            let mut out = Map::new();

            for (key, inner) in entries {
                out.insert(key, sorted(inner));
            }

            Json::Object(out)
        }
        Json::Array(items) => Json::Array(items.into_iter().map(sorted).collect()),
        other => other,
    }
}

fn plain(lua: &Lua, value: Value) -> Result<Json> {
    Ok(sorted(lua.from_value(value)?))
}

fn text_of(root: &Path, relative: &str) -> Result<Option<String>> {
    let path = resolve(root, relative).ok_or_else(|| deny(relative))?;

    Ok(std::fs::read_to_string(path)
        .ok()
        .map(|body| body.trim_start_matches('\u{feff}').to_string()))
}

fn callable(lua: &Lua, table: &Table, call: Function) -> Result<()> {
    let meta = lua.create_table()?;
    meta.set("__call", call)?;
    table.set_metatable(Some(meta))
}

fn json_file(lua: &Lua, root: &Path, relative: &str) -> Result<Value> {
    let Some(body) = text_of(root, relative)? else {
        return Ok(Value::Nil);
    };

    let decoded: Json = serde_json::from_str(&body)
        .map_err(|error| mlua::Error::runtime(format!("{relative}: {error}")))?;

    lua.to_value(&decoded)
}

fn toml_file(lua: &Lua, root: &Path, relative: &str) -> Result<Value> {
    let Some(body) = text_of(root, relative)? else {
        return Ok(Value::Nil);
    };

    let decoded: Json = toml::from_str(&body)
        .map_err(|error| mlua::Error::runtime(format!("{relative}: {error}")))?;

    lua.to_value(&decoded)
}

pub fn install(lua: &Lua, roflux: &Table, root: PathBuf) -> Result<()> {
    let json = lua.create_table()?;

    json.set(
        "decode",
        lua.create_function(|lua, text: String| {
            let decoded: Json = serde_json::from_str(text.trim_start_matches('\u{feff}'))
                .map_err(mlua::Error::external)?;
            lua.to_value(&decoded)
        })?,
    )?;

    json.set(
        "encode",
        lua.create_function(|lua, (value, pretty): (Value, Option<bool>)| {
            let plain = plain(lua, value)?;

            let rendered = if pretty.unwrap_or(false) {
                serde_json::to_string_pretty(&plain)
            } else {
                serde_json::to_string(&plain)
            };

            rendered.map_err(mlua::Error::external)
        })?,
    )?;

    let base = root.clone();
    json.set(
        "read",
        lua.create_function(move |lua, relative: String| json_file(lua, &base, &relative))?,
    )?;

    let base = root.clone();
    callable(
        lua,
        &json,
        lua.create_function(move |lua, (_, relative): (Table, String)| json_file(lua, &base, &relative))?,
    )?;

    roflux.set("json", json)?;

    let tomls = lua.create_table()?;

    tomls.set(
        "decode",
        lua.create_function(|lua, text: String| {
            let decoded: Json = toml::from_str(&text).map_err(mlua::Error::external)?;
            lua.to_value(&decoded)
        })?,
    )?;

    tomls.set(
        "encode",
        lua.create_function(|lua, value: Value| {
            let plain = plain(lua, value)?;
            toml::to_string(&plain).map_err(mlua::Error::external)
        })?,
    )?;

    let base = root.clone();
    tomls.set(
        "read",
        lua.create_function(move |lua, relative: String| toml_file(lua, &base, &relative))?,
    )?;

    roflux.set("toml", tomls)?;

    let base64 = lua.create_table()?;

    base64.set(
        "encode",
        lua.create_function(|_, text: mlua::String| Ok(STANDARD.encode(text.as_bytes().to_vec())))?,
    )?;

    base64.set(
        "decode",
        lua.create_function(|lua, text: String| {
            let bytes = STANDARD
                .decode(text.trim())
                .map_err(|error| mlua::Error::runtime(format!("not valid base64: {error}")))?;
            lua.create_string(bytes)
        })?,
    )?;

    roflux.set("base64", base64)?;

    roflux.set(
        "hash",
        lua.create_function(|_, (text, algorithm): (mlua::String, Option<String>)| {
            if let Some(name) = &algorithm {
                if !name.eq_ignore_ascii_case("sha256") {
                    return Err(mlua::Error::runtime(format!("unknown hash \"{name}\", only sha256 is supported")));
                }
            }

            let digest = Sha256::digest(text.as_bytes().to_vec());
            Ok(digest.iter().map(|byte| format!("{byte:02x}")).collect::<String>())
        })?,
    )?;

    let luau = lua.create_table()?;

    luau.set(
        "literal",
        lua.create_function(|lua, value: Value| Ok(crate::literal::emit(&plain(lua, value)?)))?,
    )?;

    luau.set(
        "module",
        lua.create_function(|lua, value: Value| {
            Ok(format!("return {}\n", crate::literal::emit(&plain(lua, value)?)))
        })?,
    )?;

    luau.set(
        "quote",
        lua.create_function(|_, text: String| Ok(crate::literal::quote(&text)))?,
    )?;

    roflux.set("luau", luau)?;

    Ok(())
}
