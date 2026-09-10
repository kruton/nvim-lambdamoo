local lambdamoo = require("lambdamoo")
local webdav = require("lambdamoo.webdav")

describe("LSP fixture #1:fixture_1", function()
  local original_read_file
  local original_write_file
  local webdav_requests

  before_each(function()
    original_read_file = webdav.read_file
    original_write_file = webdav.write_file
    webdav_requests = {}

    webdav.read_file = function(uri)
      table.insert(webdav_requests, uri)
      if uri == "moo://waterpoint/object/1/verb/fixture_1" then
        return table.concat({
          "",
          "{x} = args;",
          'index(x, ":");',
          "$you:say_action(x);",
          "",
        }, "\n")
      elseif uri:match("^moo://waterpoint/object/0/property/you/.*/defined%-on$") then
        return "#1\n"
      end
      return nil, "Not found: " .. uri
    end

    webdav.write_file = function(uri, content)
      return true
    end

    lambdamoo.setup({
      lsp = {
        inlay_hints = true,
      },
      connections = {
        {
          authority = "waterpoint",
          endpoint = "https://waterpoint.example.com/dav/",
        },
      },
    })
  end)

  after_each(function()
    webdav.read_file = original_read_file
    webdav.write_file = original_write_file
  end)

  it("loads fixture, enables inlay hints, and handles hover and definition requests", function()
    -- Only run full live LSP client test if moo-lsp-rs is executable in the environment
    if vim.fn.executable("moo-lsp-rs") == 0 then
      pending("moo-lsp-rs binary not available in environment")
      return
    end

    vim.cmd("edit moo://waterpoint/object/1/verb/fixture_1")
    local buf = vim.api.nvim_get_current_buf()

    -- Wait for LSP client to attach
    local attached = vim.wait(3000, function()
      return #vim.lsp.get_clients({ bufnr = buf, name = "moo-lsp-rs" }) > 0
    end, 50)
    assert.is_true(attached, "moo-lsp-rs client should attach to buffer")

    local client = vim.lsp.get_clients({ bufnr = buf, name = "moo-lsp-rs" })[1]
    assert.is_not_nil(client)

    local function lsp_request(method, params, cb)
      local ok = pcall(function()
        client:request(method, params, cb, buf)
      end)
      if not ok then
        client.request(method, params, cb, buf)
      end
    end

    -- 1. Inlay hints verification
    if vim.lsp.inlay_hint then
      local is_enabled = vim.lsp.inlay_hint.is_enabled({ bufnr = buf })
      assert.is_true(is_enabled, "Inlay hints should be enabled on the buffer")
    end

    -- Request inlay hints directly from the server for this document
    local line_count = vim.api.nvim_buf_line_count(buf)
    local hint_params = {
      textDocument = vim.lsp.util.make_text_document_params(buf),
      range = {
        start = { line = 0, character = 0 },
        ["end"] = { line = line_count, character = 0 },
      },
    }

    local hints = nil
    lsp_request("textDocument/inlayHint", hint_params, function(_err, result)
      hints = result or false
    end)

    vim.wait(3000, function()
      return hints ~= nil
    end, 50)
    assert.is_truthy(hints, "Server should return inlay hints for index() call")
    assert.is_true(#hints >= 2, "Expected at least 2 inlay hints for index(x, ':')")

    local labels = {}
    for _, hint in ipairs(hints) do
      local label_text = type(hint.label) == "string" and hint.label
        or (type(hint.label) == "table" and hint.label[1] and hint.label[1].value)
        or ""
      table.insert(labels, label_text)
    end
    assert.are.equal("str1:", labels[1])
    assert.are.equal("str2:", labels[2])

    -- 2. Pressing K over 'index' on line 3 (1-indexed line 3, 0-indexed line 2)
    local hover_res = nil
    lsp_request("textDocument/hover", {
      textDocument = vim.lsp.util.make_text_document_params(buf),
      position = { line = 2, character = 1 }, -- over 'index'
    }, function(_err, result)
      hover_res = result or false
    end)

    vim.wait(3000, function()
      return hover_res ~= nil
    end, 50)
    assert.is_truthy(hover_res, "Hover request over index should return information")
    local hover_text = hover_res.contents and hover_res.contents.value or ""
    assert.is_truthy(hover_text:match("index%(str1: STR, str2: STR"))

    -- 3. Pressing K over 'say_action' on line 4 (0-indexed line 3)
    -- When hover is requested on a custom verb, hover_handler falls back to definition
    -- resolution, which queries moo://waterpoint/object/0/property/you/*
    local hover_handler = client.handlers["textDocument/hover"]
    assert.is_not_nil(hover_handler, "Hover handler should be registered")

    local hover_fallback_rendered = false
    local original_default_hover = vim.lsp.handlers["textDocument/hover"]
    vim.lsp.handlers["textDocument/hover"] = function(err, result, ctx, config)
      if result and result.contents and result.contents.value then
        if result.contents.value:match("Defined on: moo://waterpoint/object/1/verb/say_action") then
          hover_fallback_rendered = true
        end
      end
    end

    hover_handler(nil, nil, {
      client_id = client.id,
      bufnr = buf,
      params = {
        textDocument = vim.lsp.util.make_text_document_params(buf),
        position = { line = 3, character = 6 },
      },
    }, {})

    vim.wait(3000, function()
      return hover_fallback_rendered
    end, 50)
    vim.lsp.handlers["textDocument/hover"] = original_default_hover
    assert.is_true(
      hover_fallback_rendered,
      "Pressing K over say_action should trigger definition lookup and display resolved target in hover"
    )

    -- Check that webdav requests were made for moo://waterpoint/object/0/property/you/*
    local matched_prop_request = false
    for _, uri in ipairs(webdav_requests) do
      if uri:match("^moo://waterpoint/object/0/property/you/") then
        matched_prop_request = true
        break
      end
    end
    assert.is_true(
      matched_prop_request,
      "Expected a request for moo://waterpoint/object/0/property/you/* but saw: " .. vim.inspect(webdav_requests)
    )

    -- 4. Verify definition_handler rewrites moo:// definition locations
    local def_handler = client.handlers["textDocument/definition"]
    assert.is_not_nil(def_handler, "Definition handler should be registered")

    local resolved_definition = nil
    local original_default_def = vim.lsp.handlers["textDocument/definition"]
    vim.lsp.handlers["textDocument/definition"] = function(err, result, ctx, config)
      resolved_definition = result
    end

    local raw_loc = {
      uri = "moo://waterpoint/object/0/property/you/object/verb/say_action",
      range = {
        start = { line = 0, character = 0 },
        ["end"] = { line = 0, character = 0 },
      },
    }
    def_handler(nil, raw_loc, { client_id = client.id, bufnr = buf }, {})
    vim.lsp.handlers["textDocument/definition"] = original_default_def

    local final_uri = (type(resolved_definition) == "table" and resolved_definition.uri) or ""
    assert.are.equal("moo://waterpoint/object/1/verb/say_action", final_uri)

    vim.api.nvim_buf_delete(buf, { force = true })
  end)
end)
