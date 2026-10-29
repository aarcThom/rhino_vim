-- :checkhealth rhino
local M = {}

local function check_executable(name, advice)
  if vim.fn.executable(name) == 1 then
    vim.health.ok(name .. " found")
    return true
  end
  vim.health.error(name .. " not found", advice)
  return false
end

function M.check()
  vim.health.start("rhino.nvim")

  if vim.fn.has("nvim-0.11") == 1 then
    vim.health.ok("Neovim 0.11+")
  else
    vim.health.error("Neovim 0.11+ is required (roslyn.nvim)")
  end

  local windows = require("rhino.windows")
  if windows.wsl then
    vim.health.ok("WSL: building in Linux, launching and debugging Rhino on Windows")
    vim.health.info("Build output is copied to " .. require("rhino.launch").stage_dir("<project>"))
  elseif vim.fn.has("win32") == 1 then
    vim.health.ok("Windows")
  else
    vim.health.warn("Launching and debugging Rhino only works on Windows or WSL")
  end

  if check_executable("dotnet", "Install the .NET SDK: winget install Microsoft.DotNet.SDK.10") then
    -- `dotnet --version` resolves the SDK the way builds and Roslyn do, honouring global.json
    local root = require("rhino.build").project_root()
    local sdk = vim.system({ "dotnet", "--version" }, { cwd = root, text = true }):wait()
    if sdk.code == 0 then
      vim.health.ok(("SDK %s for %s"):format(vim.trim(sdk.stdout), root))
    else
      vim.health.error(
        "No installed .NET SDK matches the global.json for " .. root,
        "Install the SDK version global.json asks for, then restart the Roslyn daemon (see the README)"
      )
    end

    local list = vim.system({ "dotnet", "new", "list", "rhino" }, { text = true }):wait()
    if (list.stdout or ""):find("Rhino3D Plug-In", 1, true) then
      vim.health.ok("Rhino.Templates installed")
    else
      vim.health.warn("Rhino.Templates not installed", "Run :Rhino install-templates")
    end
  end

  local rhino = require("rhino.launch").find_rhino()
  if rhino and vim.uv.fs_stat(rhino) then
    vim.health.ok("Rhino: " .. rhino)
  else
    vim.health.warn("Rhino.exe not found", "Set `rhino_exe` in the rhino.nvim options")
  end

  local ok, dap = pcall(require, "dap")
  if not ok then
    vim.health.warn("nvim-dap not installed; debugging is unavailable")
    return
  end
  local netcoredbg = require("rhino.dap").netcoredbg()
  if vim.fn.executable(netcoredbg) == 1 then
    vim.health.ok("netcoredbg: " .. netcoredbg)
  elseif windows.wsl then
    vim.health.error(
      "Windows netcoredbg.exe not found: " .. netcoredbg,
      "Extract netcoredbg-win64.zip to C:\\tools (see the README), or set `netcoredbg_exe`, then restart Neovim"
    )
  else
    vim.health.error("netcoredbg not found", "Run :MasonInstall netcoredbg")
  end
end

return M
