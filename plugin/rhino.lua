-- :Rhino {subcommand}
if vim.g.loaded_rhino then
  return
end
vim.g.loaded_rhino = true

local subcommands = {
  build = function()
    require("rhino.build").build(function() end)
  end,
  launch = function()
    require("rhino.dap").run("launch")
  end,
  grasshopper = function()
    require("rhino.dap").run("grasshopper")
  end,
  attach = function()
    require("rhino.dap").run("attach")
  end,
  new = function(args)
    require("rhino.templates").new(args[1], args[2])
  end,
  ["install-templates"] = function()
    require("rhino.templates").install()
  end,
}

vim.api.nvim_create_user_command("Rhino", function(cmd)
  local name = cmd.fargs[1]
  local run = subcommands[name]
  if not run then
    vim.notify("Unknown :Rhino subcommand: " .. tostring(name), vim.log.levels.ERROR, { title = "Rhino" })
    return
  end
  run(vim.list_slice(cmd.fargs, 2))
end, {
  nargs = "+",
  desc = "Rhino / Grasshopper development",
  complete = function(arglead, line)
    local args = vim.split(line, "%s+")
    local candidates
    if #args == 2 then
      candidates = vim.tbl_keys(subcommands)
      table.sort(candidates)
    elseif #args == 3 and args[2] == "new" then
      candidates = require("rhino.templates").names()
    else
      return {}
    end
    return vim.tbl_filter(function(c)
      return vim.startswith(c, arglead)
    end, candidates)
  end,
})
