-- rhino.nvim: RhinoCommon / Grasshopper plug-in development in Neovim
local M = {}

---@class rhino.Config
M.defaults = {
  -- Path to Rhino.exe (Windows or WSL path), a function returning one, or nil to use the newest of `rhino_versions`
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
  -- Path to netcoredbg, or nil to use Mason's. From WSL this must be the Windows netcoredbg.exe;
  -- the default is the one in the Windows Neovim's Mason (%LOCALAPPDATA%\nvim-data\mason)
  netcoredbg_exe = nil,
  -- WSL only: Windows folder the build output is copied to for Rhino to load, or nil for %LOCALAPPDATA%\Temp\rhino_vim
  wsl_stage_dir = nil,
}

---@type rhino.Config
M.config = vim.deepcopy(M.defaults)

---@param opts? rhino.Config|{}
function M.setup(opts)
  M.config = vim.tbl_deep_extend("force", vim.deepcopy(M.defaults), opts or {})
end

return M
