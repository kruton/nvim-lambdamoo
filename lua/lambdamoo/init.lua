local M = {}

M.config = {
  lsp = {
    cmd = { "moo-lsp-rs" }, -- Command to start the LSP
    inlay_hints = true,
  },
  connections = {
    -- Example connection profile:
    -- {
    --   authority = "codepoint",
    --   endpoint = "https://codepoint.the-b.org/dav/",
    --   -- Credentials will be automatically read from ~/.netrc
    -- }
  },
}

function M.setup(opts)
  M.config = vim.tbl_deep_extend("force", M.config, opts or {})

  -- Check if moo-lsp-rs is executable, if not, try installing
  if vim.fn.executable(M.config.lsp.cmd[1]) == 0 then
    require("lambdamoo.install").install()
  end

  require("lambdamoo.vfs").setup()
  require("lambdamoo.lsp").setup()
end

return M
