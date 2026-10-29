-- Finding the project and building it with `dotnet build`
local M = {}

-- Directory of the nearest .csproj above the current buffer
function M.project_root()
  return vim.fs.root(0, function(name)
    return name:match("%.csproj$") ~= nil
  end) or vim.fn.getcwd()
end

-- Environment for MSBuild from WSL (dotnet build/restore and Roslyn), or nil natively.
-- MSBuild reads environment variables as properties.
function M.msbuild_env()
  if not require("rhino.windows").wsl then
    return nil
  end
  -- Allows building the -windows target frameworks on Linux
  local env = { EnableWindowsTargeting = "true" }
  -- Resolves references to Rhino's assemblies whose HintPath is a Windows path (see msbuild/rhino_vim.targets)
  local rhino = require("rhino.launch").find_rhino()
  local plugin = vim.fs.dirname(vim.fs.dirname(vim.fs.dirname(debug.getinfo(1, "S").source:sub(2))))
  local targets = vim.fs.joinpath(plugin, "msbuild", "rhino_vim.targets")
  -- Leave a CustomAfterMicrosoftCommonTargets the user set alone
  local custom = vim.env.CustomAfterMicrosoftCommonTargets
  if rhino and (not custom or custom == targets) then
    env.CustomAfterMicrosoftCommonTargets = targets
    env.RhinoVimSystemDir = vim.fs.dirname(rhino)
  end
  return env
end

-- The build command and its working directory: the project file's `build`, else `dotnet build` of the nearest .csproj
local function command(project)
  if project and project.build then
    return project.build, project.root
  end
  local config = require("rhino").config
  return vim.list_extend({ "dotnet", "build", "-c", config.configuration }, config.build_args), M.project_root()
end

-- MSBuild prints `C:\path\File.cs(12,5): error CS0103: ... [C:\path\Project.csproj]`
local function to_quickfix(output)
  local lines = vim.tbl_map(vim.trim, vim.split(output, "\n", { trimempty = true }))
  vim.fn.setqflist({}, " ", {
    title = "dotnet build",
    lines = lines,
    efm = "%f(%l\\,%c): %trror %m,%f(%l\\,%c): %tarning %m,%-G%.%#",
  })
end

local function report(result)
  if result.code == 0 then
    vim.notify("Build succeeded", vim.log.levels.INFO, { title = "Rhino" })
    return true
  end
  local output = result.stdout .. result.stderr
  to_quickfix(output)
  if #vim.fn.getqflist() > 0 then
    vim.notify("Build failed, see the quickfix list", vim.log.levels.ERROR, { title = "Rhino" })
    vim.cmd("botright copen")
  else
    vim.notify(output, vim.log.levels.ERROR, { title = "dotnet build failed" })
  end
  return false
end

-- Builds the current project. Blocks and returns true on success, or runs in the background
-- and calls `on_done(ok)` when one is given.
---@param on_done? fun(ok: boolean)
function M.build(on_done)
  local project = require("rhino.project").load()
  if project == false then
    if on_done then
      on_done(false)
    end
    return false
  end
  local cmd, cwd = command(project)
  local custom = project and project.build
  vim.notify(custom and "Building (.rhino.lua)…" or "dotnet build…", vim.log.levels.INFO, { title = "Rhino" })
  local opts = { cwd = cwd, text = true, env = M.msbuild_env() }
  if not on_done then
    return report(vim.system(cmd, opts):wait())
  end
  vim.system(cmd, opts, function(result)
    vim.schedule(function()
      on_done(report(result))
    end)
  end)
end

return M
