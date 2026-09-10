pub mod place;
pub mod sourcemap;
pub mod types;

use std::path::{Path, PathBuf};
use std::sync::Arc;

use anyhow::Result;

use crate::hooks::Hooks;
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

impl Build {
    pub fn open(root: &Path, manifest: &str) -> Result<Self> {
        let config = scan::config_from(root, manifest)?;
        let hooks = Arc::new(Hooks::load(root)?);

        if hooks.count() > 0 {
            log::info(format!(
                "loaded {} hook script{}",
                hooks.count(),
                if hooks.count() == 1 { "" } else { "s" }
            ));
        }

        let (tree, files) = scan::build_with(root, hooks.as_ref(), &config)?;

        let build = Build {
            root: root.to_path_buf(),
            manifest: manifest.to_string(),
            config,
            hooks,
            tree,
            files,
        };

        build.emit()?;

        Ok(build)
    }

    pub fn reload_hooks(&mut self) -> Result<()> {
        self.hooks = Arc::new(Hooks::load(&self.root)?);
        Ok(())
    }

    pub fn reload_config(&mut self) -> Result<()> {
        self.config = scan::config_from(&self.root, &self.manifest)?;
        Ok(())
    }

    pub fn rebuild(&mut self) -> Result<Patch> {
        let (tree, files) = scan::build_with(&self.root, self.hooks.as_ref(), &self.config)?;
        let changes = patch::diff(&self.tree, &tree);

        self.tree = tree;
        self.files = files;
        self.hooks.drain();
        self.emit()?;

        Ok(changes)
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
