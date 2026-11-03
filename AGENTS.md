# Notes for contributors and coding agents

How rhino_vim is put together, the decisions behind it, and what's been verified. Read this before changing launching
or debugging: most of the code exists because a simpler approach didn't work. README.md covers usage.

Keep this file current when you learn something durable about the system. This repo is public: no personal details,
machine-specific paths, or names of projects the plugin was used on.

## Scope

Windows only. Neovim, `dotnet`, Roslyn, Rhino and netcoredbg all run natively. WSL support (building in Linux, launching
Rhino on Windows) existed until it was removed to keep the plugin simple; see the git history before `Remove WSL
support` if it's ever wanted again (staging the build output, PowerShell `Start-Process` for the Windows pid, MSBuild
`AssemblySearchPaths` for Windows HintPaths, `EnableWindowsTargeting`).

## Layout

| File | Responsibility |
|---|---|
| `lua/rhino/specs.lua` | lazy.nvim specs for LazyVim (`import = "rhino.specs"`): Roslyn, Mason registry, keys, dap hook |
| `lua/rhino/init.lua` | Options (`setup()`), read lazily through `require("rhino").config` |
| `lua/rhino/build.lua` | Project root (nearest `.csproj`), `dotnet build`, MSBuild errors → quickfix |
| `lua/rhino/launch.lua` | Find Rhino.exe, start Rhino, wait for .NET Core, list Rhino processes (`tasklist`) |
| `lua/rhino/project.lua` | `.rhino.lua`: per-project build and launch commands |
| `lua/rhino/dap.lua` | `rhino` adapter and the three debug configurations |
| `lua/rhino/templates.lua` | `dotnet new` with Rhino.Templates |
| `lua/rhino/health.lua` | `:checkhealth rhino` |
| `plugin/rhino.lua` | The `:Rhino` command and its completion |

## Launching and debugging Rhino

- **Spawn Rhino, then attach.** Don't use a netcoredbg `launch` request. netcoredbg re-quotes arguments, and Rhino only
  accepts `/runscript="_Grasshopper"` with the quotes intact. `vim.uv.spawn` with `verbatim = true` keeps them.
- **Wait for `coreclr.dll`** before attaching (`tasklist /m coreclr.dll /fi "PID eq <pid>"`). netcoredbg can't attach
  until the runtime is loaded, about a second after start.
- **`/netcore` is required.** netcoredbg can't debug the .NET Framework runtime.
- **`RHINO_PACKAGE_DIRS=<output>/bin/<configuration>`** makes Rhino load the freshly built `.rhp`/`.gha`. This is what
  the Rhino.Templates launch profiles do. `uv.spawn`'s `env` replaces the whole environment, so copy `environ()` first.
- **The `rhino` adapter** runs Mason's `netcoredbg.exe` directly (`mason/packages/netcoredbg/netcoredbg/`), not the
  `mason/bin/netcoredbg.cmd` shim, so ending a session stops netcoredbg itself. It's separate from LazyVim's
  `netcoredbg` adapter, which resolves `exepath("netcoredbg")` once when nvim-dap loads. It's an adapter function, so
  the exe is looked up at session start (a netcoredbg Mason installed after startup is found).
- **Registering the configurations:** `rhino.dap.setup()` runs from the nvim-dap spec's `opts`, so nvim-dap can stay
  lazy-loaded. That spec is `optional = true`: nvim-dap has no `setup()`, and a non-optional spec without
  `dap.core`'s `config` would make lazy.nvim call one. `dap.run()` callers call `setup()` first; it's idempotent.
- **The `coreclr` alias** is what the templates' `.vscode/launch.json` uses.
- After `terminate`, Rhino closes and nvim-dap reports netcoredbg `exited with 1`. That's netcoredbg losing its
  debuggee, not a failure.

## Project file (`.rhino.lua`)

- **Why:** the default build and launch assume one project whose `bin/<configuration>` holds the `.rhp`/`.gha`. Real
  plug-ins break that in project-specific ways (several plug-ins, platform folders such as `bin/x64/...`, `.rhp` made by
  a post-build step, a plug-in GUID already registered in `HKCU\...\Rhinoceros\<ver>\Plug-Ins`, which Rhino trusts
  over `RHINO_PACKAGE_DIRS`). Rather than handle each case, a project can replace the build and launch commands, and
  the plugin keeps the part that's generic: quickfix and attaching the debugger.
- **Lua, not TOML or JSON:** no parser to add, and commands can be built in code. It runs commands, so it's read with
  `vim.secure.read` (trust prompt, re-asked when the file changes).
- **An untrusted or invalid file stops** `build`/`start` (`project.load()` returns `false`) instead of falling back to
  the defaults, which would quietly build or load something else.
- **`output` without `launch`:** a project whose `.csproj` isn't at the root (say `src/`) builds fine through `build`,
  but the default launch looks for `bin/<configuration>` next to the nearest `.csproj` above the *buffer*, so a run
  from a buffer outside `src/` would point at a folder that doesn't exist. `output` pins it, relative to `.rhino.lua`.
