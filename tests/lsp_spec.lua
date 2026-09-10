local lsp = require("lambdamoo.lsp")
local webdav = require("lambdamoo.webdav")

describe("lambdamoo.lsp", function()
  before_each(function()
    lsp.setup()
  end)

  it("sets up LambdaMooLSP augroup and FileType autocmd", function()
    local autocmds = vim.api.nvim_get_autocmds({ group = "LambdaMooLSP", event = "FileType" })
    assert.is_true(#autocmds > 0)
    assert.are.equal("moo", autocmds[1].pattern)
  end)

  it("rewrites moo:// definitions using webdav.resolve_verb_definition", function()
    local original_resolve = webdav.resolve_verb_definition
    webdav.resolve_verb_definition = function(uri)
      return uri:gsub("object/123", "object/1")
    end

    -- Test definition resolution logic indirectly or through handler
    local handler = vim.lsp.handlers["textDocument/definition"]
    local original_default_handler = handler

    vim.lsp.handlers["textDocument/definition"] = function(_, result)
      return result
    end

    -- Trigger handler through the setup by obtaining the handler or calling definition_handler
    -- Let's inspect vim.lsp.start mock or autocmd callback
    local autocmds = vim.api.nvim_get_autocmds({ group = "LambdaMooLSP", event = "FileType" })
    local cb = autocmds[1].callback

    local original_lsp_start = vim.lsp.start
    local captured_start_opts = nil
    vim.lsp.start = function(opts)
      captured_start_opts = opts
      return 1
    end

    local original_attach = vim.lsp.buf_attach_client
    vim.lsp.buf_attach_client = function(_, _) end

    cb({ buf = 1 })

    assert.is_not_nil(captured_start_opts)
    assert.is_not_nil(captured_start_opts.handlers["textDocument/definition"])

    local def_handler = captured_start_opts.handlers["textDocument/definition"]

    -- Test single Location
    local loc = { uri = "moo://server/object/123/verb/look" }
    def_handler(nil, loc, {}, {})
    assert.are.equal("moo://server/object/1/verb/look", loc.uri)

    -- Test LocationLink (targetUri)
    local loc_link = { targetUri = "moo://server/object/123/verb/look" }
    def_handler(nil, loc_link, {}, {})
    assert.are.equal("moo://server/object/1/verb/look", loc_link.targetUri)

    -- Test list of Locations
    local loc_list = {
      { uri = "moo://server/object/123/verb/look" },
      { uri = "file:///tmp/other.moo" },
    }
    def_handler(nil, loc_list, {}, {})
    assert.are.equal("moo://server/object/1/verb/look", loc_list[1].uri)
    assert.are.equal("file:///tmp/other.moo", loc_list[2].uri)

    -- Restore
    vim.lsp.start = original_lsp_start
    vim.lsp.buf_attach_client = original_attach
    vim.lsp.handlers["textDocument/definition"] = original_default_handler
    webdav.resolve_verb_definition = original_resolve
  end)
end)
