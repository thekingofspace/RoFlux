# RoFlux

One way syncing from your editor into Roblox Studio. Your files are the truth, Studio only ever
receives.

## Quick start

```
cargo build --release --manifest-path Server/Cargo.toml   # build the server
roflux plugin                                             # install the Studio plugin
roflux init MyGame                                        # set up a project
roflux serve MyGame                                       # start syncing
```

Then open Studio, click **RoFlux** on the toolbar, and press Connect.

## Commands

| Command | Does |
| --- | --- |
| `roflux serve [project]` | Watch and stream changes into Studio |
| `roflux compile [project]` | Compile once, refresh `sourcemap.json` |
| `roflux build [project] -o Game.rbxl` | Write a place or model file |
| `roflux plugin` | Install the Studio plugin |
| `roflux init [project]` | Scaffold a new project |

`[project]` is a project name and `.project.json` is added for you, so `roflux serve game` reads
`game.project.json`. With no name you get `default.project.json`.

## What a project looks like

```
MyGame/
├─ default.project.json   project info and service properties
├─ meta.inst.json         instances with no file of their own
├─ scripts/               compile time hooks
└─ Shared/
   ├─ init.meta.json      { "$Parent": "ReplicatedStorage" }
   └─ Greeting.luau       becomes a ModuleScript
```

Files become instances. `.luau` is a ModuleScript, `.server.luau` a Script, `.client.luau` a
LocalScript, and a folder with an `init.luau` becomes the script itself. Luau source is sent
across as text and never parsed or rewritten.

## Documentation

Full docs are in [`docs/`](docs/), servable with GitHub Pages.

| Page | Covers |
| --- | --- |
| [Getting started](docs/getting-started.html) | Install, connect, editor setup |
| [Project format](docs/project.html) | Files, directives, `meta.inst.json`, multiple places |
| [How syncing works](docs/syncing.html) | Ownership, deletion, playtests, transport |
| [Script system](docs/scripts.html) | Hooks, transpilers, reading files |
| [Value types](docs/types.html) | How to write Color3, enums, UDim2 and every other type |
| [CLI commands](docs/cli.html) | Every command and option |
| [Edge cases](docs/edge-cases.html) | The things that surprise people |

## Building releases

The **Build** workflow in Actions builds both platforms on demand. Run it from the Actions tab,
optionally giving it a version label, and it produces one artifact holding everything:

```
roflux-v0.1.0/
├─ roflux-linux-x86_64
├─ roflux-windows-x86_64.exe
└─ RoFlux.rbxm
```

Download that, then attach the files to a release.

## Layout

| Path | What it is |
| --- | --- |
| `Server/` | Rust server: scans, watches, serves the sync socket |
| `Plugin/` | The Studio plugin, compiled into the server binary |
| `docs/` | Documentation site |
| `TestProject/` | A sample project |
