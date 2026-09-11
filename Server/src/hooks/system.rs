use std::collections::BTreeMap;
use std::process::{Command, Stdio};
use std::sync::{Mutex, MutexGuard, OnceLock};

use mlua::{Lua, LuaSerdeExt, Result, Table, Value};
use serde_json::{json, Value as Json};

use super::files::{deny, resolve};
use super::Setup;

fn store() -> Result<MutexGuard<'static, BTreeMap<String, Json>>> {
    static STORE: OnceLock<Mutex<BTreeMap<String, Json>>> = OnceLock::new();

    STORE
        .get_or_init(|| Mutex::new(BTreeMap::new()))
        .lock()
        .map_err(|_| mlua::Error::runtime("roflux.cache is poisoned"))
}

pub fn install(lua: &Lua, roflux: &Table, setup: &Setup) -> Result<()> {
    roflux.set(
        "env",
        lua.create_function(|_, name: String| Ok(std::env::var(name).ok()))?,
    )?;

    roflux.set(
        "platform",
        lua.create_function(|_, ()| Ok(std::env::consts::OS))?,
    )?;

    roflux.set(
        "version",
        lua.create_function(|_, ()| Ok(env!("CARGO_PKG_VERSION")))?,
    )?;

    let project = json!({
        "name": setup.name,
        "id": setup.id,
        "root": setup.root.to_string_lossy().replace('\\', "/"),
        "manifest": setup.manifest,
    });

    roflux.set(
        "project",
        lua.create_function(move |lua, ()| lua.to_value(&project))?,
    )?;

    let scripts = setup.scripts.clone();

    roflux.set(
        "config",
        lua.create_function(move |lua, key: Option<String>| {
            let value = match &key {
                Some(key) => scripts.get(key).cloned().unwrap_or(Json::Null),
                None if scripts.is_object() => scripts.clone(),
                None => json!({}),
            };

            if value.is_null() {
                return Ok(Value::Nil);
            }

            lua.to_value(&value)
        })?,
    )?;

    let allowed = setup.allow_exec();
    let base = setup.root.clone();

    roflux.set(
        "exec",
        lua.create_function(
            move |lua, (program, args, options): (String, Option<Vec<String>>, Option<Table>)| {
                if !allowed {
                    return Err(mlua::Error::runtime(
                        "roflux.exec is off. Set \"Scripts\": { \"AllowExec\": true } in the project file to allow it",
                    ));
                }

                let cwd = match &options {
                    Some(options) => options.get::<Option<String>>("cwd")?,
                    None => None,
                };

                let folder = match cwd {
                    Some(relative) => resolve(&base, &relative).ok_or_else(|| deny(&relative))?,
                    None => base.clone(),
                };

                let output = Command::new(&program)
                    .args(args.unwrap_or_default())
                    .current_dir(folder)
                    .stdin(Stdio::null())
                    .output()
                    .map_err(|error| mlua::Error::runtime(format!("could not run \"{program}\": {error}")))?;

                let result = lua.create_table()?;
                result.set("ok", output.status.success())?;
                result.set("code", output.status.code().unwrap_or(-1))?;
                result.set("stdout", lua.create_string(&output.stdout)?)?;
                result.set("stderr", lua.create_string(&output.stderr)?)?;
                Ok(result)
            },
        )?,
    )?;

    let cache = lua.create_table()?;

    cache.set(
        "get",
        lua.create_function(|lua, key: String| {
            let found = store()?.get(&key).cloned();

            match found {
                Some(value) => lua.to_value(&value),
                None => Ok(Value::Nil),
            }
        })?,
    )?;

    cache.set(
        "set",
        lua.create_function(|lua, (key, value): (String, Value)| {
            if value.is_nil() {
                store()?.remove(&key);
                return Ok(());
            }

            let plain: Json = lua.from_value(value)?;
            store()?.insert(key, plain);
            Ok(())
        })?,
    )?;

    cache.set(
        "has",
        lua.create_function(|_, key: String| Ok(store()?.contains_key(&key)))?,
    )?;

    cache.set(
        "delete",
        lua.create_function(|_, key: String| Ok(store()?.remove(&key).is_some()))?,
    )?;

    cache.set(
        "clear",
        lua.create_function(|_, ()| {
            store()?.clear();
            Ok(())
        })?,
    )?;

    cache.set(
        "keys",
        lua.create_function(|lua, ()| {
            let keys: Vec<String> = store()?.keys().cloned().collect();
            lua.create_sequence_from(keys)
        })?,
    )?;

    roflux.set("cache", cache)?;

    Ok(())
}
