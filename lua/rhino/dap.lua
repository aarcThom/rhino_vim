-- Debug configurations for RhinoCommon / Grasshopper plug-ins (netcoredbg via nvim-dap)
local windows = require("rhino.windows")

local M = {}

-- Returns a processId function that builds, starts Rhino and returns its pid for netcoredbg to attach to
local function build_and_start(runscript)
  return function()
    local dap = require("dap")
    if not require("rhino.build").build() then
      return dap.ABORT
    end
    return require("rhino.launch").start(runscript) or dap.ABORT
  end
end

-- Runs inside nvim-dap's coroutine, so it can wait for vim.ui.select
local function pick_rhino()
  local dap = require("dap")
  local pids = windows.rhino_pids()
  if #pids <= 1 then
    if #pids == 0 then
      vim.notify("Rhino isn't running", vim.log.levels.WARN, { title = "Rhino" })
    end
    return pids[1] or dap.ABORT
  end
  local co = coroutine.running()
  vim.ui.select(pids, {
    prompt = "Rhino process",
    format_item = function(pid)
      return "Rhino.exe " .. pid
    end,
  }, function(pid)
    vim.schedule(function()
      coroutine.resume(co, pid or dap.ABORT)
    end)
  end)
  return coroutine.yield()
end

-- Configurations use their own `rhino` adapter: from WSL it's the Windows netcoredbg.exe,
-- while the Linux `netcoredbg` adapter stays available for Linux .NET apps
M.configurations = {
  launch = {
    type = "rhino",
    name = "Rhino: build & launch",
    request = "attach",
    processId = build_and_start(),
  },
  grasshopper = {
    type = "rhino",
    name = "Rhino: build & launch Grasshopper",
    request = "attach",
    processId = build_and_start("_Grasshopper"),
  },
  attach = {
    type = "rhino",
    name = "Rhino: attach to running Rhino",
    request = "attach",
    processId = pick_rhino,
  },
}

-- Path to the netcoredbg Rhino is debugged with
function M.netcoredbg()
  local exe = require("rhino").config.netcoredbg_exe
  if exe then
    return windows.local_path(exe)
  end
  if windows.wsl then
    -- A Windows Neovim's Mason install, else where the README's download puts it
    local mason =
      vim.fs.joinpath(windows.localappdata(), "nvim-data/mason/packages/netcoredbg/netcoredbg/netcoredbg.exe")
    local tools = windows.local_path("C:/tools/netcoredbg/netcoredbg.exe")
    return vim.fn.executable(mason) == 0 and vim.fn.executable(tools) == 1 and tools or mason
  end
  exe = vim.fn.exepath("netcoredbg")
  return exe ~= "" and exe or vim.fs.joinpath(vim.fn.stdpath("data"), "mason/bin/netcoredbg")
end

-- Adds the Rhino configurations to nvim-dap (safe to call more than once)
function M.setup()
  local dap = require("dap")
  -- Resolved when a session starts, so finding the Windows netcoredbg doesn't slow down startup
  dap.adapters.rhino = function(callback)
    callback({ type = "executable", command = M.netcoredbg(), args = { "--interpreter=vscode" } })
  end
  if not windows.wsl then
    -- `coreclr` is the adapter name used by the templates' .vscode/launch.json
    dap.adapters.coreclr = dap.adapters.coreclr or dap.adapters.netcoredbg or dap.adapters.rhino
  end

  dap.configurations.cs = dap.configurations.cs or {}
  for _, name in ipairs({ "launch", "grasshopper", "attach" }) do
    local config = M.configurations[name]
    local exists = vim.iter(dap.configurations.cs):any(function(c)
      return c.name == config.name
    end)
    if not exists then
      table.insert(dap.configurations.cs, config)
    end
  end
end

---@param name "launch"|"grasshopper"|"attach"
function M.run(name)
  M.setup()
  require("dap").run(M.configurations[name])
end

return M
