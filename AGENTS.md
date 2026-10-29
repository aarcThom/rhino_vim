# Notes for contributors and coding agents

How rhino_vim is put together, the decisions behind it, and what's been verified. Read this before changing launching,
debugging or WSL support: most of the code exists because a simpler approach didn't work. README.md covers usage.

Keep this file current when you learn something durable about the system. This repo is public: no personal details,
machine-specific paths, or names of projects the plugin was used on.

## Layout

| File | Responsibility |
|---|---|
| `lua/rhino/specs.lua` | lazy.nvim specs for LazyVim (`import = "rhino.specs"`): Roslyn, Mason registry, keys, dap hook |
| `lua/rhino/init.lua` | Options (`setup()`), read lazily through `require("rhino").config` |
| `lua/rhino/build.lua` | Project root (nearest `.csproj`), `dotnet build`, MSBuild errors → quickfix |
| `lua/rhino/launch.lua` | Find Rhino.exe, stage output (WSL), start Rhino, wait for .NET Core |
| `lua/rhino/windows.lua` | Everything that talks to Windows, natively or from WSL |
| `lua/rhino/dap.lua` | `rhino` adapter and the three debug configurations |
| `lua/rhino/templates.lua` | `dotnet new` with Rhino.Templates |
| `lua/rhino/health.lua` | `:checkhealth rhino` |
| `plugin/rhino.lua` | The `:Rhino` command and its completion |
| `msbuild/rhino_vim.targets` | WSL: lets MSBuild find Rhino's assemblies when a project's HintPath is a Windows path |

## Launching and debugging Rhino

- **Spawn Rhino, then attach.** Don't use a netcoredbg `launch` request. netcoredbg re-quotes arguments, and Rhino only
  accepts `/runscript="_Grasshopper"` with the quotes intact. Natively, `vim.uv.spawn` with `verbatim = true` keeps them.
- **Wait for `coreclr.dll`** before attaching (`tasklist /m coreclr.dll /fi "PID eq <pid>"`). netcoredbg can't attach
  until the runtime is loaded, about a second after start.
- **`/netcore` is required.** netcoredbg can't debug the .NET Framework runtime.
- **`RHINO_PACKAGE_DIRS=<output>/bin/<configuration>`** makes Rhino load the freshly built `.rhp`/`.gha`. This is what
  the Rhino.Templates launch profiles do. `uv.spawn`'s `env` replaces the whole environment, so copy `environ()` first.
- **The `rhino` adapter is separate from LazyVim's `netcoredbg`.** From WSL it must be the Windows `netcoredbg.exe`,
  while `netcoredbg` stays the Linux build for Linux .NET programs. It's an adapter function, so finding the exe (which
  shells out to `cmd.exe` in WSL) happens at session start, not at Neovim startup.
- **Registering the configurations:** `rhino.dap.setup()` runs from the nvim-dap spec's `opts`, so nvim-dap can stay
  lazy-loaded. That spec is `optional = true`: nvim-dap has no `setup()`, and a non-optional spec without
  `dap.core`'s `config` would make lazy.nvim call one. `dap.run()` callers call `setup()` first; it's idempotent.
