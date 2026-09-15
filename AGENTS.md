# AGENTS.md

## Project
Godot 4.7 / GDScript desktop tool ("Asama") that scans a directory of Lua files and reports global-variable accesses. No build system, package manager, or test suite exists.

## Running / verifying
- Open in the Godot 4.7 editor and run the main scene (F5). There is no CLI lint/typecheck/test command.
- Entry point: `scenes/main/main.tscn` (uid `uid://crsr6y6ju5ija`) backed by `scenes/main/main.gd`.
- GDScript uses tab indentation (match existing `.gd` files). `.editorconfig` pins UTF-8, `.gitattributes` pins LF.

## Lua parsing
- AST parsing comes from the vendored `addons/lua-gdextension` (gilzoide, v0.8.2): use `LuaParser`, `LuaAST`, `LuaASTNode`, `LuaASTQuery` (Tree-sitter based, see `addons/lua-gdextension/CHANGELOG.md` 0.6.0).
- `addons/lua-gdextension` and `addons/script-ide` are third-party editor addons; do not modify them for project work. `addons/lua-gdextension/MY_CHANGE` records a local tweak (icon 64->16) that is lost on addon upgrade.
- `_handle_identifier` only filters `self`/`const`/`nil`/`true`/`false`, so Lua stdlib identifiers (`print`, `pairs`, `table`, ...) are reported as globals by design.

## Test fixtures (`testscripts/`)
- Manual Lua fixtures (`dnd_*.lua`, generated `dnd_stress_globals.lua`, `dnd_stress_test_generator.lua`). Nothing in `.gd` references them; they exist to be loaded via the UI's Open dialog while testing.
- Guardrail (from `testscripts/dnd-readme-testscripts.txt`): never delete files/folders beginning with `dnd` or `.gdignore`. Any other file/folder there is fair game for CRUD.
- The empty `.gdignore` stops Godot from importing this folder as project assets.

## Godot MCP Toolkit
- `addons/godot_mcp_toolkit` (v1.0.0, third-party) is enabled in `project.godot` and registers the `MCPRuntimeServer` autoload; `.mcp.json` wires the `@npgamedev/godot-mcp-server` bridge via `npx` (Node.js 22+).
- Do not hand-edit `.mcp.json` or the autoload; use Project > Tools > MCP Toolkit. The `[mcp_toolkit] status` string in `project.godot` is stale and not authoritative.

## Gotchas
- Root `dump.txt` is the runtime AST debug target written via `res://dump.txt` from `main.gd` (`_dump`); it is overwritten every analysis run and can be very large (100k+ lines) — grep it, don't read it whole.
- `.uid`, `.import`, and `.godot/` are Godot-generated; never hand-edit. `.godot/` is gitignored.
- `project.godot` pins Windows rendering to `d3d12` + Forward Plus and physics to Jolt.
- Unused placeholders: `assets/textures/pyramid/`, the `SaveSingle`/`SaveAll` buttons, the `FileBlacklistEditor`/`GlobalBlacklistEditor` CodeEdits (bound to `@onready` vars but never read), and the empty `scenes/file_binder_button/` + `scenes/folder_binder_button/` dirs; none have working logic behind them.

## Architecture (`main.gd`)
- `find_global_variable_accesses()` is the core: parses Lua with `LuaParser`, walks the AST with a scope stack, and returns referenced globals (Chinese comments explain the AST cases). `_dump()` writes the AST to `dump.txt`.
- `_on_file_dialog_dir_selected()` recursively scans `root_path` via `_scan_dir()`, filling `globals_find_result[relative_path] = Array[String]` and building `file_tree`: folders via `_create_tree_folder_item` (their `TreeItem`s are indexed in `_tree_items_by_path`), files via `_create_tree_file_item` (relative path stored as item metadata).
- `_ready()` connects `file_tree.item_selected` to `_on_tree_item_selected()`, which reads the item's relative-path metadata and calls `_on_tree_file_item_pressed()` to rebuild the labels in `rbar_container`.
