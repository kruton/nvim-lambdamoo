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

function M.list_dir(uri)
  local authority, path = parse_uri(uri)
  if not authority or not path then
    return nil, "Invalid URI: " .. tostring(uri)
  end

  local conn = get_connection(authority)
  if not conn then
    return nil, "No connection profile configured for authority '" .. authority .. "'"
  end

  local url = build_url(conn, path)

  local res = curl.request({
    method = "PROPFIND",
    url = url,
    headers = {
      ["Depth"] = "1",
    },
    raw = { "--netrc-optional" },
    insecure = false,
  })

  if res.status >= 200 and res.status < 300 then
    local xml2lua = require("xml2lua")
    local handler = require("xmlhandler.tree")
    local tree_handler = handler:new()
    local parser = xml2lua.parser(tree_handler)
    parser:parse(res.body)

    local children = {}
    local multistatus = tree_handler.root["D:multistatus"]
    if not multistatus then
      return children
    end

    local responses = multistatus["D:response"]
    if not responses then
      return children
    end

    -- Ensure it's iterable even if there's only one response
    if #responses == 0 then
      responses = { responses }
    end

    for _, resp in ipairs(responses) do
      local href = resp["D:href"]
      if type(href) == "table" then
        href = href[1]
      end
      if href then
        href = vim.uri_decode(href)
        local name = href:match("([^/]+/?)$")

        local current_path_name = path:match("([^/]+/?)$") or ""

        if name and name ~= "" and name ~= current_path_name then
          -- Extract custom MOO properties
          local props = {}
          local propstat = resp["D:propstat"]

          -- handle propstat being a table or array of tables
          local propstats = propstat
          if propstat and #propstat == 0 then
            propstats = { propstat }
          end

          if propstats then
            for _, stat in ipairs(propstats) do
              if stat["D:prop"] then
                for k, v in pairs(stat["D:prop"]) do
                  props[k] = v
                end
              end
            end
          end

          local owner = props["moo-owner"] or ""
          local perms = props["moo-permissions"] or ""
          local names = props["moo-names"] or ""
          local args_str = props["moo-arguments"] or ""

          table.insert(children, {
            name = name,
            owner = type(owner) == "table" and owner[1] or owner,
            perms = type(perms) == "table" and perms[1] or perms,
            names = type(names) == "table" and names[1] or names,
            args = type(args_str) == "table" and args_str[1] or args_str,
            uri = href,
          })
        end
      end
    end
    return children
  end

  return nil, string.format("HTTP %s from %s: %s", tostring(res.status), url, res.body or "")
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
