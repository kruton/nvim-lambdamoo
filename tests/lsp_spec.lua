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

  describe("parse_verb_header", function()
    it("parses comments and args assignment from verb code", function()
      local content = table.concat({
        ' " $string_utils:explode(subject [, delim])";',
        '" Return a list of those substrings of subject separated by runs of delim[1].";',
        '" delim defaults to space.";',
        '{subject, ?delim = " "} = args;',
        "if (!delim)",
        "  return this:char_list(subject);",
        "endif",
      }, "\n")

      local parsed = lsp.parse_verb_header(content)
      assert.are.equal('{subject, ?delim = " "} = args;', parsed.args)
      assert.are.same({
        "$string_utils:explode(subject [, delim])",
        "Return a list of those substrings of subject separated by runs of delim[1].",
        "delim defaults to space.",
      }, parsed.comments)
    end)

    it("parses args assignment when no comments are present", function()
      local content = table.concat({
        '{text, len, ?fill = " "} = args;',
        "abslen = abs(len);",
        "out = tostr(text);",
      }, "\n")

      local parsed = lsp.parse_verb_header(content)
      assert.are.equal('{text, len, ?fill = " "} = args;', parsed.args)
      assert.are.same({}, parsed.comments)
    end)

    it("parses comments when no args assignment is present", function()
      local content = table.concat({
        '" Just a descriptive comment line ";',
        "player:tell();",
      }, "\n")

      local parsed = lsp.parse_verb_header(content)
      assert.is_nil(parsed.args)
      assert.are.same({ "Just a descriptive comment line" }, parsed.comments)
    end)

    it("handles escaped quotes and backslashes in comments", function()
      local content = table.concat({
        '" Syntax: \\"foo\\" \\\\ bar ";',
        "{x} = args",
      }, "\n")

      local parsed = lsp.parse_verb_header(content)
      assert.are.same({ 'Syntax: "foo" \\ bar' }, parsed.comments)
      assert.are.equal("{x} = args;", parsed.args)
    end)

    it("returns empty comments and nil args on empty content", function()
      local parsed = lsp.parse_verb_header("")
      assert.are.same({}, parsed.comments)
      assert.is_nil(parsed.args)
    end)
  end)

  describe("format_hover_markdown", function()
    it("formats full markdown with args, comments, and target URI", function()
      local header = {
        args = '{subject, ?delim = " "} = args;',
        comments = {
          "$string_utils:explode(subject [, delim])",
          "delim defaults to space.",
        },
      }
      local md = lsp.format_hover_markdown("moo://waterpoint/object/18/verb/explode", header)
      assert.is_truthy(md:match('```moo\n{subject, %?delim = " "} = args;\n```'))
      assert.is_truthy(md:match("%$string_utils:explode%(subject %[, delim%]%)\ndelim defaults to space%."))
      assert.is_truthy(md:match("```moo\nDefined on: moo://waterpoint/object/18/verb/explode\n```"))
    end)

    it("formats markdown with URI only when header is empty", function()
      local md = lsp.format_hover_markdown("moo://waterpoint/object/18/verb/explode", { comments = {} })
      assert.are.equal("```moo\nDefined on: moo://waterpoint/object/18/verb/explode\n```", md)
    end)
  end)

  describe("hover_handler", function()
    it("fetches verb content and populates comments and args in hover result", function()
      local original_read_file = webdav.read_file
      webdav.read_file = function(uri)
        if uri == "moo://waterpoint/object/18/verb/explode" then
          return table.concat({
            ' " $string_utils:explode(subject [, delim])";',
            '{subject, ?delim = " "} = args;',
            "return {};",
          }, "\n")
        end
        return nil, "Not found"
      end

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
      local h_handler = captured_start_opts.handlers["textDocument/hover"]

      -- Mock client
      local original_get_client = vim.lsp.get_client_by_id
      local mock_client = {
        request = function(_, method, _, handler, _)
          if method == "textDocument/definition" then
            handler(nil, { uri = "moo://waterpoint/object/18/verb/explode" })
          end
        end,
      }
      vim.lsp.get_client_by_id = function()
        return mock_client
      end

      local rendered_hover = nil
      local original_default_hover = vim.lsp.handlers["textDocument/hover"]
      vim.lsp.handlers["textDocument/hover"] = function(_, result)
        rendered_hover = result
      end

      h_handler(nil, nil, { client_id = 1, bufnr = 1 }, {})

      assert.is_not_nil(rendered_hover)
      local val = rendered_hover.contents.value
      assert.is_truthy(val:match('{subject, %?delim = " "} = args;'))
      assert.is_truthy(val:match("%$string_utils:explode"))
      assert.is_truthy(val:match("Defined on: moo://waterpoint/object/18/verb/explode"))

      -- Restore
      vim.lsp.start = original_lsp_start
      vim.lsp.buf_attach_client = original_attach
      vim.lsp.get_client_by_id = original_get_client
      vim.lsp.handlers["textDocument/hover"] = original_default_hover
      webdav.read_file = original_read_file
    end)
  end)
end)
