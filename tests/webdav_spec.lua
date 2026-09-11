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

  describe("list_dir", function()
    it("returns error on invalid URI or unconfigured authority", function()
      local res, err = webdav.list_dir("invalid://uri")
      assert.is_nil(res)
      assert.truthy(err:match("Invalid URI"))

      local res2, err2 = webdav.list_dir("moo://unconfigured/")
      assert.is_nil(res2)
      assert.truthy(err2:match("No connection profile configured"))
    end)

    it("parses PROPFIND XML response and filters out root collection", function()
      lambdamoo.config.connections = {
        {
          authority = "testserver",
          endpoint = "https://example.com/dav/",
        },
      }

      local original_request = curl.request
      curl.request = function(opts)
        assert.are.equal("PROPFIND", opts.method)
        assert.are.equal("https://example.com/dav/", opts.url)
        assert.are.equal("1", opts.headers["Depth"])
        return {
          status = 207,
          body = [[<?xml version="1.0" encoding="utf-8"?>
<D:multistatus xmlns:D="DAV:" xmlns:M="urn:moo:webdav">
  <D:response>
    <D:href>/dav/</D:href>
    <D:propstat><D:prop><D:resourcetype><D:collection/></D:resourcetype></D:prop></D:propstat>
  </D:response>
  <D:response>
    <D:href>/dav/object/</D:href>
    <D:propstat><D:prop><D:resourcetype><D:collection/></D:resourcetype></D:prop></D:propstat>
  </D:response>
  <D:response>
    <D:href>/dav/owned/</D:href>
    <D:propstat><D:prop><D:resourcetype><D:collection/></D:resourcetype></D:prop></D:propstat>
  </D:response>
</D:multistatus>]],
        }
      end

      local children, err = webdav.list_dir("moo://testserver/")
      curl.request = original_request

      assert.is_nil(err)
      assert.are.equal(2, #children)
      assert.are.equal("object/", children[1].name)
      assert.are.equal("moo://testserver/object/", children[1].uri)
      assert.are.equal("owned/", children[2].name)
      assert.are.equal("moo://testserver/owned/", children[2].uri)
    end)

    it("extracts MOO-specific extensions like M:owner and M:permissions", function()
      lambdamoo.config.connections = {
        {
          authority = "testserver",
          endpoint = "https://example.com/dav/",
        },
      }

      local original_request = curl.request
      curl.request = function(opts)
        return {
          status = 207,
          body = [[<?xml version="1.0" encoding="utf-8"?>
<D:multistatus xmlns:D="DAV:" xmlns:M="urn:moo:webdav">
  <D:response>
    <D:href>/dav/owned/525/verb/</D:href>
    <D:propstat><D:prop><D:resourcetype><D:collection/></D:resourcetype></D:prop></D:propstat>
  </D:response>
  <D:response>
    <D:href>/dav/owned/525/verb/check_authorization</D:href>
    <D:propstat>
      <D:prop>
        <M:owner>#267</M:owner>
        <M:permissions>rxd</M:permissions>
        <M:names>check_authorization</M:names>
        <M:arguments>{"this", "none", "this"}</M:arguments>
      </D:prop>
    </D:propstat>
  </D:response>
</D:multistatus>]],
        }
      end

      local children, err = webdav.list_dir("moo://testserver/owned/525/verb/")
      curl.request = original_request

      assert.is_nil(err)
      assert.are.equal(1, #children)
      local item = children[1]
      assert.are.equal("check_authorization", item.name)
      assert.are.equal("moo://testserver/owned/525/verb/check_authorization", item.uri)
      assert.are.equal("#267", item.owner)
      assert.are.equal("rxd", item.perms)
      assert.are.equal('{"this", "none", "this"}', item.args)
    end)
  end)

  describe("canonical_object_uri", function()
    it("canonicalizes paths opened through the owned-object collection", function()
      assert.are.equal(
        "moo://testserver/object/454/verb/check_authorization",
        webdav.canonical_object_uri("moo://testserver/owned/454/verb/check_authorization")
      )
      assert.are.equal(
        "moo://testserver/object/-1/property/name/string",
        webdav.canonical_object_uri("moo://testserver/owned/-1/property/name/string")
      )
      assert.are.equal("moo://testserver/owned", webdav.canonical_object_uri("moo://testserver/owned"))
      assert.are.equal(
        "moo://testserver/object/454/verb/check_authorization",
        webdav.canonical_object_uri("moo://testserver/object/454/verb/check_authorization")
      )
    end)
  end)

  describe("canonical_verb_uri", function()
    it("canonicalizes verb paths across property chains and defined-on origins", function()
      local original_read_file = webdav.read_file
      webdav.read_file = function(uri)
        if uri == "moo://testserver/object/0/property/string_utils/object/resolve/verb/explode/defined-on" then
          return "#18"
        end
        return nil, "Not found"
      end

      assert.are.equal(
        "moo://testserver/object/18/verb/explode",
        webdav.canonical_verb_uri("moo://testserver/object/0/property/string_utils/object/verb/explode")
      )

      webdav.read_file = original_read_file
    end)
  end)
end)
