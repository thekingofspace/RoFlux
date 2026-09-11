pub mod api;
pub mod data;
pub mod files;
pub mod modules;
pub mod outbox;
pub mod system;

use std::collections::HashSet;
use std::path::PathBuf;
use std::sync::{Arc, Mutex};

use anyhow::{anyhow, Result};
use mlua::{Function, Lua, LuaSerdeExt, MultiValue, SerializeOptions, Table, Thread, ThreadStatus, Value as LuaValue};
use serde_json::Value;

use crate::ir::{Node, Tree};
use crate::log;
use crate::project::{meta, Loaded, Transform};

const PRELUDE: &str = include_str!("prelude.luau");

#[derive(Clone, Debug, Default)]
pub struct Setup {
    pub root: PathBuf,
    pub name: String,
    pub id: String,
    pub manifest: String,
    pub scripts: Value,
}

impl Setup {
    pub fn allow_exec(&self) -> bool {
        self.scripts
            .get("AllowExec")
            .and_then(Value::as_bool)
            .unwrap_or(false)
    }
}

pub struct Hooks {
    lua: Mutex<Lua>,
    extensions: HashSet<String>,
    scripts: usize,
    required: modules::Required,
}

impl Hooks {
    pub fn count(&self) -> usize {
        self.scripts
    }

    pub fn depends_on(&self, relative: &str) -> bool {
        self.required
            .lock()
            .map(|set| set.contains(relative))
            .unwrap_or(false)
    }

    pub fn load(setup: &Setup) -> Result<Self> {
        let lua = Lua::new();
        api::install(&lua, setup)?;
        run(&lua, PRELUDE, "roflux.prelude").map_err(|error| anyhow!("prelude: {error}"))?;

        let root = &setup.root;
        let folder = root.join("scripts");
        let required: modules::Required = Arc::new(Mutex::new(HashSet::new()));
        let mut scripts = 0;

        if folder.is_dir() {
            let mut files = Vec::new();

            for entry in walkdir::WalkDir::new(&folder).sort_by_file_name() {
                let entry = entry?;

                if !entry.file_type().is_file() {
                    continue;
                }

                let name = entry.file_name().to_string_lossy().to_string();

                if !crate::project::classify::is_luau(&name) || crate::project::classify::definition(&name) {
                    continue;
                }

                files.push(entry.path().to_path_buf());
            }

            for file in files {
                let relative = file
                    .strip_prefix(root)
                    .unwrap_or(&file)
                    .to_string_lossy()
                    .replace('\\', "/");

                scripts += 1;

                if modules::loaded(&lua, &relative)? {
                    continue;
                }

                modules::load(&lua, root, &required, &relative).map_err(|error| anyhow!("{relative}: {error}"))?;
            }
        }

        let mut extensions = HashSet::new();

        for pair in api::transpilers(&lua)?.pairs::<String, Function>() {
            let (extension, _) = pair?;
            extensions.insert(extension);
        }

        Ok(Hooks {
            lua: Mutex::new(lua),
            extensions,
            scripts,
            required,
        })
    }

    pub fn notify(&self, event: &str, relative: &str) {
        let Ok(lua) = self.lua.lock() else {
            return;
        };

        let context = match context(&lua, relative) {
            Ok(context) => context,
            Err(error) => {
                log::warn(format!("hook context failed: {error}"));
                return;
            }
        };

        if let Err(error) = broadcast(&lua, event, context) {
            log::warn(format!("{event} hook failed: {error}"));
        }
    }

    pub fn emit(&self, event: &str, payload: &Value) {
        let Ok(lua) = self.lua.lock() else {
            return;
        };

        let waiting = api::listeners(&lua, event)
            .map(|list| list.raw_len() > 0)
            .unwrap_or(false);

        if !waiting {
            return;
        }

        let context = match lua.to_value(payload) {
            Ok(LuaValue::Table(table)) => table,
            Ok(_) => return,
            Err(error) => {
                log::warn(format!("{event} hook payload failed: {error}"));
                return;
            }
        };

        if let Err(error) = broadcast(&lua, event, context) {
            log::warn(format!("{event} hook failed: {error}"));
        }
    }

