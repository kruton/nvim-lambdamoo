local lsp = require("lambdamoo.lsp")
local webdav = require("lambdamoo.webdav")

describe("lambdamoo.lsp", function()
  local original_start
  local original_attach

  before_each(function()
    original_start = vim.lsp.start
    original_attach = vim.lsp.buf_attach_client
    lsp.setup()
  end)

  after_each(function()
    vim.lsp.start = original_start
    vim.lsp.buf_attach_client = original_attach
  end)

  local function capture_options()
    local options
    vim.lsp.start = function(opts)
      options = opts
      return 1
    end
    vim.lsp.buf_attach_client = function() end
    local autocmds = vim.api.nvim_get_autocmds({ group = "LambdaMooLSP", event = "FileType" })
    autocmds[1].callback({ buf = 1 })
    return options
  end

  it("advertises and registers the remote document protocol", function()
    local options = capture_options()
    assert.are.equal(1, options.init_options.lambdamoo.remoteDocuments)
    assert.is_function(options.handlers["lambdamoo/readDocument"])
    assert.is_function(options.handlers["lambdamoo/canonicalizeDocument"])
    assert.is_nil(options.handlers["textDocument/definition"])
    assert.is_nil(options.handlers["textDocument/hover"])
  end)

  it("serves open buffer text before WebDAV content", function()
    local options = capture_options()
    local uri = "moo://waterpoint/object/18/verb/explode"
    local buf = vim.fn.bufadd(uri)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "return args;" })
    local result = options.handlers["lambdamoo/readDocument"](nil, { uri = uri })
    assert.are.equal("return args;", result.text)
    vim.api.nvim_buf_delete(buf, { force = true })
  end)

  it("fetches unopened remote documents through WebDAV", function()
    local options = capture_options()
    local original_read = webdav.read_file
    webdav.read_file = function(uri)
      assert.are.equal("moo://waterpoint/object/18/verb/explode", uri)
      return '"documentation";\n{x} = args;'
    end
    local result = options.handlers["lambdamoo/readDocument"](nil, { uri = "moo://waterpoint/object/18/verb/explode" })
    assert.is_truthy(result.text:match("documentation"))
    webdav.read_file = original_read
  end)
end)
