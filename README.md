# rhino_vim

A [LazyVim](https://lazyvim.github.io) plugin for developing RhinoCommon / Grasshopper plug-ins: Roslyn language
server, `dotnet build` with errors in the quickfix list, Rhino.Templates project creation, and build, launch and debug
Rhino / Grasshopper with your plug-in loaded.

Works with Neovim running on Windows, or in WSL with Rhino launched and debugged on the Windows side.

## Requirements

- Neovim 0.11+ and LazyVim, on Windows or in WSL
- The [.NET SDK](https://dotnet.microsoft.com/download) where Neovim runs (`winget install Microsoft.DotNet.SDK.10` on
  Windows, your distro's `dotnet-sdk` package in WSL)
- Rhino 8 or newer on Windows, running in .NET Core mode (the default in Rhino 8)
- The LazyVim extras `lang.dotnet` and `dap.core` — enable them with `:LazyExtras`
- WSL only: the **Windows** build of netcoredbg. The plugin finds it in a Windows Neovim's Mason
  (`%LOCALAPPDATA%\nvim-data\mason`) or in `C:\tools\netcoredbg\`; anywhere else, set `netcoredbg_exe`

## Installation

### 1. Install Rhino (Windows)

Install Rhino 8 or newer on Windows. Leave it in .NET Core mode, the default in Rhino 8. To check, run `SetDotNetRuntime`
in Rhino; it should say `NETCore`.

### 2. Install Neovim and LazyVim

Where you'll edit code (Windows or WSL), install Neovim 0.11+ and LazyVim by following the
[LazyVim installation guide](https://lazyvim.github.io/installation). That guide also lists LazyVim's own requirements
(git, a C compiler, ripgrep, fd).

### 3. Install the .NET SDK

The SDK goes where Neovim runs. It provides `dotnet build`, the project templates and the runtime for the Roslyn
language server.

- **Windows:**

  ```powershell
  winget install Microsoft.DotNet.SDK.10
  ```

- **WSL:** use your distro's package (`sudo apt install dotnet-sdk-10.0` on Ubuntu, `sudo dnf install dotnet-sdk-10.0`
  on Fedora). If your distro doesn't package it, use Microsoft's install script:

  ```bash
  curl -sSL https://dot.net/v1/dotnet-install.sh | bash -s -- --channel 10.0
  echo 'export DOTNET_ROOT=$HOME/.dotnet; export PATH=$PATH:$DOTNET_ROOT:$DOTNET_ROOT/tools' >> ~/.bashrc
  ```

Check it with `dotnet --version` in a new terminal.

### 4. Enable the LazyVim extras

Open Neovim, run `:LazyExtras`, and enable these two with `x`:

- `lang.dotnet`: C# treesitter, the csharpier formatter and netcoredbg
- `dap.core`: the debugger UI and `<leader>d` keys

### 5. Add the plugin

Create `lua/plugins/rhino.lua` in your Neovim config (`~/.config/nvim` in WSL, `%LOCALAPPDATA%\nvim` on Windows):

```lua
return {
  { "aarcThom/rhino_vim", import = "rhino.specs" },
}
```

Restart Neovim. lazy.nvim installs the plugin, and Mason then installs the Roslyn language server and netcoredbg (see
progress in `:Mason`). `rhino.specs` adds [roslyn.nvim](https://github.com/seblyng/roslyn.nvim) with the
[Crashdummyy Mason registry](https://github.com/Crashdummyy/mason-registry) for the Roslyn package, disables OmniSharp,
and adds the Rhino debug configurations to nvim-dap.

### 6. Install the Rhino project templates

```vim
:Rhino install-templates
```

This runs `dotnet new install Rhino.Templates`.

### 7. WSL only: get the Windows netcoredbg

*Skip this step if Neovim runs on Windows.*

**Why:** netcoredbg is the debugger. It has to run on the same OS as the program it debugs, so when Rhino runs on
Windows it has to be `netcoredbg.exe`, the Windows build. The netcoredbg that Mason installed in step 5 is the Linux
build: it's fine for Linux .NET programs but can't attach to Rhino. The plugin runs `netcoredbg.exe` from WSL for you;
you only need to have it on the Windows drive.

**a. Check whether you already have it.** If you also use LazyVim on Windows with the `lang.dotnet` extra, its Mason
has already installed it. Run this in WSL:

```bash
ls /mnt/c/Users/*/AppData/Local/nvim-data/mason/packages/netcoredbg/netcoredbg/netcoredbg.exe
```

If that prints a path, you're done: the plugin looks there by default. Go to step 8.

**b. Otherwise, download it.** Run this in WSL; it puts the debugger in `C:\tools\netcoredbg\`:

```bash
mkdir -p /mnt/c/tools
curl -L -o /tmp/netcoredbg-win64.zip https://github.com/Samsung/netcoredbg/releases/latest/download/netcoredbg-win64.zip
unzip -o /tmp/netcoredbg-win64.zip -d /mnt/c/tools   # the zip contains a netcoredbg\ folder
ls /mnt/c/tools/netcoredbg/netcoredbg.exe            # should print the path
```

(Or by hand: download `netcoredbg-win64.zip` from
[netcoredbg releases](https://github.com/Samsung/netcoredbg/releases) and extract it to `C:\tools`.)

The plugin also looks in `C:\tools\netcoredbg\`, so there's nothing to configure. If Neovim was open, quit it and
start it again before step 8.

**c. Somewhere else?** If you put `netcoredbg.exe` in another folder, edit `~/.config/nvim/lua/plugins/rhino.lua` from
step 5 so it reads:

```lua
return {
  {
    "aarcThom/rhino_vim",
    import = "rhino.specs",
    opts = { netcoredbg_exe = "D:/somewhere/netcoredbg/netcoredbg.exe" },
  },
}
```

Either a Windows path (`D:/...`) or the WSL path (`/mnt/d/...`) works. Then quit Neovim and start it again: plugin
options are only read at startup, so a Neovim that was already open keeps looking in the default places and
`:checkhealth rhino` will report netcoredbg.exe as missing.

### 8. Check the setup

```vim
:checkhealth rhino
```

This checks Neovim, the platform (Windows / WSL), `dotnet`, the templates, Rhino.exe and netcoredbg, and tells you how
to fix anything missing. It also runs `dotnet restore` on the solutions (or projects) under the working directory: a
project that doesn't restore can't be loaded by Roslyn, so `K`, completion and go to definition stop working for it.

WSL: if netcoredbg.exe is reported missing even though step 7 put it in place, Neovim probably hasn't been restarted
since. Quit it, start it again and rerun the check.

### 9. Try it

```vim
:Rhino new grasshopper MyComponents   " creates ./MyComponents and :cd's into it
```

Open a `.cs` file (Roslyn starts after a few seconds), set a breakpoint with `<leader>db`, then press `<leader>Rg`.
Neovim builds the project, starts Rhino with Grasshopper and attaches the debugger. Place your component on the canvas
to hit the breakpoint.

## Options

Defaults shown:

```lua
return {
  { "aarcThom/rhino_vim", import = "rhino.specs" },
  {
    "aarcThom/rhino_vim",
    opts = {
      rhino_exe = nil, -- path to Rhino.exe, Windows or WSL style (or a function returning one); nil = newest of rhino_versions
      rhino_versions = { 9, 8 }, -- looked up in C:/Program Files/Rhino <n>/System/Rhino.exe
      template_version = 8, -- `dotnet new rhino/grasshopper --version`
      configuration = "Debug", -- build configuration; Rhino loads plug-ins from bin/<configuration>
      build_args = { "-clp:NoSummary" },
      attach_timeout = 30, -- seconds to wait for Rhino to load .NET Core
      launch_timeout = 120, -- seconds to wait for a .rhino.lua `launch` command to print Rhino's pid
      netcoredbg_exe = nil, -- nil = Mason's; from WSL, the Windows Neovim's Mason or C:/tools/netcoredbg
      wsl_stage_dir = nil, -- WSL: Windows folder for the build output; nil = %LOCALAPPDATA%\Temp\rhino_vim
    },
  },
}
```

## Usage

| Command | Key | What it does |
|---|---|---|
| `:Rhino new [template] [name]` | `<leader>Rn` | `dotnet new` from Rhino.Templates. `rhino` / `grasshopper` create a project in the working directory and `:cd` into it; `rhinocommand` / `ghcomponent` add to the current project |
| `:Rhino build` | `<leader>Rb` | `dotnet build` the nearest `.csproj`; errors and warnings go to the quickfix list |
| `:Rhino launch` | `<leader>Rl` | Build, start Rhino with your plug-in loaded and attach the debugger |
| `:Rhino grasshopper` | `<leader>Rg` | Same, and open Grasshopper so your `.gha` loads |
| `:Rhino attach` | `<leader>Ra` | Attach the debugger to an already running Rhino |

The debug configurations also appear in nvim-dap's picker (`<leader>dc`) as `Rhino: build & launch`,
`Rhino: build & launch Grasshopper` and `Rhino: attach to running Rhino`. Use these rather than the `Rhino 8 - netcore`
entries from the templates' `.vscode/launch.json` — those don't build first. Breakpoints and stepping use the usual
`dap.core` keys (`<leader>db`, `<leader>dc`, …); stopping the session (`<leader>dt`) closes Rhino.

Formatting (csharpier, `<leader>cf` and on save) comes from the `lang.dotnet` extra.

## How launching works

- Rhino is started with `/netcore` and `RHINO_PACKAGE_DIRS=<project>/bin/<configuration>`, which is how the
  Rhino.Templates launch profiles make Rhino load the plug-in you just built.
- Rhino is spawned by Neovim and netcoredbg then attaches to it, rather than using a netcoredbg `launch`: netcoredbg
  re-quotes arguments, and Rhino only accepts `/runscript="_Grasshopper"` with the quotes intact.
- netcoredbg can only attach once `coreclr.dll` is loaded, about a second after start, so code that runs in that first
  second isn't debuggable. Plug-ins and Grasshopper assemblies load after that.
- netcoredbg can't debug the `/netfx` runtime, so Rhino must run in .NET Core mode.
- The `coreclr` adapter is aliased to netcoredbg so the templates' own `launch.json` entries work too.
- The Roslyn server keeps running after Neovim exits (`--daemon`) and is reused by the next session.

### From WSL

Neovim, Roslyn and `dotnet build` run in Linux; Rhino and the debugger run on Windows.

- `EnableWindowsTargeting=true` is set for `dotnet build` and Roslyn, so the templates' `-windows` target frameworks
  build and load on Linux.
- References to Rhino's own assemblies by a Windows path (`<HintPath>C:\Program Files\Rhino 8\System\...`) are found
  in the Rhino folder through `/mnt/c`: the plugin adds that folder to MSBuild's assembly search paths, for both
  `dotnet build` and Roslyn. A HintPath that exists still takes precedence.
- After building, `bin/<configuration>` is copied to `%LOCALAPPDATA%\Temp\rhino_vim\<project>` and
  `RHINO_PACKAGE_DIRS` points there, so Rhino loads from a Windows drive rather than over `\\wsl.localhost`. Close
  Rhino before rebuilding: Rhino locks the copied files.
- Rhino is started through PowerShell's `Start-Process` (Windows tools are called by full path, so the Windows `PATH`
  doesn't need to be shared with WSL). This gives the Windows pid netcoredbg needs to attach to.
- The debug configurations use their own `rhino` adapter, the Windows `netcoredbg.exe` talking over stdio, so the
  `netcoredbg` adapter from `lang.dotnet` stays free for Linux .NET programs.
- Breakpoints work without any path mapping: the PDBs record the Linux source paths (`/home/...`), and netcoredbg
  matches the paths Neovim sends against them.
- The templates' `.vscode/launch.json` entries (`coreclr`) don't work from WSL; use the `Rhino:` configurations.

## Custom build and launch (`.rhino.lua`)

Some projects don't fit the default build and launch: a solution with several plug-ins, an output folder other than
`bin/<configuration>`, `.rhp` files made in a post-build step, or setup Rhino needs before it starts. For these, put a
`.rhino.lua` file at the project root. It replaces the build, the launch, or both, or just says where the build output
is; the debugger still attaches as usual.

```lua
-- .rhino.lua
return {
  -- Replaces `dotnet build` of the nearest .csproj. Errors still go to the quickfix list.
  -- `dotnet build` takes one project per call, so build several through a shell:
  build = { "bash", "-c", "dotnet build src/A/A.csproj -c Debug && dotnet build src/B/B.csproj -c Debug" },
  -- Where the default launch finds the build output (it loads it with RHINO_PACKAGE_DIRS), relative to this file.
  -- Replaces `bin/<configuration>` of the nearest .csproj, which depends on the buffer you're in.
  output = "src/bin/Debug",
  -- Replaces starting Rhino (`output` is then unused). The command must start Rhino (in .NET Core mode, /netcore) and print
  -- `pid=<Windows pid>`, then exit; Neovim attaches the debugger to that pid.
  launch = { "./scripts/start-rhino.sh" },
}
```

- `build` and `launch` are lists of strings, run from the folder containing `.rhino.lua`. The nearest `.rhino.lua` above the current
  buffer is used, else the one above the working directory.
- For `:Rhino grasshopper`, the launch command gets `RHINO_VIM_RUNSCRIPT=_Grasshopper` in its environment; pass it to
  Rhino as `/runscript="_Grasshopper"`.
- The launch command should exit as soon as it knows the pid: code that runs before the debugger attaches can't be
  debugged. It has `launch_timeout` seconds.
- The file runs commands, so Neovim asks whether to trust it the first time, and again whenever it changes (the same
  mechanism as `'exrc'`). If you answer no, `:Rhino build` and `:Rhino launch` stop rather than use the defaults; allow
  it later with `:trust .rhino.lua`. Running `:trust` in the file's own buffer hashes the buffer as it would be
  written: if an EditorConfig `end_of_line` changed its line endings on opening, the hash won't match the file on
  disk and the trust won't stick. Save the buffer first, or trust the file by path from another buffer.
- `:checkhealth rhino` shows which `.rhino.lua` applies.

## Troubleshooting

### Rhino frozen after quitting Neovim

If Neovim exits (or netcoredbg is killed) while the debugger is attached, Rhino is left with all its threads suspended
and stops responding. Stop the debug session first (`<leader>dt`), which closes Rhino, then quit Neovim. A Rhino that's
already frozen can only be ended from Task Manager.

### No RhinoCommon completions

Completions for RhinoCommon (and your own other classes) only appear once Roslyn has loaded the project; until then it
treats each file on its own. Open a `.cs` file, wait for the loading notification to finish, then check `:LspLog` for
`Error while loading ....csproj`. Common causes:

- **Missing SDK:** your `global.json` asks for an SDK you don't have (`:checkhealth rhino` reports this). Install that
  version. On Fedora, dnf only ships the 10.0.1xx SDKs, so use
  [dotnet-install.sh](https://learn.microsoft.com/dotnet/core/tools/dotnet-install-script) for a newer feature band.
- **Stale Roslyn daemon:** Roslyn keeps one shared server running for 15 minutes after Neovim exits, and the next Neovim
  reconnects to it. If that server started before you installed or changed an SDK, it keeps the old environment. Stop
  it, then reopen Neovim:

  ```bash
  pkill -f Microsoft.CodeAnalysis.LanguageServer
  ```

## Developing this plugin

Use lazy.nvim's dev mode to load your checkout instead of the GitHub copy. In `lua/config/lazy.lua`:

```lua
require("lazy").setup({
  -- ...
  dev = { path = "~/source/repos/aarcThom" }, -- folder containing rhino_vim
})
```

and in `lua/plugins/rhino.lua`:

```lua
return {
  { "aarcThom/rhino_vim", dev = true, import = "rhino.specs" },
}
```
