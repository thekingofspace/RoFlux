use std::path::{Path, PathBuf};

use anyhow::{Context, Result};
use serde_json::{Map, Value};

use super::classify::{self, Kind};
use super::meta::{self, Meta};
use super::Transform;
use crate::ir::{Node, Ownership, Tree};
use crate::log;
use crate::paths;

pub struct Config {
    pub id: String,
    pub name: String,
    pub default_parent: Option<String>,
    pub services: Vec<(String, Meta)>,
    pub include: Vec<String>,
    pub exclude: Vec<String>,
    pub scripts: Value,
}

pub struct Scanner<'a> {
    root: PathBuf,
    transform: &'a dyn Transform,
    hoisted: Vec<(String, Node)>,
    files: Vec<PathBuf>,
    include: Vec<String>,
    exclude: Vec<String>,
    mounted: Vec<PathBuf>,
}

struct Entry {
    node: Node,
    parent: Option<String>,
}

fn names(object: &serde_json::Map<String, Value>, key: &str) -> Vec<String> {
    object
        .get(key)
        .or_else(|| object.get(&format!("${key}")))
        .and_then(Value::as_array)
        .map(|items| {
            items
                .iter()
                .filter_map(Value::as_str)
                .map(|value| value.trim_matches('/').to_string())
                .filter(|value| !value.is_empty())
                .collect()
        })
        .unwrap_or_default()
}

pub fn config_from(root: &Path, manifest: &str) -> Result<Config> {
    let file = root.join(manifest);
    let name = root
        .file_name()
        .map(|value| value.to_string_lossy().to_string())
        .unwrap_or_else(|| "Project".into());

    if !file.exists() {
        log::warn(format!("no {manifest}, using defaults"));
        return Ok(Config {
            id: name.clone(),
            name,
            default_parent: None,
            services: Vec::new(),
            include: Vec::new(),
            exclude: Vec::new(),
            scripts: Value::Null,
        });
    }

    let value = meta::read(&file).with_context(|| manifest.to_string())?;
    let object = value.as_object().cloned().unwrap_or_default();

    let id = object
        .get("ProjectID")
        .or_else(|| object.get("$ProjectID"))
        .and_then(Value::as_str)
        .unwrap_or(&name)
        .to_string();

    let default_parent = object
        .get("Default")
        .or_else(|| object.get("$Default"))
        .and_then(Value::as_str)
        .map(str::to_string);

    let mut services = Vec::new();

    let include = names(&object, "Include");
    let exclude = names(&object, "Exclude");
    let scripts = object.get("Scripts").cloned().unwrap_or(Value::Null);

    let reserved = ["ProjectID", "Default", "Name", "Include", "Exclude", "Scripts"];

    for (key, entry) in &object {
        if key.starts_with('$') || reserved.contains(&key.as_str()) {
            continue;
        }
        if !entry.is_object() {
            continue;
        }
        services.push((key.clone(), meta::parse(entry, manifest)));
    }

    let name = object
        .get("Name")
        .and_then(Value::as_str)
        .map(str::to_string)
        .unwrap_or(name);

    Ok(Config {
        id,
        name,
        default_parent,
        services,
        include,
        exclude,
        scripts,
    })
}