    pub fn relay(&self, event: &str, values: &[Value]) {
        let Ok(lua) = self.lua.lock() else {
            return;
        };

        let Ok(listeners) = api::listeners(&lua, event) else {
            return;
        };

        if listeners.raw_len() == 0 {
            return;
        }

        let options = SerializeOptions::new()
            .serialize_none_to_null(false)
            .serialize_unit_to_null(false)
            .set_array_metatable(false);

        let mut arguments = Vec::with_capacity(values.len());

        for value in values {
            match lua.to_value_with(value, options) {
                Ok(converted) => arguments.push(converted),
                Err(error) => {
                    log::warn(format!("{event} hook payload failed: {error}"));
                    return;
                }
            }
        }

        for pair in listeners.clone().pairs::<i64, Function>() {
            let Ok((_, callback)) = pair else {
                continue;
            };

            if let Err(error) = call(&lua, &callback, MultiValue::from_vec(arguments.clone())) {
                log::warn(format!("{event} hook failed: {error}"));
            }
        }
    }

    pub fn tree(&self, tree: &mut Tree) -> Result<()> {
        let lua = self.lua.lock().map_err(|_| anyhow!("hook runtime is poisoned"))?;
        let listeners = api::listeners(&lua, "tree")?;

        if listeners.raw_len() == 0 {
            return Ok(());
        }

        let LuaValue::Table(mut root) = lua.to_value(&tree.root)? else {
            return Err(anyhow!("the tree could not be handed to onTree"));
        };

        fill(&lua, &root)?;

        for pair in listeners.clone().pairs::<i64, Function>() {
            let (_, callback) = pair?;

            if let Some(LuaValue::Table(replaced)) = invoke(&lua, &callback, &root)? {
                fill(&lua, &replaced)?;
                root = replaced;
            }
        }

        let mut rebuilt: Node = lua
            .from_value(LuaValue::Table(root))
            .map_err(|error| anyhow!("onTree left a node RoFlux cannot read: {error}"))?;

        rebuilt.sort();
        crate::ir::reindex_root(&mut rebuilt);
        tree.root = rebuilt;

        Ok(())
    }

    pub fn drain(&self) {
        let Ok(lua) = self.lua.lock() else {
            return;
        };

        let Ok(pending) = api::pending(&lua) else {
            return;
        };

        let Ok(length) = pending.raw_len().try_into() else {
            return;
        };

        let mut resumed: Vec<Thread> = Vec::new();

        for index in 1..=length {
            if let Ok(thread) = pending.raw_get::<Thread>(index) {
                resumed.push(thread);
            }
        }

        pending.clear().ok();

        for thread in resumed {
            if thread.status() != ThreadStatus::Resumable {
                continue;
            }

            if let Err(error) = thread.resume::<MultiValue>(()) {
                log::warn(format!("deferred hook failed: {error}"));
                continue;
            }

            if thread.status() == ThreadStatus::Resumable {
                pending.push(thread).ok();
            }
        }
    }
}

pub(crate) fn fill(lua: &Lua, node: &Table) -> mlua::Result<()> {
    for key in ["properties", "attributes", "tags", "children", "filePaths"] {
        if node.get::<LuaValue>(key)?.is_nil() {
            node.set(key, lua.create_table()?)?;
        }
    }

    if node.get::<LuaValue>("id")?.is_nil() {
        node.set("id", "")?;
    }

    if node.get::<LuaValue>("ownership")?.is_nil() {
        node.set("ownership", "managed")?;
    }

    let children: Table = node.get("children")?;

    for child in children.sequence_values::<Table>() {
        fill(lua, &child?)?;
    }

    Ok(())
}

fn run(lua: &Lua, body: &str, name: &str) -> Result<()> {
    let chunk = lua.load(body).set_name(name).into_function()?;
    let thread = lua.create_thread(chunk)?;

    thread.resume::<MultiValue>(())?;

    if thread.status() == ThreadStatus::Resumable {
        return Err(anyhow!("scripts must not yield while loading"));
    }

    Ok(())
}

fn context(lua: &Lua, relative: &str) -> mlua::Result<Table> {
    let name = relative.rsplit('/').next().unwrap_or(relative);
    let folder = relative.rsplit_once('/').map(|(head, _)| head).unwrap_or("");
    let stem = name.split('.').next().unwrap_or(name);

    let context = lua.create_table()?;
    context.set("path", relative)?;
    context.set("name", name)?;
    context.set("stem", stem)?;
    context.set("folder", folder)?;
    context.set(
        "extension",
        relative.rsplit_once('.').map(|(_, tail)| tail.to_ascii_lowercase()).unwrap_or_default(),
    )?;
    Ok(context)
}

fn invoke(lua: &Lua, callback: &Function, context: &Table) -> Result<Option<LuaValue>> {
    call(lua, callback, MultiValue::from_vec(vec![LuaValue::Table(context.clone())]))
}

