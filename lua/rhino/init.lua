-- rhino.nvim: RhinoCommon / Grasshopper plug-in development in Neovim
local M = {}

---@class rhino.Config
M.defaults = {
  -- Path to Rhino.exe, a function returning one, or nil to use the newest of `rhino_versions`
  ---@type string|fun():string|nil
  rhino_exe = nil,
  -- Installed Rhino versions to look for, newest first
  rhino_versions = { 9, 8 },
  -- Rhino version passed to `dotnet new rhino/grasshopper --version`
  template_version = 8,
  -- Build configuration; Rhino loads plug-ins from bin/<configuration>
  configuration = "Debug",
  -- Extra arguments for `dotnet build`
  build_args = { "-clp:NoSummary" },
  -- Seconds to wait for Rhino to load .NET Core before giving up on attaching
  attach_timeout = 30,
  -- Seconds to wait for a .rhino.lua `launch` command to print Rhino's pid
  launch_timeout = 120,
  -- Path to netcoredbg.exe, or nil to use Mason's
  netcoredbg_exe = nil,
}

---@type rhino.Config
M.config = vim.deepcopy(M.defaults)

---@param opts? rhino.Config|{}
function M.setup(opts)
  M.config = vim.tbl_deep_extend("force", vim.deepcopy(M.defaults), opts or {})
end

return M
