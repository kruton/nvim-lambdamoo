local M = {}
local curl = require("plenary.curl")
local config = require("lambdamoo").config

M.etags = {}

local function parse_uri(uri)
  -- Parse moo://<authority>/<path>
  local authority, path = uri:match("^moo://([^/]+)/(.*)$")
  return authority, path
end

local function get_connection(authority)
  for _, conn in ipairs(config.connections or {}) do
    if conn.authority == authority then
      return conn
    end
  end
  return nil
end

local function build_url(conn, path)
  -- Ensure endpoint ends with /
  local base = conn.endpoint:gsub("/+$", "") .. "/"
  return base .. path
end

local function extract_etag(headers)
  if not headers then
    return nil
  end
  for _, h in ipairs(headers) do
    local k, v = h:match("^([%w%-]+):%s*(.*)$")
    if k and k:lower() == "etag" then
      return v:gsub("^%s*", ""):gsub("%s*$", "")
    end
  end
  return nil
end

function M.read_file(uri)
  local authority, path = parse_uri(uri)
  if not authority or not path then
    return nil, "Invalid URI: " .. tostring(uri)
  end

  local conn = get_connection(authority)
  if not conn then
    return nil, "No connection profile configured for authority '" .. authority .. "'"
  end

  local url = build_url(conn, path)

  local res = curl.get(url, {
    raw = { "--netrc-optional" }, -- Use ~/.netrc
    insecure = false,
  })

  if res.status == 200 then
    local etag = extract_etag(res.headers)
    if etag then
      M.etags[uri] = etag
    end
    return res.body
  end

  return nil, string.format("HTTP %s from %s: %s", tostring(res.status), url, res.body or "")
end

function M.write_file(uri, content)
  local authority, path = parse_uri(uri)
  if not authority or not path then
    return false, "Invalid URI: " .. tostring(uri)
  end

  local conn = get_connection(authority)
  if not conn then
    return false, "No connection profile configured for authority '" .. authority .. "'"
  end

  local url = build_url(conn, path)
  local headers = {
    ["Content-Type"] = "text/plain; charset=utf-8",
  }

  local etag = M.etags[uri]
  if etag then
    headers["If-Match"] = etag
  end

  local res = curl.put(url, {
    raw = { "--netrc-optional" }, -- Use ~/.netrc
    headers = headers,
    body = content,
    insecure = false,
  })

  if res.status >= 200 and res.status < 300 then
    local new_etag = extract_etag(res.headers)
    if new_etag then
      M.etags[uri] = new_etag
    end
    return true
  end

  return false, string.format("HTTP %s from %s: %s", tostring(res.status), url, res.body or "")
end

function M.resolve_verb_definition(uri)
  local authority, path = parse_uri(uri)
  if not authority or not path then
    return uri
  end

  local object_path, verb_name = path:match("^(.*)/verb/([^/]+)$")
  if not object_path or not verb_name then
    return uri
  end

  local resolution_path = string.format("%s/resolve/verb/%s/defined-on", object_path, verb_name)
  local resolution_uri = string.format("moo://%s/%s", authority, resolution_path)

  local content = M.read_file(resolution_uri)
  if content then
    local defined_on = content:match("^#?(%-?%d+)")
    if defined_on then
      return string.format("moo://%s/object/%s/verb/%s", authority, defined_on, verb_name)
    end
  end
  return uri
end

return M
