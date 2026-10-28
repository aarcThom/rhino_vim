-- lazy.nvim specs for LazyVim: `{ "aarcThom/rhino_vim", import = "rhino.specs" }`
-- Builds on the lang.dotnet and dap.core extras, but swaps OmniSharp for the Roslyn
-- language server and adds Rhino commands and debug configurations.
return {
  {
    "aarcThom/rhino_vim",
    cmd = "Rhino",
    opts = {},
    keys = {
      { "<leader>Rb", "<cmd>Rhino build<cr>", desc = "Build" },
      { "<leader>Rl", "<cmd>Rhino launch<cr>", desc = "Build & Debug Rhino" },
      { "<leader>Rg", "<cmd>Rhino grasshopper<cr>", desc = "Build & Debug Grasshopper" },
      { "<leader>Ra", "<cmd>Rhino attach<cr>", desc = "Attach to Rhino" },
      { "<leader>Rn", "<cmd>Rhino new<cr>", desc = "New from Template" },
    },
  },
  {
    "folke/which-key.nvim",
    optional = true,
    opts = {
      spec = {
        { "<leader>R", group = "rhino", icon = { icon = "🦏", color = "grey" } },
      },
    },
  },

  -- Roslyn language server (the engine behind VS Code's C# extension)
  {
    "mason-org/mason.nvim",
    opts = {
      registries = {
        "github:mason-org/mason-registry",
        "github:Crashdummyy/mason-registry", -- provides the "roslyn" package
      },
      ensure_installed = { "roslyn", "netcoredbg" },
    },
  },
  {
    "seblyng/roslyn.nvim",
    ft = { "cs", "razor" },
    opts = {},
    init = function()
      if vim.fn.has("wsl") == 1 then
        -- Lets Roslyn's MSBuild load the -windows target frameworks on Linux
        vim.env.EnableWindowsTargeting = "true"
      end
    end,
  },
  {
    "neovim/nvim-lspconfig",
    opts = {
      servers = {
        omnisharp = { enabled = false },
      },
    },
  },

  -- Debugging with netcoredbg
  {
    "mfussenegger/nvim-dap",
    optional = true,
    opts = function()
      require("rhino.dap").setup()
    end,
  },
}
