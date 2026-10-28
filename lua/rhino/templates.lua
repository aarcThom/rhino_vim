-- New projects and items from the Rhino.Templates dotnet templates
local M = {}

-- Templates that create a project (and take --version), as opposed to items added to one
M.project_templates = { "rhino", "grasshopper" }
M.item_templates = { "rhinocommand", "grasshoppercomponent" }

function M.names()
  return vim.list_extend(vim.list_slice(M.project_templates), M.item_templates)
end

function M.install()
  vim.notify("Installing Rhino.Templates…", vim.log.levels.INFO, { title = "Rhino" })
  vim.system({ "dotnet", "new", "install", "Rhino.Templates" }, { text = true }, function(result)
    vim.schedule(function()
      if result.code == 0 then
        vim.notify("Rhino.Templates installed", vim.log.levels.INFO, { title = "Rhino" })
      else
        vim.notify(result.stdout .. result.stderr, vim.log.levels.ERROR, { title = "Installing Rhino.Templates failed" })
      end
    end)
  end)
end

local function create(template, name)
  local is_project = vim.tbl_contains(M.project_templates, template)
  local cmd = { "dotnet", "new", template, "-n", name }
  local cwd
  if is_project then
    vim.list_extend(cmd, { "--version", tostring(require("rhino").config.template_version) })
    cwd = vim.fn.getcwd()
  else
    -- Items go into the project the current buffer belongs to
    cwd = require("rhino.build").project_root()
  end

  local result = vim.system(cmd, { cwd = cwd, text = true }):wait()
  if result.code ~= 0 then
    vim.notify(result.stdout .. result.stderr, vim.log.levels.ERROR, { title = "dotnet new " .. template .. " failed" })
    return
  end

  if is_project then
    -- Roslyn finds the .csproj from the working directory
    local dir = vim.fs.joinpath(cwd, name)
    vim.cmd.cd(vim.fn.fnameescape(dir))
    vim.notify(("Created %s project in %s"):format(template, dir), vim.log.levels.INFO, { title = "Rhino" })
  else
    vim.notify(("Added %s %s to %s"):format(template, name, cwd), vim.log.levels.INFO, { title = "Rhino" })
  end
end

-- Creates a project or item from a Rhino template, asking for whatever isn't given
---@param template? string
---@param name? string
function M.new(template, name)
  if not template then
    vim.ui.select(M.names(), { prompt = "Rhino template" }, function(choice)
      if choice then
        M.new(choice, name)
      end
    end)
    return
  end
  if not name then
    vim.ui.input({ prompt = "Name: " }, function(input)
      if input and input ~= "" then
        create(template, input)
      end
    end)
    return
  end
  create(template, name)
end

return M
