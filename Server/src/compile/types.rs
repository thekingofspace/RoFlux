use std::path::Path;

use anyhow::Result;
use serde_json::{json, Map, Value};

use crate::log;

pub const DEFINITIONS: &str = r#"export type RoFluxFile = {
	path: string,
	name: string,
	stem: string,
	folder: string,
	extension: string,
	source: string,
	text: string,
	className: string,
}

export type RoFluxDeclaration = { [any]: any }

export type RoFluxResult = string | RoFluxDeclaration | { RoFluxDeclaration } | nil

export type RoFluxListener = (file: RoFluxFile) -> RoFluxResult

export type RoFluxNode = {
	id: string,
	name: string,
	className: string,
	ownership: "managed" | "passthrough" | "reference",
	properties: { [string]: any },
	attributes: { [string]: any },
	tags: { string },
	children: { RoFluxNode },
	filePaths: { string },
}

export type RoFluxCompile = {
	initial: boolean,
	instances: number,
	scripts: number,
	files: number,
	added: number,
	updated: number,
	removed: number,
}

export type RoFluxSync = {
	added: number,
	updated: number,
	removed: number,
	summary: string,
	lines: { string },
	clients: number,
}

export type RoFluxStat = { size: number, modified: number, isFile: boolean, isDirectory: boolean }

export type RoFluxExec = { ok: boolean, code: number, stdout: string, stderr: string }

export type RoFluxProject = { name: string, id: string, root: string, manifest: string }

declare roflux: {
	on: (event: string, callback: (...any) -> ...any) -> (),
	onRead: (callback: RoFluxListener) -> (),
	onTransfer: (callback: RoFluxListener) -> (),
	onAdded: (callback: (file: RoFluxFile) -> ()) -> (),
	onRemoved: (callback: (file: RoFluxFile) -> ()) -> (),
	onChanged: (callback: (file: RoFluxFile) -> ()) -> (),
	onCompile: (callback: (info: RoFluxCompile) -> ()) -> (),
	onSync: (callback: (info: RoFluxSync) -> ()) -> (),
	onTree: (callback: (root: RoFluxNode) -> RoFluxNode?) -> (),
	transpile: (extension: string, callback: RoFluxListener) -> (),
	defer: (callback: () -> ()) -> (),

	log: (...any) -> (),
	warn: (...any) -> (),
	error: (...any) -> (),
	inspect: (value: any) -> string,

	root: () -> string,
	read: (path: string) -> string?,
	exists: (path: string) -> boolean,
	isDirectory: (path: string) -> boolean,
	list: (path: string) -> { string },
	walk: (path: string) -> { string },

	fs: {
		root: () -> string,
		read: (path: string) -> string?,
		write: (path: string, text: string) -> boolean,
		append: (path: string, text: string) -> (),
		remove: (path: string) -> boolean,
		mkdir: (path: string) -> (),
		exists: (path: string) -> boolean,
		isFile: (path: string) -> boolean,
		isDirectory: (path: string) -> boolean,
		list: (path: string) -> { string },
		walk: (path: string) -> { string },
		glob: (pattern: string) -> { string },
		stat: (path: string) -> RoFluxStat?,
	},

	json: ((path: string) -> any) & {
		read: (path: string) -> any,
		decode: (text: string) -> any,
		encode: (value: any, pretty: boolean?) -> string,
	},

	toml: {
		read: (path: string) -> any,
		decode: (text: string) -> any,
		encode: (value: any) -> string,
	},

	base64: {
		encode: (text: string) -> string,
		decode: (text: string) -> string,
	},

	hash: (text: string, algorithm: string?) -> string,

	luau: {
		literal: (value: any) -> string,
		module: (value: any) -> string,
		quote: (text: string) -> string,
		isIdentifier: (name: string) -> boolean,
	},

	new: (className: string, fields: { [any]: any }?, children: { [any]: any }?) -> RoFluxDeclaration,

	types: {
		color: (r: number, g: number, b: number) -> { number },
		rgb: (r: number, g: number, b: number) -> { number },
		hex: (value: string) -> { number },
		hsv: (h: number, s: number, v: number) -> { number },
		vector3: (x: number?, y: number?, z: number?) -> { number },
		vector2: (x: number?, y: number?) -> { number },
		udim: (scale: number?, offset: number?) -> { number },
		udim2: (xScale: number?, xOffset: number?, yScale: number?, yOffset: number?) -> { number },
		fromScale: (x: number?, y: number?) -> { number },
		fromOffset: (x: number?, y: number?) -> { number },
		cframe: (x: number?, y: number?, z: number?, ...number) -> { number },
		rect: (minX: number?, minY: number?, maxX: number?, maxY: number?) -> { number },
		range: (min: number, max: number?) -> { number },
		numberSequence: (...any) -> any,
		colorSequence: (...any) -> any,
		font: (family: string, weight: string?, style: string?) -> { family: string, weight: string?, style: string? },
		typed: (name: string, value: any) -> { [string]: any },
	},

	text: {
		trim: (value: string) -> string,
		trimStart: (value: string) -> string,
		trimEnd: (value: string) -> string,
		startsWith: (value: string, prefix: string) -> boolean,
		endsWith: (value: string, suffix: string) -> boolean,
		replace: (value: string, find: string, with: string) -> string,
		split: (value: string, separator: string?) -> { string },
		lines: (value: string) -> { string },
		indent: (value: string, prefix: string?) -> string,
		words: (value: string) -> { string },
		pascal: (value: string) -> string,
		camel: (value: string) -> string,
		snake: (value: string) -> string,
		kebab: (value: string) -> string,
		title: (value: string) -> string,
		padStart: (value: string, width: number, fill: string?) -> string,
		padEnd: (value: string, width: number, fill: string?) -> string,
	},

	path: {
		normalize: (value: string) -> string,
		join: (...string) -> string,
		dirname: (value: string) -> string,
		basename: (value: string) -> string,
		extension: (value: string) -> string,
		stem: (value: string) -> string,
		withExtension: (value: string, extension: string) -> string,
	},

	tree: {
		node: (name: string, declaration: (string | RoFluxDeclaration)?) -> RoFluxNode,
		child: (node: RoFluxNode, name: string) -> RoFluxNode?,
		find: (root: RoFluxNode, path: string) -> RoFluxNode?,
		each: (root: RoFluxNode, visit: (node: RoFluxNode, path: string) -> ()) -> (),
		add: (parent: RoFluxNode, node: RoFluxNode) -> RoFluxNode,
		remove: (root: RoFluxNode, path: string) -> RoFluxNode?,
		ensure: (root: RoFluxNode, path: string) -> RoFluxNode,
	},

	env: (name: string) -> string?,
	platform: () -> string,
	version: () -> string,
	project: () -> RoFluxProject,
	config: (key: string?) -> any,
	exec: (program: string, args: { string }?, options: { cwd: string? }?) -> RoFluxExec,

	cache: {
		get: (key: string) -> any,
		set: (key: string, value: any) -> (),
		has: (key: string) -> boolean,
		delete: (key: string) -> boolean,
		clear: () -> (),
		keys: () -> { string },
	},
}
"#;

