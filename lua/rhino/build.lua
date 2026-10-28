-- Finding the project and building it with `dotnet build`
local M = {}

-- Directory of the nearest .csproj above the current buffer
function M.project_root()
  return vim.fs.root(0, function(name)
    return name:match("%.csproj$") ~= nil
  end) or vim.fn.getcwd()
end

local function command()
  local config = require("rhino").config
  return vim.list_extend({ "dotnet", "build", "-c", config.configuration }, config.build_args)
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
  vim.notify("dotnet build…", vim.log.levels.INFO, { title = "Rhino" })
  local opts = { cwd = M.project_root(), text = true }
  if require("rhino.windows").wsl then
    -- Allows building the -windows target frameworks on Linux
    opts.env = { EnableWindowsTargeting = "true" }
  end
  if not on_done then
    return report(vim.system(command(), opts):wait())
  end
  vim.system(command(), opts, function(result)
    vim.schedule(function()
      on_done(report(result))
    end)
  end)
end

return M
