-- Talking to Windows, either natively or from WSL (where the Windows PATH may not be available)
local M = {}

M.wsl = vim.fn.has("wsl") == 1

local function is_windows_path(path)
  return path:match("^%a:[/\\]") ~= nil
end

-- A Windows path ("C:\x" or "C:/x") as this Neovim sees it
function M.local_path(path)
  if not (M.wsl and is_windows_path(path)) then
    return path
  end
  return vim.trim(vim.fn.system({ "wslpath", "-u", path }))
end

-- A path as Windows programs see it
function M.windows_path(path)
  if not M.wsl or is_windows_path(path) then
    return path
  end
  return vim.trim(vim.fn.system({ "wslpath", "-w", path }))
end

local function system32(exe)
  return M.wsl and M.local_path("C:\\Windows\\System32\\" .. exe) or exe
end

-- Runs a Windows program; from WSL it's started in C:\ so cmd.exe doesn't complain about UNC paths
local function run(cmd)
  return vim.system(cmd, { text = true, cwd = M.wsl and M.local_path("C:\\") or nil }):wait()
end

local localappdata
-- %LOCALAPPDATA% as a local path
function M.localappdata()
  if not M.wsl then
    return vim.env.LOCALAPPDATA
  end
  if not localappdata then
    local out = run({ system32("cmd.exe"), "/d", "/c", "echo %LOCALAPPDATA%" }).stdout or ""
    localappdata = M.local_path(vim.trim(out))
  end
  return localappdata
end

local function tasklist(args)
  local cmd = vim.list_extend({ system32("tasklist.exe") }, args)
  return run(vim.list_extend(cmd, { "/fo", "csv", "/nh" })).stdout or ""
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

local function ps_quote(s)
  return "'" .. s:gsub("'", "''") .. "'"
end

-- Starts a Windows program from WSL and returns its Windows pid (the pid of a process spawned
-- directly is the WSL-side one, which netcoredbg can't attach to). `args` is passed verbatim.
---@param exe string Windows path
---@param args string
---@param env table<string, string>
---@return integer?, string?
function M.start(exe, args, env)
  local script = { "$ProgressPreference = 'SilentlyContinue'" }
  for k, v in pairs(env) do
    table.insert(script, ("$env:%s = %s"):format(k, ps_quote(v)))
  end
  table.insert(script, ("(Start-Process -FilePath %s -ArgumentList %s -PassThru).Id"):format(ps_quote(exe), ps_quote(args)))
  -- -EncodedCommand sidesteps quoting through WSL interop and PowerShell's own parser
  local encoded = vim.base64.encode(vim.iconv(table.concat(script, "; "), "utf-8", "utf-16le"))
  local powershell = system32("WindowsPowerShell\\v1.0\\powershell.exe")
  local result = run({ powershell, "-NoProfile", "-NonInteractive", "-EncodedCommand", encoded })
  local pid = (result.stdout or ""):match("(%d+)%s*$")
  if not pid then
    return nil, (result.stdout or "") .. (result.stderr or "")
  end
  return tonumber(pid)
end

return M
