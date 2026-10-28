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
- WSL only: the **Windows** build of netcoredbg. The default is the one from Mason in a Windows Neovim
  (`%LOCALAPPDATA%\nvim-data\mason`); otherwise download it from
  [netcoredbg releases](https://github.com/Samsung/netcoredbg/releases) and set `netcoredbg_exe`

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

Rhino runs on Windows, so the debugger attaching to it must be the Windows build of netcoredbg. Use one of these:

- **If you also use Neovim on Windows** with the `lang.dotnet` extra, its Mason already has netcoredbg in
  `%LOCALAPPDATA%\nvim-data\mason`. That's the default and needs no setup.
- **Otherwise,** download `netcoredbg-win64.zip` from [netcoredbg releases](https://github.com/Samsung/netcoredbg/releases),
  extract it (e.g. to `C:\tools\netcoredbg`) and point the plugin at it:

  ```lua
  return {
    { "aarcThom/rhino_vim", import = "rhino.specs" },
    { "aarcThom/rhino_vim", opts = { netcoredbg_exe = "C:/tools/netcoredbg/netcoredbg.exe" } },
  }
  ```

### 8. Check the setup

```vim
:checkhealth rhino
```

This checks Neovim, the platform (Windows / WSL), `dotnet`, the templates, Rhino.exe and netcoredbg, and tells you how
to fix anything missing.

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
      netcoredbg_exe = nil, -- nil = Mason's; from WSL, the Windows Neovim's Mason netcoredbg.exe
      wsl_stage_dir = nil, -- WSL: Windows folder for the build output; nil = %LOCALAPPDATA%\Temp\rhino_vim
    },
  },
}
```

## Usage

| Command | Key | What it does |
|---|---|---|
| `:Rhino new [template] [name]` | `<leader>Rn` | `dotnet new` from Rhino.Templates. `rhino` / `grasshopper` create a project in the working directory and `:cd` into it; `rhinocommand` / `grasshoppercomponent` add to the current project |
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