pub fn build_with(root: &Path, transform: &dyn Transform, config: &Config) -> Result<(Tree, Vec<PathBuf>)> {
    let mut tree = Tree::new(&config.name);
    let mut scanner = Scanner {
        root: root.to_path_buf(),
        transform,
        hoisted: Vec::new(),
        files: Vec::new(),
        include: config.include.clone(),
        exclude: config.exclude.clone(),
        mounted: Vec::new(),
    };

    for (path, declared) in &config.services {
        let mut built = Vec::new();

        for (name, child) in &declared.children {
            if child.ignore {
                continue;
            }

            let class_name = child.class_name.clone().unwrap_or_else(|| "Folder".into());
            let mut node = Node::new("", name, class_name);
            apply_declaration(&mut node, child);

            if let Some(target) = &child.path {
                match scanner.mount(target, name)? {
                    Some(mounted) => merge(&mut node, mounted),
                    None => log::warn(format!("$Path \"{target}\" does not exist")),
                }
            }

            built.push(node);
        }

        let contents = match &declared.path {
            Some(target) => scanner.contents(target, path)?,
            None => None,
        };

        let parts = paths::split(path);
        let slot = tree.reserve(&parts, container);

        if let Some(contents) = contents {
            fill(slot, contents);
        }

        apply(slot, declared);

        for node in built {
            attach(slot, node);
        }
    }

    let entries = scanner.directory(root, true)?;

    for entry in entries {
        let parent = entry.parent.clone().or_else(|| config.default_parent.clone());

        match parent {
            Some(parent) => place(&mut tree, &parent, entry.node),
            None => log::warn(format!(
                "\"{}\" has no $Parent and the project has no $Default, skipping it",
                entry.node.name
            )),
        }
    }

    for (parent, node) in std::mem::take(&mut scanner.hoisted) {
        place(&mut tree, &parent, node);
    }

    let files = scanner.files.clone();
    tree.sort();
    crate::ir::reindex_root(&mut tree.root);

    Ok((tree, files))
}

pub fn build_folder(root: &Path, transform: &dyn Transform, name: &str) -> Result<Node> {
    let mut scanner = Scanner {
        root: root.to_path_buf(),
        transform,
        hoisted: Vec::new(),
        files: Vec::new(),
        include: Vec::new(),
        exclude: Vec::new(),
        mounted: Vec::new(),
    };

    let entry = scanner
        .folder(root, name)?
        .ok_or_else(|| anyhow::anyhow!("{} has nothing to build", root.display()))?;

    let mut node = entry.node;
    node.sort();
    crate::ir::reindex(&mut node, "");

    Ok(node)
}

const CONTAINERS: &[&str] = &["StarterPlayerScripts", "StarterCharacterScripts"];

fn container(depth: usize, part: &str) -> String {
    if depth == 0 || CONTAINERS.contains(&part) {
        part.to_string()
    } else {
        "Folder".into()
    }
}

fn place(tree: &mut Tree, parent: &str, node: Node) {
    let parts = paths::split(parent);
    let slot = tree.reserve(&parts, container);
    attach(slot, node);
}

fn attach(slot: &mut Node, node: Node) {
    match slot.child_index(&node.name) {
        Some(index) => merge(&mut slot.children[index], node),
        None => slot.children.push(node),
    }
}

fn fill(slot: &mut Node, contents: Node) {
    for (key, value) in contents.properties {
        if key != "Source" {
            slot.properties.insert(key, value);
        }
    }

    for (key, value) in contents.attributes {
        slot.attributes.insert(key, value);
    }

    for tag in contents.tags {
        if !slot.tags.contains(&tag) {
            slot.tags.push(tag);
        }
    }

    for path in contents.file_paths {
        if !slot.file_paths.contains(&path) {
            slot.file_paths.push(path);
        }
    }

    for child in contents.children {
        attach(slot, child);
    }
}

fn merge(target: &mut Node, incoming: Node) {
    if incoming.class_name != "Folder" {
        target.class_name = incoming.class_name;
    }

    if incoming.ownership == Ownership::Managed {
        target.ownership = Ownership::Managed;
    }

    for (key, value) in incoming.properties {
        target.properties.insert(key, value);
    }

    for (key, value) in incoming.attributes {
        target.attributes.insert(key, value);
    }

    for tag in incoming.tags {
        if !target.tags.contains(&tag) {
            target.tags.push(tag);
        }
    }

    for path in incoming.file_paths {
        if !target.file_paths.contains(&path) {
            target.file_paths.push(path);
        }
    }

    for child in incoming.children {
        attach(target, child);
    }
}

