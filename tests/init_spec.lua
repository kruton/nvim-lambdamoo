local lambdamoo = require("lambdamoo")
local install = require("lambdamoo.install")

describe("lambdamoo.init", function()
  local original_install

  before_each(function()
    original_install = install.install
  end)

  after_each(function()
    install.install = original_install
  end)

  it("merges user options into config", function()
    lambdamoo.setup({
      lsp = {
        cmd = { "echo" },
      },
      connections = {
        {
          authority = "my-server",
          endpoint = "https://example.com/dav/",
        },
      },
    })

    assert.are.same({ "echo" }, lambdamoo.config.lsp.cmd)
    assert.are.equal(1, #lambdamoo.config.connections)
    assert.are.equal("my-server", lambdamoo.config.connections[1].authority)
  end)

  it("calls install() when lsp binary is not executable", function()
    local install_called = false
    install.install = function()
      install_called = true
    end

    lambdamoo.setup({
      lsp = {
        cmd = { "nonexistent-moo-lsp-binary" },
      },
    })

    assert.is_true(install_called)
  end)
end)