pub fn write_definitions(root: &Path, name: &str) -> Result<()> {
    let file = root.join(name);
    let current = std::fs::read_to_string(&file).unwrap_or_default();

    if current == DEFINITIONS {
        return Ok(());
    }

    std::fs::write(&file, DEFINITIONS)?;
    log::info(format!("wrote {name}"));

    Ok(())
}

fn relaxed(raw: &str) -> String {
    let mut marked: Vec<(char, bool)> = Vec::with_capacity(raw.len());
    let mut chars = raw.chars().peekable();
    let mut inside = false;
    let mut escaped = false;

    while let Some(value) = chars.next() {
        if inside {
            marked.push((value, true));

            if escaped {
                escaped = false;
            } else if value == '\\' {
                escaped = true;
            } else if value == '"' {
                inside = false;
            }

            continue;
        }

        match value {
            '"' => {
                inside = true;
                marked.push((value, true));
            }
            '/' if matches!(chars.peek(), Some('/')) => {
                for next in chars.by_ref() {
                    if next == '\n' {
                        marked.push(('\n', false));
                        break;
                    }
                }
            }
            '/' if matches!(chars.peek(), Some('*')) => {
                chars.next();
                let mut previous = '\0';

                for next in chars.by_ref() {
                    if previous == '*' && next == '/' {
                        break;
                    }
                    previous = next;
                }
            }
            _ => marked.push((value, false)),
        }
    }

    let mut out = String::with_capacity(marked.len());

    for (index, (value, quoted)) in marked.iter().enumerate() {
        if !quoted && *value == ',' {
            let trailing = marked[index + 1..]
                .iter()
                .find(|(next, inner)| *inner || !next.is_whitespace())
                .map(|(next, inner)| !*inner && (*next == '}' || *next == ']'))
                .unwrap_or(false);

            if trailing {
                continue;
            }
        }

        out.push(*value);
    }

    out
}

pub fn write_settings(root: &Path, definitions: &str) -> Result<()> {
    let folder = root.join(".vscode");
    let file = folder.join("settings.json");

    std::fs::create_dir_all(&folder)?;

    let existing = std::fs::read_to_string(&file).ok();

    let mut settings: Map<String, Value> = match &existing {
        Some(raw) if !raw.trim().is_empty() => match serde_json::from_str(relaxed(raw).as_str()) {
            Ok(parsed) => parsed,
            Err(error) => {
                log::warn(format!(
                    ".vscode/settings.json could not be read ({error}), leaving it alone"
                ));
                return Ok(());
            }
        },
        _ => Map::new(),
    };

    let before = settings.clone();

    let mut files = settings
        .get("luau-lsp.types.definitionFiles")
        .and_then(Value::as_object)
        .cloned()
        .unwrap_or_default();

    files.insert("RoFlux".into(), Value::String(definitions.into()));

    settings.insert("luau-lsp.types.definitionFiles".into(), Value::Object(files));
    settings.insert("luau-lsp.platform.type".into(), json!("roblox"));
    settings.insert("luau-lsp.sourcemap.enabled".into(), json!(true));
    settings.insert("luau-lsp.sourcemap.autogenerate".into(), json!(false));

    if settings == before {
        return Ok(());
    }

    let rendered = format!("{}\n", serde_json::to_string_pretty(&Value::Object(settings))?);
    std::fs::write(&file, rendered)?;
    log::info("wrote .vscode/settings.json");

    Ok(())
}

pub fn generate(root: &Path) -> Result<()> {
    let name = "types.d.luau";
    write_definitions(root, name)?;
    write_settings(root, name)?;
    Ok(())
}
