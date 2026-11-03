-- Starting Rhino with the current project's plug-ins loaded
local M = {}

-- Configured or newest installed Rhino.exe, or nil
function M.find_rhino()
  local config = require("rhino").config
  local exe = config.rhino_exe
  if type(exe) == "function" then
    exe = exe()
  end
  if exe then
    return exe
  end
  for _, version in ipairs(config.rhino_versions) do
    local path = ("C:/Program Files/Rhino %d/System/Rhino.exe"):format(version)
    if vim.uv.fs_stat(path) then
      return path
    end
  end
end

local function rhino_exe()
  return M.find_rhino() or vim.fn.input("Path to Rhino.exe: ", "C:/Program Files/", "file")
end

local function tasklist(args)
  local cmd = vim.list_extend({ "tasklist" }, args)
  return vim.system(vim.list_extend(cmd, { "/fo", "csv", "/nh" }), { text = true }):wait().stdout or ""
end

-- Whether the process has loaded the .NET Core runtime
function M.has_coreclr(pid)
  return tasklist({ "/m", "coreclr.dll", "/fi", "PID eq " .. pid }):find('"' .. pid .. '"', 1, true) ~= nil
end

-- Pids of the running Rhino.exe processes
function M.rhino_pids()
  local pids = {}
  for pid in tasklist({ "/fi", "IMAGENAME eq Rhino.exe" }):gmatch('"Rhino%.exe","(%d+)"') do
    table.insert(pids, tonumber(pid))
  end
  return pids
end

-- Spawns Rhino with `env` added to Neovim's environment. `verbatim` keeps /runscript="..." quoted as given.
-- It also stops libuv quoting argv[0], and Rhino reads an unquoted "C:/Program Files/..." as a file to open
-- ("File type not supported ... Files/Rhino"). So Rhino is started by its bare file name from its own folder:
-- libuv looks the name up in `cwd` first, and argv[0] has no space left to split on.
local function spawn(exe, args, env)
  -- uv.spawn's `env` replaces the whole environment
  local env_list = {}
  for k, v in pairs(vim.fn.environ()) do
    table.insert(env_list, k .. "=" .. v)
  end
  for k, v in pairs(env) do
    table.insert(env_list, k .. "=" .. v)
  end

  local handle, pid
  local opts = { args = args, env = env_list, verbatim = true }
  if exe:find(" ", 1, true) then
    opts.cwd = vim.fs.dirname(exe)
    exe = vim.fs.basename(exe)
  end
  handle, pid = vim.uv.spawn(exe, opts, function()
    handle:close()
  end)
  if not handle then
    return nil, tostring(pid)
  end
  return pid
end

-- Runs the project file's `launch` command, which starts Rhino its own way and prints `pid=<pid>`.
-- It gets the Rhino command to run on start, if any, in RHINO_VIM_RUNSCRIPT.
local function start_project(project, runscript)
  local env = runscript and { RHINO_VIM_RUNSCRIPT = runscript } or nil
  local timeout = require("rhino").config.launch_timeout * 1000
  local result = vim.system(project.launch, { cwd = project.root, text = true, env = env }):wait(timeout)
  local output = (result.stdout or "") .. (result.stderr or "")
  local pid = (result.stdout or ""):match("pid=(%d+)")
  if result.code ~= 0 or not pid then
    local why = result.code == 124 and result.signal ~= 0 and "timed out" or ("exited with code %d"):format(result.code)
    return nil, ("%s (%s), expected pid=<pid>:\n%s"):format(table.concat(project.launch, " "), why, output)
  end
  return tonumber(pid)
end

-- Starts Rhino in .NET Core mode with RHINO_PACKAGE_DIRS pointing at the build output, so the
-- project's .rhp/.gha load (or through the .rhino.lua `launch` command), and returns its pid
-- once it can be attached to (nil on failure).
-- Rhino is started here rather than with a netcoredbg "launch" because netcoredbg re-quotes the
-- arguments, and Rhino only accepts /runscript="..." with the quotes intact.
---@param runscript? string Rhino command to run on start, e.g. "_Grasshopper"
---@return integer?
function M.start(runscript)
  local project = require("rhino.project").load()
  if project == false then
    return nil
  end

  local pid, err
  if project and project.launch then
    pid, err = start_project(project, runscript)
  else
    -- The project file's `output`, else bin/<configuration> of the nearest .csproj
    local output
    if project and project.output then
      output = vim.fs.normalize(vim.fs.joinpath(project.root, project.output))
    else
      output = vim.fs.joinpath(require("rhino.build").project_root(), "bin", require("rhino").config.configuration)
    end
    if not vim.uv.fs_stat(output) then
      local msg = "No build output at " .. output .. " (set `output` in " .. require("rhino.project").filename .. ")"
      vim.notify(msg, vim.log.levels.ERROR, { title = "Rhino" })
      return nil
    end

    local args = { "/netcore" }
    if runscript then
      table.insert(args, ('/runscript="%s"'):format(runscript))
    end
    -- Rhino loads .rhp/.gha files found under these folders (same as the Rhino.Templates launch profiles)
    pid, err = spawn(rhino_exe(), args, { RHINO_PACKAGE_DIRS = output })
  end
  if not pid then
    vim.notify("Could not start Rhino: " .. tostring(err), vim.log.levels.ERROR, { title = "Rhino" })
    return nil
  end

  -- netcoredbg can only attach once the .NET runtime is loaded (about a second after start)
  local timeout = require("rhino").config.attach_timeout * 1000
  if not vim.wait(timeout, function()
    return M.has_coreclr(pid)
  end, 250) then
    vim.notify("Rhino didn't load .NET Core — is it set to /netfx?", vim.log.levels.ERROR, { title = "Rhino" })
    return nil
  end
  return pid
end

return M