fn stamp(node: &mut Node, relative: &str) {
    if !node.file_paths.iter().any(|path| path == relative) {
        node.file_paths.push(relative.to_string());
    }

    for child in &mut node.children {
        stamp(child, relative);
    }
}

fn blank(declared: &Meta) -> bool {
    declared.class_name.is_none()
        && declared.from_model.is_none()
        && declared.path.is_none()
        && declared.children.is_empty()
        && declared.properties.is_empty()
        && declared.attributes.is_empty()
        && declared.tags.is_empty()
}

fn apply(node: &mut Node, declared: &Meta) {
    for (key, value) in &declared.properties {
        node.properties.insert(key.clone(), value.clone());
    }

    for (key, value) in &declared.attributes {
        node.attributes.insert(key.clone(), value.clone());
    }

    for tag in &declared.tags {
        if !node.tags.contains(tag) {
            node.tags.push(tag.clone());
        }
    }
}

pub fn apply_declaration(node: &mut Node, declared: &Meta) {
    apply(node, declared);

    if let Some(name) = &declared.name {
        node.name = name.clone();
    }

    if declared.from_model.is_some() {
        node.ownership = Ownership::Reference;
    }

    for (name, child) in &declared.children {
        if child.ignore {
            continue;
        }

        let class_name = child.class_name.clone().unwrap_or_else(|| "Folder".into());
        let mut built = Node::new("", name, class_name);
        built.ownership = node.ownership;
        apply_declaration(&mut built, child);
        attach(node, built);
    }
}