fn call(lua: &Lua, callback: &Function, arguments: MultiValue) -> Result<Option<LuaValue>> {
    let thread = lua.create_thread(callback.clone())?;
    let produced = thread.resume::<MultiValue>(arguments)?;

    if thread.status() == ThreadStatus::Resumable {
        api::pending(lua)?.push(thread)?;
        log::warn("a hook yielded, its result was skipped for this pass");
        return Ok(None);
    }

    Ok(produced.into_vec().into_iter().next())
}

fn broadcast(lua: &Lua, event: &str, context: Table) -> Result<()> {
    let listeners = api::listeners(lua, event)?;

    for pair in listeners.clone().pairs::<i64, Function>() {
        let (_, callback) = pair?;
        invoke(lua, &callback, &context)?;
    }

    Ok(())
}

fn chain(lua: &Lua, event: &str, context: &Table) -> Result<()> {
    let listeners = api::listeners(lua, event)?;

    for pair in listeners.clone().pairs::<i64, Function>() {
        let (_, callback) = pair?;

        let produced = invoke(lua, &callback, context)?;

        match produced {
            Some(LuaValue::String(text)) => {
                context.set("source", text.to_string_lossy())?;
            }
            Some(LuaValue::Table(table)) => {
                if let Ok(source) = table.get::<String>("source") {
                    context.set("source", source)?;
                }
            }
            _ => {}
        }
    }

    Ok(())
}

fn single(decoded: &Value) -> Loaded {
    let parsed = meta::parse(decoded, "transpiler");

    if parsed.ignore {
        return Loaded {
            skip: true,
            ..Loaded::default()
        };
    }

    let mut children = Vec::new();

    for (name, child) in &parsed.children {
        if child.ignore {
            continue;
        }

        let class_name = child.class_name.clone().unwrap_or_else(|| "Folder".into());
        let mut node = Node::new("", name, class_name);
        crate::project::scan::apply_declaration(&mut node, child);
        children.push(node);
    }

    Loaded {
        class_name: parsed.class_name.clone(),
        name: parsed.name.clone(),
        parent: parsed.parent.clone(),
        properties: parsed.properties.clone(),
        attributes: parsed.attributes.clone(),
        tags: parsed.tags.clone(),
        children,
        skip: false,
    }
}

fn declaration(lua: &Lua, value: LuaValue) -> Result<Option<Vec<Loaded>>> {
    if let LuaValue::String(text) = &value {
        let mut loaded = Loaded {
            class_name: Some("ModuleScript".into()),
            ..Loaded::default()
        };

        loaded
            .properties
            .insert("Source".into(), Value::String(text.to_string_lossy().to_string()));

        return Ok(Some(vec![loaded]));
    }

    let LuaValue::Table(_) = &value else {
        return Ok(None);
    };

    let decoded: Value = lua.from_value(value)?;

    match &decoded {
        Value::Array(items) => {
            let mut built = Vec::new();

            for item in items {
                built.push(single(item));
            }

            Ok(Some(built))
        }
        _ => Ok(Some(vec![single(&decoded)])),
    }
}

impl Transform for Hooks {
    fn claims(&self, extension: &str) -> bool {
        self.extensions.contains(extension)
    }

    fn source(&self, relative: &str, class_name: &str, source: String) -> Result<String> {
        let lua = self.lua.lock().map_err(|_| anyhow!("hook runtime is poisoned"))?;

        let listeners = api::listeners(&lua, "read")?.raw_len() + api::listeners(&lua, "transfer")?.raw_len();

        if listeners == 0 {
            return Ok(source);
        }

        let context = context(&lua, relative)?;
        context.set("className", class_name)?;
        context.set("source", source.clone())?;

        chain(&lua, "read", &context)?;
        chain(&lua, "transfer", &context)?;

        Ok(context.get::<String>("source").unwrap_or(source))
    }

    fn file(&self, relative: &str, extension: &str, raw: &str) -> Result<Option<Vec<Loaded>>> {
        let lua = self.lua.lock().map_err(|_| anyhow!("hook runtime is poisoned"))?;

        let Ok(callback) = api::transpilers(&lua)?.get::<Function>(extension) else {
            return Ok(None);
        };

        let context = context(&lua, relative)?;
        context.set("source", raw)?;
        context.set("text", raw)?;

        let Some(produced) = invoke(&lua, &callback, &context)? else {
            return Ok(None);
        };

        declaration(&lua, produced)
    }
}
