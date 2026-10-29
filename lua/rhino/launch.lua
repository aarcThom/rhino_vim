-- Starting Rhino with the current project's plug-ins loaded, natively on Windows or from WSL
local windows = require("rhino.windows")

local M = {}

-- Configured or newest installed Rhino.exe as a local path, or nil
function M.find_rhino()
  local config = require("rhino").config
  local exe = config.rhino_exe
  if type(exe) == "function" then
    exe = exe()
  end
  if exe then
    return windows.local_path(exe)
  end
  for _, version in ipairs(config.rhino_versions) do
    local path = windows.local_path(("C:/Program Files/Rhino %d/System/Rhino.exe"):format(version))
    if vim.uv.fs_stat(path) then
      return path
    end
  end
end

local function rhino_exe()
  return M.find_rhino() or vim.fn.input("Path to Rhino.exe: ", windows.local_path("C:/Program Files/"), "file")
end

-- Folder the build output is copied to from WSL, so Rhino loads it from a Windows drive
-- rather than over \\wsl.localhost
function M.stage_dir(root)
  local dir = require("rhino").config.wsl_stage_dir
  if dir then
    return vim.fs.joinpath(windows.local_path(dir), vim.fs.basename(root))
  end
  return vim.fs.joinpath(windows.localappdata(), "Temp", "rhino_vim", vim.fs.basename(root))
end

-- Folder for RHINO_PACKAGE_DIRS (as a Windows path), or nil and an error. `output` is the build output;
-- `root` names the staging folder.
local function package_dir(root, output)
  if not vim.uv.fs_stat(output) then
    return nil, "No build output at " .. output .. " (set `output` in " .. require("rhino.project").filename .. ")"
  end
  if not windows.wsl then
    return output
  end
  local stage = M.stage_dir(root)
  if vim.uv.fs_stat(stage) and vim.fn.delete(stage, "rf") ~= 0 then
    return nil, "Could not clear " .. stage .. " — is Rhino still running?"
  end
  vim.fn.mkdir(stage, "p")
  local copy = vim.system({ "cp", "-r", output .. "/.", stage }, { text = true }):wait()
  if copy.code ~= 0 then
    return nil, copy.stderr
  end
  return windows.windows_path(stage)
end

-- Native Windows: spawn directly. `verbatim` keeps /runscript="..." quoted as given.
local function spawn(exe, args, env)
  local env_list = {}
  for k, v in pairs(vim.fn.environ()) do
    table.insert(env_list, k .. "=" .. v)
  end
  for k, v in pairs(env) do
    table.insert(env_list, k .. "=" .. v)
  end

  local handle, pid
  handle, pid = vim.uv.spawn(exe, { args = args, env = env_list, verbatim = true }, function()
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
-- project's .rhp/.gha load (or through the .rhino.lua `launch` command), and returns its (Windows) pid
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
    local root, output
    if project and project.output then
      root = project.root
      output = vim.fs.normalize(vim.fs.joinpath(root, project.output))
    else
      root = require("rhino.build").project_root()
      output = vim.fs.joinpath(root, "bin", require("rhino").config.configuration)
    end
    local dir
    dir, err = package_dir(root, output)
    if not dir then
      vim.notify(err, vim.log.levels.ERROR, { title = "Rhino" })
      return nil
    end
    -- Rhino loads .rhp/.gha files found under these folders (same as the Rhino.Templates launch profiles)
    local env = { RHINO_PACKAGE_DIRS = dir }

    local args = { "/netcore" }
    if runscript then
      table.insert(args, ('/runscript="%s"'):format(runscript))
    end

    if windows.wsl then
      pid, err = windows.start(windows.windows_path(rhino_exe()), table.concat(args, " "), env)
    else
      pid, err = spawn(rhino_exe(), args, env)
    end
  end
  if not pid then
    vim.notify("Could not start Rhino: " .. tostring(err), vim.log.levels.ERROR, { title = "Rhino" })
    return nil
  end

  -- netcoredbg can only attach once the .NET runtime is loaded (about a second after start)
  local timeout = require("rhino").config.attach_timeout * 1000
  if not vim.wait(timeout, function()
    return windows.has_coreclr(pid)
  end, 250) then
    vim.notify("Rhino didn't load .NET Core — is it set to /netfx?", vim.log.levels.ERROR, { title = "Rhino" })
    return nil
  end
  return pid
end

return M
