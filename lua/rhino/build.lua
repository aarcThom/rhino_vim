-- Finding the project and building it with `dotnet build`
local M = {}

-- Where the plug-in project picked for each working tree is remembered
M.state_file = vim.fs.joinpath(vim.fn.stdpath("state"), "rhino", "projects.json")

-- Directory of the nearest .csproj above the current buffer
function M.buffer_project()
  local dir = vim.fs.root(0, function(name)
    return name:match("%.csproj$") ~= nil
  end)
  return vim.fs.normalize(dir or vim.fn.getcwd())
end

-- The working tree: the git checkout of the buffer, else of the working directory, else the working directory
function M.tree_root()
  local dir = vim.fs.root(0, ".git") or vim.fs.root(vim.fn.getcwd(), ".git") or vim.fn.getcwd()
  return vim.fs.normalize(dir)
end

local skipped = { bin = true, obj = true, node_modules = true, packages = true }

-- A Rhino plug-in project sets TargetExt to .rhp/.gha, or makes one in a post-build step: then its bin folder has one
local function is_plugin(csproj)
  local file = io.open(csproj, "r")
  if file then
    local text = file:read("*a")
    file:close()
    if text:find("<TargetExt>%s*%.rhp") or text:find("<TargetExt>%s*%.gha") then
      return true
    end
  end
  local bin = vim.fs.joinpath(vim.fs.dirname(csproj), "bin")
  return #vim.fs.find(function(name)
    return name:match("%.rhp$") ~= nil or name:match("%.gha$") ~= nil
  end, { path = bin, limit = 1 }) > 0
end

-- Folders of the Rhino plug-in projects in the working tree, sorted
---@param root? string
---@return string[]
function M.plugin_projects(root)
  root = root or M.tree_root()
  local found = {}
  local walk = vim.fs.dir(root, {
    depth = 8,
    skip = function(dir)
      local name = vim.fs.basename(dir)
      return not (skipped[name] or name:sub(1, 1) == ".")
    end,
  })
  for name, type in walk do
    if type == "file" and name:match("%.csproj$") then
      local csproj = vim.fs.normalize(vim.fs.joinpath(root, name))
      if is_plugin(csproj) then
        table.insert(found, vim.fs.dirname(csproj))
      end
    end
  end
  table.sort(found)
  return found
end

local function read_choices()
  local file = io.open(M.state_file, "r")
  if not file then
    return {}
  end
  local ok, choices = pcall(vim.json.decode, file:read("*a"))
  file:close()
  return ok and type(choices) == "table" and choices or {}
end

local function save_choice(root, dir)
  local choices = read_choices()
  choices[root] = dir:sub(#root + 2)
  vim.fn.mkdir(vim.fs.dirname(M.state_file), "p")
  local file = assert(io.open(M.state_file, "w"))
  file:write(vim.json.encode(choices))
  file:close()
end

-- Asks which plug-in project of the working tree to build and launch, and remembers the answer
---@return string? dir
function M.pick_project()
  local root = M.tree_root()
  local plugins = M.plugin_projects(root)
  if #plugins == 0 then
    vim.notify("No Rhino plug-in project found under " .. root, vim.log.levels.WARN, { title = "Rhino" })
    return nil
  end
  local items = { "Rhino plug-in project to build and launch:" }
  for i, dir in ipairs(plugins) do
    table.insert(items, ("%d. %s"):format(i, dir:sub(#root + 2)))
  end
  local dir = plugins[vim.fn.inputlist(items)]
  if dir then
    save_choice(root, dir)
  end
  return dir
end

-- The project to build and launch. Not the buffer's own project: in a solution the buffer is often in a library,
-- and building that leaves Rhino loading an old plug-in. So it's the working tree's Rhino plug-in project: the only
-- one, else the one picked for this tree (asked once). Without any, the nearest .csproj above the buffer.
-- Returns nil when the user cancels the pick, or when `ask` is false and a pick is needed.
---@param opts? { ask?: boolean }
---@return string?
function M.project_root(opts)
  local root = M.tree_root()
  local plugins = M.plugin_projects(root)
  if #plugins == 0 then
    return M.buffer_project()
  end
  if #plugins == 1 then
    return plugins[1]
  end
  local saved = read_choices()[root]
  saved = saved and vim.fs.normalize(vim.fs.joinpath(root, saved))
  if saved and vim.tbl_contains(plugins, saved) then
    return saved
  end
  if opts and opts.ask == false then
    return nil
  end
  return M.pick_project()
end

-- The build command and its working directory: the project file's `build`, else `dotnet build` of the plug-in project
local function command(project)
  if project and project.build then
    return project.build, project.root
  end
  local dir = M.project_root()
  if not dir then
    return nil
  end
  local config = require("rhino").config
  return vim.list_extend({ "dotnet", "build", "-c", config.configuration }, config.build_args), dir
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
  if not cmd then
    if on_done then
      on_done(false)
    end
    return false
  end
  local custom = project and project.build
  vim.notify(custom and "Building (.rhino.lua)…" or "dotnet build…", vim.log.levels.INFO, { title = "Rhino" })
  local opts = { cwd = cwd, text = true }
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
