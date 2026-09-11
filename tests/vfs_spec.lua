local vfs = require("lambdamoo.vfs")
local webdav = require("lambdamoo.webdav")

describe("lambdamoo.vfs", function()
  local original_read_file
  local original_write_file

  before_each(function()
    original_read_file = webdav.read_file
    original_write_file = webdav.write_file
    vfs.setup()
  end)

  after_each(function()
    webdav.read_file = original_read_file
    webdav.write_file = original_write_file
  end)

  it("reads content into buffer and configures buffer options on BufReadCmd", function()
    webdav.read_file = function(uri)
      if uri == "moo://test/sample" then
        return "line 1\r\nline 2\r\nline 3\n"
      end
      return nil, "Not found"
    end

    local buf = vim.fn.bufadd("moo://test/sample")
    vim.api.nvim_buf_call(buf, function()
      vim.cmd("doautocmd BufReadCmd moo://test/sample")
    end)

    local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
    assert.are.same({ "line 1", "line 2", "line 3" }, lines)
    assert.are.equal("acwrite", vim.bo[buf].buftype)
    assert.are.equal("moo", vim.bo[buf].filetype)
    assert.is_false(vim.bo[buf].modified)

    vim.api.nvim_buf_delete(buf, { force = true })
  end)

  it("writes buffer contents back to webdav on BufWriteCmd", function()
    local written_uri = nil
    local written_content = nil

    webdav.write_file = function(uri, content)
      written_uri = uri
      written_content = content
      return true
    end

    local buf = vim.api.nvim_create_buf(false, false)
    vim.api.nvim_buf_set_name(buf, "moo://test/sample_write")
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "code line 1", "code line 2" })
    vim.bo[buf].buftype = "acwrite"
    vim.bo[buf].modified = true

    vim.api.nvim_buf_call(buf, function()
      vim.cmd("doautocmd BufWriteCmd moo://test/sample_write")
    end)

    assert.are.equal("moo://test/sample_write", written_uri)
    assert.are.equal("code line 1\ncode line 2\n", written_content)
    assert.is_false(vim.bo[buf].modified)

    vim.api.nvim_buf_delete(buf, { force = true })
  end)

  it("handles buffer lifecycle for moo://codepoint/object/168/verb/test2", function()
    local saved_content = nil
    webdav.read_file = function(uri)
      if uri == "moo://codepoint/object/168/verb/test2" then
        return 'notify(player, "Hello from verb");\n'
      end
      return nil, "Not found"
    end

    webdav.write_file = function(uri, content)
      saved_content = content
      return true
    end

    local buf = vim.fn.bufadd("moo://codepoint/object/168/verb/test2")
    vim.api.nvim_buf_call(buf, function()
      vim.cmd("doautocmd BufReadCmd moo://codepoint/object/168/verb/test2")
    end)

    local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
    assert.are.same({ 'notify(player, "Hello from verb");' }, lines)
    assert.are.equal("moo", vim.bo[buf].filetype)
    assert.are.equal("acwrite", vim.bo[buf].buftype)

    -- Modify lines and trigger BufWriteCmd
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, { 'notify(player, "Updated verb");' })
    vim.bo[buf].modified = true

    vim.api.nvim_buf_call(buf, function()
      vim.cmd("doautocmd BufWriteCmd moo://codepoint/object/168/verb/test2")
    end)

    assert.are.equal('notify(player, "Updated verb");\n', saved_content)
    assert.is_false(vim.bo[buf].modified)

    vim.api.nvim_buf_delete(buf, { force = true })
  end)

  it("renders directory listing and sets nofile/moo_dir buffer options on directory BufReadCmd", function()
    local original_list_dir = webdav.list_dir
    webdav.list_dir = function(uri)
      if uri == "moo://waterpoint/" then
        return {
          { name = "object/", uri = "moo://waterpoint/object/" },
          { name = "owned/", uri = "moo://waterpoint/owned/" },
        }
      end
      return nil, "Not found"
    end

    local buf = vim.fn.bufadd("moo://waterpoint/")
    vim.api.nvim_buf_call(buf, function()
      vim.cmd("doautocmd BufReadCmd moo://waterpoint/")
    end)

    local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
    assert.are.same({ "object/", "owned/" }, lines)
    assert.are.equal("nofile", vim.bo[buf].buftype)
    assert.are.equal("moo_dir", vim.bo[buf].filetype)
    assert.is_false(vim.bo[buf].modifiable)

    webdav.list_dir = original_list_dir
    vim.api.nvim_buf_delete(buf, { force = true })
  end)

  it("rewrites owned verb URIs to canonical object URIs on BufReadCmd", function()
    local read_uri = nil
    webdav.read_file = function(uri)
      read_uri = uri
      return "player:tell();\n"
    end

    local buf = vim.fn.bufadd("moo://waterpoint/owned/525/verb/check_authorization")
    vim.api.nvim_buf_call(buf, function()
      vim.cmd("doautocmd BufReadCmd moo://waterpoint/owned/525/verb/check_authorization")
    end)

    assert.are.equal("moo://waterpoint/object/525/verb/check_authorization", vim.api.nvim_buf_get_name(buf))
    assert.are.equal("moo://waterpoint/object/525/verb/check_authorization", read_uri)
    vim.api.nvim_buf_delete(buf, { force = true })
  end)
end)
