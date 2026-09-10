use std::path::PathBuf;

use mlua::{Function, Lua, Result, Table, Value};

use crate::log;

pub const EVENTS: &[&str] = &[
    "read",
    "transfer",
    "added",
    "removed",
    "changed",
    "compile",
    "sync",
];

pub fn state(lua: &Lua) -> Result<Table> {
    lua.named_registry_value::<Table>("roflux.state")
}

pub fn listeners(lua: &Lua, event: &str) -> Result<Table> {
    state(lua)?.get::<Table>("events")?.get::<Table>(event)
}

pub fn transpilers(lua: &Lua) -> Result<Table> {
    state(lua)?.get::<Table>("transpilers")
}

pub fn pending(lua: &Lua) -> Result<Table> {
    state(lua)?.get::<Table>("pending")
}

fn describe(values: &[Value]) -> String {
    values
        .iter()
        .map(|value| match value {
            Value::String(text) => text.to_string_lossy().to_string(),
            Value::Integer(number) => number.to_string(),
            Value::Number(number) => number.to_string(),
            Value::Boolean(flag) => flag.to_string(),
            Value::Nil => "nil".into(),
            other => format!("{other:?}"),
        })
        .collect::<Vec<_>>()
        .join(" ")
}

pub fn install(lua: &Lua, root: PathBuf) -> Result<()> {
    let state = lua.create_table()?;
    let events = lua.create_table()?;

    for event in EVENTS {
        events.set(*event, lua.create_table()?)?;
    }

    state.set("events", events)?;
    state.set("transpilers", lua.create_table()?)?;
    state.set("pending", lua.create_table()?)?;
    state.set("source", lua.create_table()?)?;

    lua.set_named_registry_value("roflux.state", &state)?;

    let roflux = lua.create_table()?;

    roflux.set(
        "on",
        lua.create_function(|lua, (event, callback): (String, Function)| {
            let list = listeners(lua, &event).map_err(|_| {
                mlua::Error::runtime(format!("unknown event \"{event}\""))
            })?;

            list.push(callback)?;
            Ok(())
        })?,
    )?;

    for event in EVENTS {
        let name = format!("on{}{}", event[..1].to_uppercase(), &event[1..]);
        let key = event.to_string();

        roflux.set(
            name,
            lua.create_function(move |lua, callback: Function| {
                listeners(lua, &key)?.push(callback)?;
                Ok(())
            })?,
        )?;
    }

    roflux.set(
        "transpile",
        lua.create_function(|lua, (extension, callback): (String, Function)| {
            let extension = extension.trim_start_matches('.').to_ascii_lowercase();
            transpilers(lua)?.set(extension, callback)?;
            Ok(())
        })?,
    )?;

    roflux.set(
        "defer",
        lua.create_function(|lua, callback: Function| {
            let thread = lua.create_thread(callback)?;
            pending(lua)?.push(thread)?;
            Ok(())
        })?,
    )?;

    roflux.set(
        "log",
        lua.create_function(|_, values: mlua::MultiValue| {
            log::hook(describe(&values.into_vec()));
            Ok(())
        })?,
    )?;

    roflux.set(
        "warn",
        lua.create_function(|_, values: mlua::MultiValue| {
            log::warn(describe(&values.into_vec()));
            Ok(())
        })?,
    )?;

    super::files::install(lua, &roflux, root)?;

    lua.globals().set("roflux", roflux)?;

    Ok(())
}
