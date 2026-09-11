pub mod place;
pub mod sourcemap;
pub mod types;

use std::path::{Path, PathBuf};
use std::sync::Arc;

use anyhow::Result;
use serde_json::json;

use crate::hooks::{Hooks, Setup};
use crate::ir::Tree;
use crate::log;
use crate::patch::{self, Patch};
use crate::project::scan::{self, Config};

pub struct Build {
    pub root: PathBuf,
    pub manifest: String,
    pub config: Config,
    pub hooks: Arc<Hooks>,
    pub tree: Tree,
    pub files: Vec<PathBuf>,
}

fn setup(root: &Path, manifest: &str, config: &Config) -> Setup {
    Setup {
        root: root.to_path_buf(),
        name: config.name.clone(),
        id: config.id.clone(),
        manifest: manifest.to_string(),
        scripts: config.scripts.clone(),
    }
}

impl Build {
    pub fn open(root: &Path, manifest: &str) -> Result<Self> {
        let config = scan::config_from(root, manifest)?;
        let hooks = Arc::new(Hooks::load(&setup(root, manifest, &config))?);

        if hooks.count() > 0 {
            log::info(format!(
                "loaded {} hook script{}",
                hooks.count(),
                if hooks.count() == 1 { "" } else { "s" }
            ));
        }

        let (mut tree, files) = scan::build_with(root, hooks.as_ref(), &config)?;
        hooks.tree(&mut tree)?;

        let build = Build {
            root: root.to_path_buf(),
            manifest: manifest.to_string(),
            config,
            hooks,
            tree,
            files,
        };

        build.emit()?;
        build.announce(true, None);

        Ok(build)
    }

    pub fn reload_hooks(&mut self) -> Result<()> {
        self.hooks = Arc::new(Hooks::load(&setup(&self.root, &self.manifest, &self.config))?);
        Ok(())
    }

    pub fn reload_config(&mut self) -> Result<()> {
        self.config = scan::config_from(&self.root, &self.manifest)?;
        self.reload_hooks()
    }

    pub fn rebuild(&mut self) -> Result<Patch> {
        let (mut tree, files) = scan::build_with(&self.root, self.hooks.as_ref(), &self.config)?;
        self.hooks.tree(&mut tree)?;

        let changes = patch::diff(&self.tree, &tree);

        self.tree = tree;
        self.files = files;
        self.hooks.drain();
        self.emit()?;
        self.announce(false, Some(&changes));

        Ok(changes)
    }

    fn announce(&self, initial: bool, changes: Option<&Patch>) {
        self.hooks.emit(
            "compile",
            &json!({
                "initial": initial,
                "instances": self.tree.root.descendants(),
                "scripts": self.tree.root.scripts(),
                "files": self.files.len(),
                "added": changes.map(Patch::added).unwrap_or(0),
                "updated": changes.map(Patch::updated).unwrap_or(0),
                "removed": changes.map(Patch::removed).unwrap_or(0),
            }),
        );
    }

    pub fn emit(&self) -> Result<()> {
        let rendered = sourcemap::render(&self.tree)?;
        let file = self.root.join("sourcemap.json");
        let current = std::fs::read_to_string(&file).unwrap_or_default();

        if current != rendered {
            std::fs::write(&file, &rendered)?;
        }

        types::generate(&self.root)?;

        Ok(())
    }

    pub fn snapshot(&self) -> Tree {
        patch::syncable(&self.tree)
    }

    pub fn stats(&self) -> String {
        format!(
            "{} instances, {} scripts",
            self.tree.root.descendants(),
            self.tree.root.scripts()
        )
    }
}
