local install = require("lambdamoo.install")
local curl = require("plenary.curl")

describe("lambdamoo.install", function()
  local original_os_uname
  local original_notify
  local original_get

  before_each(function()
    original_os_uname = vim.loop.os_uname
    original_notify = vim.notify
    original_get = curl.get
  end)

  after_each(function()
    vim.loop.os_uname = original_os_uname
    vim.notify = original_notify
    curl.get = original_get
  end)

  it("notifies error on unsupported OS", function()
    vim.loop.os_uname = function()
      return { sysname = "Windows_NT", machine = "x86_64" }
    end

    local captured_msg = nil
    local captured_level = nil
    vim.notify = function(msg, level)
      captured_msg = msg
      captured_level = level
    end

    install.install()
    assert.are.equal("Unsupported OS for auto-install", captured_msg)
    assert.are.equal(vim.log.levels.ERROR, captured_level)
  end)

  it("handles GitHub API release fetch failure gracefully", function()
    vim.loop.os_uname = function()
      return { sysname = "Linux", machine = "x86_64" }
    end

    local captured_errors = {}
    vim.notify = function(msg, level)
      if level == vim.log.levels.ERROR then
        table.insert(captured_errors, msg)
      end
    end

    curl.get = function(_, _)
      return { status = 500, body = "Internal Server Error" }
    end

    install.install()
    assert.is_true(#captured_errors > 0)
    assert.are.equal("Failed to fetch release info", captured_errors[1])
  end)
end)
