return {
  { "catppuccin/nvim", name = "catppuccin" },
  {
    "LazyVim/LazyVim",
    opts = {
      -- Match the shell: remote (SSH) sessions use Macchiato, local uses Mocha.
      colorscheme = vim.env.SSH_CONNECTION and "catppuccin-macchiato" or "catppuccin-mocha",
    },
  },
}
