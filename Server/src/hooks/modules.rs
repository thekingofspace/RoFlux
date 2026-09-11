use std::collections::HashSet;
use std::path::Path;
use std::sync::{Arc, Mutex};

use mlua::{Error, Lua, MultiValue, Result, Table, ThreadStatus, Value};

pub type Required = Arc<Mutex<HashSet<String>>>;

const SUFFIXES: &[&str] = &[".luau", ".lua", "/init.luau", "/init.lua"];

fn registry(lua: &Lua, key: &str) -> Result<Table> {
    if let Ok(table) = lua.named_registry_value::<Table>(key) {
        return Ok(table);
    }

    let table = lua.create_table()?;
    lua.set_named_registry_value(key, &table)?;
    Ok(table)
}

fn cache(lua: &Lua) -> Result<Table> {
    registry(lua, "roflux.modules")
}

fn loading(lua: &Lua) -> Result<Table> {
    registry(lua, "roflux.loading")
}

fn folder(relative: &str) -> &str {
    relative.rsplit_once('/').map(|(head, _)| head).unwrap_or("")
}

fn join(base: &str, target: &str) -> Option<String> {
    let mut parts: Vec<&str> = base.split('/').filter(|part| !part.is_empty()).collect();

    for part in target.split('/') {
        match part {
            "" | "." => {}
            ".." => {
                parts.pop()?;
            }
            other if other.contains(':') => return None,
            other => parts.push(other),
        }
    }

    Some(parts.join("/"))
}

fn locate(root: &Path, relative: &str) -> Option<String> {
    let lower = relative.to_ascii_lowercase();

    if (lower.ends_with(".luau") || lower.ends_with(".lua")) && root.join(relative).is_file() {
        return Some(relative.to_string());
    }

    SUFFIXES.iter().find_map(|suffix| {
        let candidate = if relative.is_empty() {
            suffix.trim_start_matches('/').to_string()
        } else {
            format!("{relative}{suffix}")
        };

        root.join(&candidate).is_file().then_some(candidate)
    })
}

pub fn loaded(lua: &Lua, relative: &str) -> Result<bool> {
    Ok(!cache(lua)?.get::<Value>(relative)?.is_nil())
}

fn environment(lua: &Lua, root: &Path, required: &Required, relative: &str) -> Result<Table> {
    let base = folder(relative).to_string();
    let root = root.to_path_buf();
    let required = required.clone();

    let require = lua.create_function(move |lua, target: String| {
        let target = target.replace('\\', "/");

        if !target.starts_with("./") && !target.starts_with("../") {
            return Err(Error::runtime(format!(
                "require(\"{target}\") needs a path that starts with ./ or ../"
            )));
        }

        let joined = join(&base, &target)
            .ok_or_else(|| Error::runtime(format!("require(\"{target}\") is outside the project")))?;

        let found = locate(&root, &joined)
            .ok_or_else(|| Error::runtime(format!("require(\"{target}\") found nothing at {joined}")))?;

        load(lua, &root, &required, &found)
    })?;

    let env = lua.create_table()?;
    env.set("require", require)?;

    let meta = lua.create_table()?;
    meta.set("__index", lua.globals())?;
    meta.set("__newindex", lua.globals())?;
    env.set_metatable(Some(meta))?;

    Ok(env)
}

fn execute(lua: &Lua, root: &Path, required: &Required, relative: &str) -> Result<Value> {
    let body = std::fs::read_to_string(root.join(relative))
        .map_err(|error| Error::runtime(format!("{relative}: {error}")))?;

    let env = environment(lua, root, required, relative)?;
    let chunk = lua.load(body).set_name(relative).set_environment(env).into_function()?;
    let thread = lua.create_thread(chunk)?;
    let produced = thread.resume::<MultiValue>(())?;

    if thread.status() == ThreadStatus::Resumable {
        return Err(Error::runtime(format!("{relative} yielded while loading, scripts must not yield")));
    }

    Ok(produced.into_iter().next().unwrap_or(Value::Nil))
}

pub fn load(lua: &Lua, root: &Path, required: &Required, relative: &str) -> Result<Value> {
    let cached = cache(lua)?.get::<Value>(relative)?;

    if !cached.is_nil() {
        return Ok(cached);
    }

    let loading = loading(lua)?;

    if loading.get::<bool>(relative).unwrap_or(false) {
        return Err(Error::runtime(format!("{relative} requires itself through a loop")));
    }

    if let Ok(mut set) = required.lock() {
        set.insert(relative.to_string());
    }

    loading.set(relative, true)?;
    let result = execute(lua, root, required, relative);
    loading.set(relative, Value::Nil)?;

    let value = match result? {
        Value::Nil => Value::Boolean(true),
        value => value,
    };

    cache(lua)?.set(relative, value.clone())?;

    Ok(value)
}
