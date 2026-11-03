-- Debug configurations for RhinoCommon / Grasshopper plug-ins (netcoredbg via nvim-dap)
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
  local pids = require("rhino.launch").rhino_pids()
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

-- Configurations use their own `rhino` adapter, so they don't depend on how (or whether) lang.dotnet
-- has set up its `netcoredbg` one
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

-- Path to netcoredbg.exe: the configured one, else Mason's (the exe itself rather than Mason's .cmd shim,
-- so ending the session stops netcoredbg and not just a cmd.exe wrapper), else from PATH
function M.netcoredbg()
  local exe = require("rhino").config.netcoredbg_exe
  if exe then
    return exe
  end
  local mason = vim.fs.joinpath(vim.fn.stdpath("data"), "mason/packages/netcoredbg/netcoredbg/netcoredbg.exe")
  if vim.uv.fs_stat(mason) then
    return mason
  end
  return vim.fn.exepath("netcoredbg")
end

-- Adds the Rhino configurations to nvim-dap (safe to call more than once)
function M.setup()
  local dap = require("dap")
  -- Resolved when a session starts, so a netcoredbg Mason installs after startup is found
  dap.adapters.rhino = function(callback)
    callback({ type = "executable", command = M.netcoredbg(), args = { "--interpreter=vscode" } })
  end
  -- `coreclr` is the adapter name used by the templates' .vscode/launch.json
  dap.adapters.coreclr = dap.adapters.coreclr or dap.adapters.netcoredbg or dap.adapters.rhino

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