- **The `coreclr` alias** (what the templates' `.vscode/launch.json` uses) is only set natively; those entries can't work
  from WSL.

## WSL

Neovim, Roslyn and `dotnet build` run in Linux; Rhino and netcoredbg run on Windows.

- **The Windows PATH may not be shared into WSL** (`appendWindowsPath=false`). Call Windows tools by full path, as
  `windows.lua` does: `wslpath -u "C:\Windows\System32\..."`. Run them with cwd `C:\`, or `cmd.exe` warns about UNC
  working directories.
- **Pids:** spawning a Windows exe from WSL returns the pid of the WSL interop process, not the Windows pid netcoredbg
  needs. So Rhino is started with PowerShell `Start-Process -PassThru` and its `.Id` is read back. The script goes
  through `-EncodedCommand` (UTF-16LE base64) to avoid quoting problems through WSL interop and PowerShell's parser.
  `Start-Process -ArgumentList '<one string>'` passes that string to the process verbatim.
- **Environment:** variables set inside the PowerShell script (`$env:X = ...`) are inherited by the started process,
  so `WSLENV` isn't needed.
- **Staging:** the build output is copied to `%LOCALAPPDATA%\Temp\rhino_vim\<project>` so Rhino loads from a Windows
  drive rather than `\\wsl.localhost`. Nobody has tested whether Rhino loads plug-ins correctly from a UNC path; staging
  avoids the question. Clearing the stage fails while Rhino has the files open, which the user sees as "is Rhino still
  running?".
- **Breakpoints need no path mapping.** A Linux build writes `/home/...` source paths into the PDBs. netcoredbg on
  Windows upper-cases document paths and matches exactly (`ModulesSources::GetFullPathIndex`). Paths that don't start
  with a drive letter also go through a suffix-matching fallback (`ResolveRelativeSourceFileName`). Stack frames report
  the original-case path, so Neovim can open them.
- **MSBuild environment:** `build.msbuild_env()` is used for `dotnet build`, the health check's restore and Roslyn
  (set in `vim.env` from the roslyn.nvim spec's `config`, which runs on the first `.cs` file, not at startup).
  MSBuild reads environment variables as properties.
  - `EnableWindowsTargeting=true`: without it, the templates' `-windows` target frameworks fail on Linux (NETSDK1100).
    The `net48` target builds on Linux because the SDK pulls in the .NET Framework reference assemblies automatically.
  - `CustomAfterMicrosoftCommonTargets` → `msbuild/rhino_vim.targets`, with `RhinoVimSystemDir` set to the folder of
    Rhino.exe. Projects often reference Rhino's own assemblies (e.g. `Rhino.Runtime.Code`) by a `C:\Program Files\...`
    HintPath, which doesn't exist on Linux. The targets file appends the Rhino folder to `AssemblySearchPaths`, after
    `{HintPathFromItem}`, so a HintPath that exists still wins. `$(ReferencePath)` doesn't work for this: SDK-style
    projects leave it out of `AssemblySearchPaths`. A user-set `CustomAfterMicrosoftCommonTargets` is left alone.

## Roslyn

- Uses [roslyn.nvim](https://github.com/seblyng/roslyn.nvim) with the `roslyn` package from the Crashdummyy Mason
  registry. OmniSharp is disabled.
- The server runs as a **shared daemon** that outlives Neovim (15 min by default) and that new Neovims reconnect to. A
  daemon started before an SDK install or PATH change keeps the old environment. Symptom: `Error while loading
  ....csproj` with `hostfxr_resolve_sdk2` / "Requested SDK version" in `:LspLog`, and no completions from package
  references. Fix: `pkill -f Microsoft.CodeAnalysis.LanguageServer`. `:Roslyn restart` alone just reconnects.
- **A project that fails `dotnet restore` isn't loaded.** Its files fall back to a syntax-only workspace: parse errors
  still show, but hover, signature help and completion return nothing. The error is only in `:LspLog`
  (`Error while loading ....csproj`), so `:checkhealth rhino` restores the solutions (else projects) under the cwd to
  surface it. A NuGet package downgrade (NU1605, an error by default) is a common cause.
- **`global.json` pins** with `rollForward: latestFeature` don't accept an older feature band (10.0.1xx doesn't satisfy
  10.0.301). Some Linux distros only package the 1xx band. `:checkhealth rhino` runs `dotnet --version` in the project
  to catch this.

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

```bash
nvim --headless --clean -u NONE -l test.lua   # test.lua: vim.opt.rtp:prepend("."), require modules, assert
```

- Stub `package.loaded.dap = { adapters = {}, configurations = {} }` to test `rhino.dap.setup()`. Stub `vim.system` to
  feed fake MSBuild output to `build.lua`.
- To test the WSL → Windows start path without opening Rhino, call `windows.start()` on a hidden `cmd.exe /c echo ... >
  file` and check the echoed environment and arguments.
- In a LazyVim install, lazy.nvim loads its own clone (`~/.local/share/nvim/lazy/rhino_vim`), and its module cache
  wins over an `rtp:prepend` of the checkout. To run `:checkhealth rhino` against the checkout, use
  `nvim --headless --clean --cmd "set rtp^=<checkout>" "+checkhealth rhino" "+w! out.txt" +qa`.
- To test the spec, point lazy.nvim's `dev.path` at the checkout and use `{ "aarcThom/rhino_vim", dev = true, import =
  "rhino.specs" }`.

## Verification status

**Verified:**
- From WSL: Windows `netcoredbg.exe` runs over interop. The PowerShell start path returns the Windows pid, and the env
  var and `/runscript="..."` quoting arrive intact. Staging works.
- A Linux build of the Rhino 8 templates (`net7.0-windows`, `net7.0`, `net48`) succeeds.
- `:Rhino build`, `:Rhino new`, `:checkhealth rhino`.

**Not yet verified:**
- End to end: launching Rhino, netcoredbg attaching and stopping at a breakpoint, on either platform.
- Native Windows since the WSL refactor (it now uses the `rhino` adapter instead of LazyVim's `netcoredbg`).
- Rhino on macOS: not supported. Rhino.exe lookup, `tasklist` and `/netcore` are Windows-only.

## Conventions

- stylua: 2 spaces, 120 columns. Comments explain why, briefly; match the surrounding density.
- Use `vim.notify(..., { title = "Rhino" })` for user-facing messages.
- Commits: never include personal details, machine paths, or names of projects the plugin was used on.
