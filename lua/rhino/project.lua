-- Per-project overrides from a `.rhino.lua` file, for projects the default build and launch don't fit
-- (several plug-ins, a custom output layout, setup Rhino needs before it starts)
local M = {}

M.filename = ".rhino.lua"

---@class rhino.Project
---@field root string Folder containing the file; commands run here
---@field path string
---@field build? string[] Replaces `dotnet build` of the nearest .csproj
---@field launch? string[] Replaces starting Rhino; must print `pid=<Windows pid>` and exit
---@field output? string Build output folder (relative to `root`) for RHINO_PACKAGE_DIRS; replaces `bin/<configuration>` of the nearest .csproj

-- Nearest .rhino.lua above the current buffer, else above the working directory
function M.find()
  local paths = { vim.fn.getcwd() }
  -- Only file buffers: special ones (health://, terminals) have names that aren't paths
  local name = vim.api.nvim_buf_get_name(0)
  if vim.bo.buftype == "" and name ~= "" then
    table.insert(paths, 1, vim.fs.dirname(vim.fn.fnamemodify(name, ":p")))
  end
  for _, path in ipairs(paths) do
    local found = vim.fs.find(M.filename, { path = path, upward = true, type = "file" })[1]
    if found then
      return vim.fn.fnamemodify(found, ":p")
    end
  end
end

local function check_command(value, field, path)
  if value == nil then
    return true
  end
  if type(value) ~= "table" or #value == 0 or not vim.iter(value):all(function(v)
    return type(v) == "string"
  end) then
    return false, ("%s: `%s` must be a list of strings"):format(path, field)
  end
  return true
end

-- Loads the project file: nil when there's none, false (after saying why) when it isn't trusted or is
-- invalid. Callers stop on false rather than fall back to the defaults, which would build or load the
-- wrong thing. The file runs commands, so it goes through vim.secure.read: Neovim asks once whether to
-- trust it, and again whenever it changes.
---@return rhino.Project|false|nil
function M.load()
  local path = M.find()
  if not path then
    return nil
  end
  local source = vim.secure.read(path)
  if not source then
    vim.notify(path .. " isn't trusted. Allow it with :trust " .. path, vim.log.levels.ERROR, { title = "Rhino" })
    return false
  end
  local chunk, err = load(source, "@" .. path)
  local ok, project = false, err
  if chunk then
    ok, project = pcall(chunk)
  end
  if not ok or type(project) ~= "table" then
    local msg = ok and "must return a table" or project
    vim.notify(("%s: %s"):format(path, msg), vim.log.levels.ERROR, { title = "Rhino" })
    return false
  end
  for _, field in ipairs({ "build", "launch" }) do
    local valid, msg = check_command(project[field], field, path)
    if not valid then
      vim.notify(msg, vim.log.levels.ERROR, { title = "Rhino" })
      return false
    end
  end
  if project.output ~= nil and (type(project.output) ~= "string" or project.output == "") then
    vim.notify(("%s: `output` must be a folder path"):format(path), vim.log.levels.ERROR, { title = "Rhino" })
    return false
  end
  project.root = vim.fs.dirname(path)
  project.path = path
  return project
end

return M