- **Launch contract:** the command prints `pid=<pid>` and exits; `M.start` then waits for `coreclr.dll` like the
  default path. `RHINO_VIM_RUNSCRIPT` carries the `/runscript` command. `launch_timeout` bounds the wait
  (`vim.system():wait()` returns code 124 and a signal on timeout).

## Roslyn

- Uses [roslyn.nvim](https://github.com/seblyng/roslyn.nvim) with the `roslyn` package from the Crashdummyy Mason
  registry. OmniSharp is disabled.
- The server runs as a **shared daemon** that outlives Neovim (15 min by default) and that new Neovims reconnect to. A
  daemon started before an SDK install or PATH change keeps the old environment. Symptom: `Error while loading
  ....csproj` with `hostfxr_resolve_sdk2` / "Requested SDK version" in `:LspLog`, and no completions from package
  references. Fix: `Stop-Process -Name Microsoft.CodeAnalysis.LanguageServer`. `:Roslyn restart` alone just
  reconnects.
- **A project that fails `dotnet restore` isn't loaded.** Its files fall back to a syntax-only workspace: parse errors
  still show, but hover, signature help and completion return nothing. The error is only in `:LspLog`
  (`Error while loading ....csproj`), so `:checkhealth rhino` restores the solutions (else projects) under the cwd to
  surface it. A NuGet package downgrade (NU1605, an error by default) is a common cause.
- **`global.json` pins** with `rollForward: latestFeature` don't accept an older feature band (10.0.1xx doesn't satisfy
  10.0.301). `:checkhealth rhino` runs `dotnet --version` in the project to catch this.

## Other decisions

- **The plugin isn't lazy-loaded** (`lazy = false`). lazy.nvim keeps lazy plugins off the runtimepath, so
  `:checkhealth rhino` reported "No healthcheck found". Startup only sources `plugin/rhino.lua`.
- **Rhino.Templates short names:** projects are `rhino` and `grasshopper` (these take `--version`). Items are
  `rhinocommand` and `ghcomponent`, not `grasshoppercomponent`. Others exist (`gh2`, `gh2component`, `rhinotest`,
  `zooplugin`), check with `dotnet new list rhino`.
- **MSBuild output → quickfix** uses `efm` `%f(%l\,%c): %trror %m` / `%tarning`, with lines trimmed. `-clp:NoSummary`
  avoids every error being listed twice.

## Testing

There's no test suite; changes have been checked with headless scripts:

```powershell
nvim --headless --clean -u NONE -l test.lua   # test.lua: vim.opt.rtp:prepend("<checkout>"), require modules, assert
```

- Use absolute paths in `rtp`: a test that `:cd`s into a project loses a relative one.
- Stub `package.loaded.dap = { adapters = {}, configurations = {} }` to test `rhino.dap.setup()`. Stub `vim.system` to
  feed fake MSBuild output to `build.lua`.
- End to end without LazyVim: `nvim --headless --clean --cmd "set rtp^=<checkout>" --cmd "set rtp^=<lazy>/nvim-dap" -l
  e2e.lua`, where the script `:cd`s into a `dotnet new grasshopper` project, sets a breakpoint with
  `require("dap.breakpoints").set`, calls `require("rhino.dap").run("grasshopper")`, waits for `event_stopped`, then
  `dap.terminate()`. Keep Neovim alive (`vim.wait`) until Rhino has exited: killing netcoredbg while attached leaves
  Rhino with every thread suspended.
- In a LazyVim install, lazy.nvim loads its own clone (`%LOCALAPPDATA%\nvim-data\lazy\rhino_vim`), and its module
  cache wins over an `rtp:prepend` of the checkout. To run `:checkhealth rhino` against the checkout, use
  `nvim --headless --clean --cmd "set rtp^=<checkout>" "+checkhealth rhino" "+w! out.txt" +qa`.
- To test the spec, point lazy.nvim's `dev.path` at the checkout and use `{ "aarcThom/rhino_vim", dev = true, import =
  "rhino.specs" }`.

## Verification status

**Verified (native Windows, Rhino 8):**
- `:checkhealth rhino`.
- Default build & launch: `dotnet build`, Rhino started with `/netcore` and `RHINO_PACKAGE_DIRS`, netcoredbg attached,
  `terminate` closed Rhino.
- Grasshopper launch: `/runscript="_Grasshopper"` arrived intact, the `.gha` loaded from `bin/Debug`, and a breakpoint
  set before attaching (in the component's constructor) was hit at the right source path.
- Killing netcoredbg while attached (Neovim exiting mid-session) leaves Rhino with every thread suspended.

**Not yet verified:**
- `.rhino.lua` build and launch since the WSL removal (it was verified from WSL; the code path didn't change).
- `:Rhino attach` to an already running Rhino.
