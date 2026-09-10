local lambdamoo = require("lambdamoo")
local webdav = require("lambdamoo.webdav")
local curl = require("plenary.curl")

describe("lambdamoo.webdav", function()
  before_each(function()
    lambdamoo.config.connections = {
      {
        authority = "testserver",
        endpoint = "https://moo.example.com/dav",
      },
      {
        authority = "slashserver",
        endpoint = "https://moo.example.com/dav/",
      },
    }
    webdav.etags = {}
  end)

  describe("URI parsing and connection lookup", function()
    it("fails when URI is invalid", function()
      local content, err = webdav.read_file("invalid://not-moo/foo")
      assert.is_nil(content)
      assert.is_truthy(err:match("Invalid URI"))

      local success, write_err = webdav.write_file("invalid-uri", "data")
      assert.is_false(success)
      assert.is_truthy(write_err:match("Invalid URI"))
    end)

    it("fails when authority is not configured", function()
      local content, err = webdav.read_file("moo://unconfigured/foo")
      assert.is_nil(content)
      assert.is_truthy(err:match("No connection profile configured"))

      local success, write_err = webdav.write_file("moo://unconfigured/foo", "data")
      assert.is_false(success)
      assert.is_truthy(write_err:match("No connection profile configured"))
    end)
  end)

  describe("read_file", function()
    local original_get

    before_each(function()
      original_get = curl.get
    end)

    after_each(function()
      curl.get = original_get
    end)

    it("fetches content and records ETag on HTTP 200", function()
      local captured_url = nil
      local captured_opts = nil

      curl.get = function(url, opts)
        captured_url = url
        captured_opts = opts
        return {
          status = 200,
          headers = {
            "Content-Type: text/plain",
            'ETag: "v12345"',
          },
          body = "return 42;\n",
        }
      end

      local content, err = webdav.read_file("moo://testserver/object/123/verb/test")
      assert.is_nil(err)
      assert.are.equal("return 42;\n", content)
      assert.are.equal("https://moo.example.com/dav/object/123/verb/test", captured_url)
      assert.are.same({ "--netrc-optional" }, captured_opts.raw)
      assert.are.equal('"v12345"', webdav.etags["moo://testserver/object/123/verb/test"])
    end)

    it("normalizes endpoint URLs with or without trailing slash", function()
      local captured_url = nil
      curl.get = function(url, _)
        captured_url = url
        return { status = 200, headers = {}, body = "ok" }
      end

      webdav.read_file("moo://slashserver/bar")
      assert.are.equal("https://moo.example.com/dav/bar", captured_url)
    end)

    it("returns error on HTTP 404", function()
      curl.get = function(_, _)
        return {
          status = 404,
          headers = {},
          body = "Not found",
        }
      end

      local content, err = webdav.read_file("moo://testserver/missing")
      assert.is_nil(content)
      assert.is_truthy(err:match("HTTP 404"))
    end)
  end)

  describe("write_file", function()
    local original_put

    before_each(function()
      original_put = curl.put
    end)

    after_each(function()
      curl.put = original_put
    end)

    it("writes content and passes If-Match when ETag is present", function()
      webdav.etags["moo://testserver/object/123/verb/test"] = '"v12345"'

      local captured_opts = nil
      curl.put = function(url, opts)
        captured_opts = opts
        return {
          status = 204,
          headers = {
            'etag: "v12346"',
          },
          body = "",
        }
      end

      local success, err = webdav.write_file("moo://testserver/object/123/verb/test", "new code")
      assert.is_nil(err)
      assert.is_true(success)
      assert.are.equal('"v12345"', captured_opts.headers["If-Match"])
      assert.are.equal("new code", captured_opts.body)
      assert.are.equal('"v12346"', webdav.etags["moo://testserver/object/123/verb/test"])
    end)

    it("returns error on HTTP conflict (412 Precondition Failed)", function()
      curl.put = function(_, _)
        return {
          status = 412,
          headers = {},
          body = "Precondition failed",
        }
      end

      local success, err = webdav.write_file("moo://testserver/file", "data")
      assert.is_false(success)
      assert.is_truthy(err:match("HTTP 412"))
    end)
  end)

  describe("resolve_verb_definition", function()
    local original_read_file

    before_each(function()
      original_read_file = webdav.read_file
    end)

    after_each(function()
      webdav.read_file = original_read_file
    end)

    it("leaves non-verb URIs untouched", function()
      local uri = "moo://testserver/object/123/prop/name"
      assert.are.equal(uri, webdav.resolve_verb_definition(uri))
    end)

    it("resolves verb to ancestor object where it is defined", function()
      webdav.read_file = function(uri)
        if uri == "moo://testserver/object/123/resolve/verb/tell/defined-on" then
          return "#1"
        end
        return nil, "Not found"
      end

      local resolved = webdav.resolve_verb_definition("moo://testserver/object/123/verb/tell")
      assert.are.equal("moo://testserver/object/1/verb/tell", resolved)
    end)

    it("returns original URI if resolution fails or returns invalid target", function()
      webdav.read_file = function(_)
        return nil, "Not found"
      end

      local uri = "moo://testserver/object/123/verb/tell"
      assert.are.equal(uri, webdav.resolve_verb_definition(uri))
    end)

    it("resolves verb URLs formatted as moo://codepoint/object/168/verb/test2", function()
      lambdamoo.config.connections = {
        {
          authority = "codepoint",
          endpoint = "https://codepoint.the-b.org/dav/",
        },
      }

      webdav.read_file = function(uri)
        if uri == "moo://codepoint/object/168/resolve/verb/test2/defined-on" then
          return "#1"
        end
        return nil, "Not found"
      end

      local resolved = webdav.resolve_verb_definition("moo://codepoint/object/168/verb/test2")
      assert.are.equal("moo://codepoint/object/1/verb/test2", resolved)
    end)
  end)

  describe("codepoint connection handling", function()
    it("handles full read cycle for moo://codepoint/object/168/verb/test2", function()
      lambdamoo.config.connections = {
        {
          authority = "codepoint",
          endpoint = "https://codepoint.the-b.org/dav/",
        },
      }

      local requested_url = nil
      local original_get = curl.get
      curl.get = function(url, opts)
        requested_url = url
        return {
          status = 200,
          headers = { 'ETag: "tag-168-test2"' },
          body = 'player:tell("Hello world");\n',
        }
      end

      local content, err = webdav.read_file("moo://codepoint/object/168/verb/test2")
      curl.get = original_get

      assert.is_nil(err)
      assert.are.equal('player:tell("Hello world");\n', content)
      assert.are.equal("https://codepoint.the-b.org/dav/object/168/verb/test2", requested_url)
      assert.are.equal('"tag-168-test2"', webdav.etags["moo://codepoint/object/168/verb/test2"])
    end)
  end)
end)
