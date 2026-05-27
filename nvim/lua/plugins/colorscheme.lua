return {
  {
    "catppuccin/nvim",
    name = "catppuccin",
    -- On remote (SSH) sessions, repaint Mocha's background to the "Berry" wine
    -- canvas while keeping every syntax/accent color, so code looks familiar but
    -- the editor clearly signals "remote". Local sessions stay stock Mocha.
    opts = vim.env.SSH_CONNECTION and {
      color_overrides = {
        mocha = { base = "#331824", mantle = "#2a1320", crust = "#1a0d13" },
      },
    } or {},
  },
  { "LazyVim/LazyVim", opts = { colorscheme = "catppuccin-mocha" } },
}