impl Scanner<'_> {
    fn wanted(&self, name: &str) -> bool {
        if self.exclude.iter().any(|entry| entry == name) {
            return false;
        }

        if self.include.is_empty() {
            return true;
        }

        self.include.iter().any(|entry| entry == name)
    }

    fn remember(&mut self, path: &Path) {
        self.mounted.push(path.canonicalize().unwrap_or_else(|_| path.to_path_buf()));
    }

    fn is_mounted(&self, path: &Path) -> bool {
        let path = path.canonicalize().unwrap_or_else(|_| path.to_path_buf());
        self.mounted.contains(&path)
    }

    fn contents(&mut self, target: &str, service: &str) -> Result<Option<Node>> {
        let path = self.root.join(target.replace('\\', "/"));

        if !path.is_dir() {
            log::warn(format!(
                "\"{service}\" has $Path \"{target}\", which needs to be a folder that exists"
            ));
            return Ok(None);
        }

        self.remember(&path);

        let name = paths::split(service).last().cloned().unwrap_or_default();
        Ok(self.folder(&path, &name)?.map(|entry| entry.node))
    }

    fn mount(&mut self, target: &str, name: &str) -> Result<Option<Node>> {
        let path = self.root.join(target.replace('\\', "/"));

        if path.is_dir() {
            self.remember(&path);
            return Ok(self.folder(&path, name)?.map(|entry| entry.node));
        }

        if !path.is_file() {
            return Ok(None);
        }

        let file = path
            .file_name()
            .map(|value| value.to_string_lossy().to_string())
            .unwrap_or_default();

        let (kind, _) = classify::classify(&file);
        let mut nodes = self.file(&path, &kind, name)?;

        if nodes.is_empty() {
            return Ok(None);
        }

        let mut node = nodes.remove(0);
        node.name = name.to_string();

        Ok(Some(node))
    }

    fn relative(&self, path: &Path) -> String {
        path.strip_prefix(&self.root)
            .unwrap_or(path)
            .to_string_lossy()
            .replace('\\', "/")
    }

    fn directory(&mut self, path: &Path, top: bool) -> Result<Vec<Entry>> {
        let mut folders = Vec::new();
        let mut files = Vec::new();

        for entry in std::fs::read_dir(path).with_context(|| path.display().to_string())? {
            let entry = entry?;
            let name = entry.file_name().to_string_lossy().to_string();

            if name.starts_with('.') || name == "target" || name == "node_modules" {
                continue;
            }

            if top && (name == "sourcemap.json" || name == "Cargo.toml" || name == "Cargo.lock") {
                continue;
            }

            if entry.file_type()?.is_dir() {
                folders.push((name, entry.path()));
            } else {
                files.push((name, entry.path()));
            }
        }

        folders.sort_by(|a, b| a.0.cmp(&b.0));
        files.sort_by(|a, b| a.0.cmp(&b.0));

        let mut sidecars: Vec<(String, Meta)> = Vec::new();
        let mut entries: Vec<Entry> = Vec::new();

        for (name, file) in &files {
            if let (Kind::Sidecar(stem), _) = classify::classify(name) {
                self.files.push(file.clone());
                let value = meta::read(file).with_context(|| self.relative(file))?;
                sidecars.push((stem, meta::parse(&value, &self.relative(file))));
            }
        }

        for (name, file) in &files {
            if top && !name.eq_ignore_ascii_case("meta.inst.json") {
                continue;
            }

            let (kind, stem) = classify::classify(name);

            match kind {
                Kind::Ignored | Kind::InitMeta | Kind::InitScript(_) | Kind::Sidecar(_) => continue,
                _ => {}
            }

            self.files.push(file.clone());

            for mut node in self.file(file, &kind, &stem)? {
                let declared = sidecars.iter().find(|(key, _)| *key == stem).map(|(_, value)| value);

                match declared {
                    Some(declared) => {
                        if declared.ignore {
                            continue;
                        }
                        apply_declaration(&mut node, declared);
                        let parent = declared.parent.clone();
                        entries.push(Entry { node, parent });
                    }
                    None => entries.push(Entry { node, parent: None }),
                }
            }
        }

        for (name, folder) in &folders {
            if top && (name == "scripts" || !folder.join("init.meta.json").is_file() || self.is_mounted(folder)) {
                continue;
            }

            if top && !self.wanted(name) {
                continue;
            }

            if let Some(entry) = self.folder(folder, name)? {
                entries.push(entry);
            }
        }

        if top {
            return Ok(entries);
        }

        let mut kept = Vec::new();

        for entry in entries {
            match entry.parent {
                Some(parent) => self.hoisted.push((parent, entry.node)),
                None => kept.push(Entry {
                    node: entry.node,
                    parent: None,
                }),
            }
        }

        Ok(kept)
    }

    fn folder(&mut self, path: &Path, name: &str) -> Result<Option<Entry>> {
        let init_meta = path.join("init.meta.json");
        let mut declared = Meta::default();

        if init_meta.exists() {
            self.files.push(init_meta.clone());
            let value = meta::read(&init_meta).with_context(|| self.relative(&init_meta))?;
            declared = meta::parse(&value, &self.relative(&init_meta));
        }

        if declared.ignore {
            return Ok(None);
        }

        let mut class_name = declared.class_name.clone().unwrap_or_else(|| "Folder".into());
        let mut properties = Map::new();
        let mut file_paths = Vec::new();

        for (candidate, script) in [
            ("init.server.luau", classify::Script::Server),
            ("init.server.lua", classify::Script::Server),
            ("init.client.luau", classify::Script::Client),
            ("init.client.lua", classify::Script::Client),
            ("init.luau", classify::Script::Module),
            ("init.lua", classify::Script::Module),
        ] {
            let file = path.join(candidate);

            if !file.exists() {
                continue;
            }

            self.files.push(file.clone());
            let relative = self.relative(&file);
            let raw = std::fs::read_to_string(&file).with_context(|| relative.clone())?;
            let source = self.transform.source(&relative, script.class_name(), raw)?;

            class_name = script.class_name().to_string();
            properties.insert("Source".into(), Value::String(source));
            file_paths.push(relative);
            break;
        }

        let mut node = Node::new("", name, class_name);
        node.properties = properties;
        node.file_paths = file_paths;

        if init_meta.exists() {
            node.file_paths.push(self.relative(&init_meta));
        }

        apply_declaration(&mut node, &declared);

        for entry in self.directory(path, false)? {
            attach(&mut node, entry.node);
        }

        Ok(Some(Entry {
            node,
            parent: declared.parent,
        }))
    }

    fn file(&mut self, path: &Path, kind: &Kind, stem: &str) -> Result<Vec<Node>> {
        let relative = self.relative(path);

        match kind {
            Kind::Script(script) => {
                let raw = std::fs::read_to_string(path).with_context(|| relative.clone())?;
                let source = self.transform.source(&relative, script.class_name(), raw)?;
                let mut node = Node::new("", stem, script.class_name());
                node.properties.insert("Source".into(), Value::String(source));
                node.file_paths.push(relative);
                Ok(vec![node])
            }
            Kind::Instance => {
                let value = meta::read(path).with_context(|| relative.clone())?;
                let declarations = meta::parse_many(&value, &relative);
                let mut nodes = Vec::new();

                for declared in declarations {
                    if declared.ignore || blank(&declared) {
                        continue;
                    }

                    if declared.from_model.is_some() {
                        self.reference(&declared, &relative);
                        continue;
                    }

                    let name = declared.name.clone().unwrap_or_else(|| stem.to_string());
                    let class_name = declared.class_name.clone().unwrap_or_else(|| "Folder".into());
                    let mut node = Node::new("", name, class_name);
                    node.file_paths.push(relative.clone());
                    apply_declaration(&mut node, &declared);

                    match &declared.parent {
                        Some(parent) => self.hoisted.push((parent.clone(), node)),
                        None => nodes.push(node),
                    }
                }

                Ok(nodes)
            }
            Kind::Asset(extension) => {
                let raw = std::fs::read_to_string(path).unwrap_or_default();

                if self.transform.claims(extension) {
                    if let Some(produced) = self.transform.file(&relative, extension, &raw)? {
                        let mut nodes = Vec::new();

                        for loaded in produced {
                            if loaded.skip {
                                continue;
                            }

                            let mut node = Node::new(
                                "",
                                loaded.name.clone().unwrap_or_else(|| stem.to_string()),
                                loaded.class_name.clone().unwrap_or_else(|| "StringValue".into()),
                            );

                            node.properties = loaded.properties;
                            node.attributes = loaded.attributes;
                            node.tags = loaded.tags;
                            node.children = loaded.children;

                            stamp(&mut node, &relative);

                            match loaded.parent {
                                Some(parent) => self.hoisted.push((parent, node)),
                                None => nodes.push(node),
                            }
                        }

                        return Ok(nodes);
                    }
                }

                let Some(class_name) = classify::asset_class(extension) else {
                    return Ok(Vec::new());
                };

                let mut node = Node::new("", stem, class_name);

                if class_name == "ModuleScript" {
                    let decoded: Value = serde_json::from_str(&raw).unwrap_or(Value::Null);
                    let body = format!("return {}\n", crate::literal::emit(&decoded));
                    node.properties.insert("Source".into(), Value::String(body));
                } else {
                    node.properties.insert("Value".into(), Value::String(raw));
                }

                node.file_paths.push(relative);
                Ok(vec![node])
            }
            _ => Ok(Vec::new()),
        }
    }

    fn reference(&mut self, declared: &Meta, relative: &str) {
        let target = declared.from_model.clone().unwrap_or_default();
        let parts = paths::split(&target);

        let Some((name, parent)) = parts.split_last() else {
            log::warn(format!("{relative}: $FromModel needs a path"));
            return;
        };

        let class_name = declared.class_name.clone().unwrap_or_else(|| "Model".into());
        let mut node = Node::new("", name.clone(), class_name);
        node.ownership = Ownership::Reference;
        node.file_paths.push(relative.to_string());
        apply_declaration(&mut node, declared);

        self.hoisted.push((paths::join(parent), node));
    }
}
