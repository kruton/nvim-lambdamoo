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
    local ok_xml, xml2lua = pcall(require, "xml2lua")
    if not ok_xml then
      return nil, "xml2lua not found: please ensure 'a-usr/xml2lua.nvim' is installed"
    end
    local ok_tree, handler = pcall(require, "xml2lua.xmlhandler.tree")
    if not ok_tree then
      ok_tree, handler = pcall(require, "xmlhandler.tree")
    end
    if not ok_tree then
      return nil, "xml2lua tree handler not found"
    end
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

    local endpoint_base = conn.endpoint:match("^https?://[^/]+(/.*)$") or "/"
    endpoint_base = endpoint_base:gsub("/+$", "") .. "/"
    local full_req_path = endpoint_base .. path

    for _, resp in ipairs(responses) do
      local href = resp["D:href"]
      if type(href) == "table" then
        href = href[1]
      end
      if href then
        href = vim.uri_decode(href)
        local href_path = href:match("^https?://[^/]+(/.*)$") or href
        local norm_href = href_path:gsub("/+$", "")
        local norm_req = full_req_path:gsub("/+$", "")

        if norm_href ~= norm_req then
          -- Extract custom MOO properties
          local props = {}
          local propstat = resp["D:propstat"]

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

          local is_col = false
          if href_path:sub(-1) == "/" then
            is_col = true
          elseif props["D:resourcetype"] then
            local rt = props["D:resourcetype"]
            if type(rt) == "table" and (rt["D:collection"] or rt["collection"]) then
              is_col = true
            end
          end

          local rel_path = href_path
          if rel_path:sub(1, #endpoint_base) == endpoint_base then
            rel_path = rel_path:sub(#endpoint_base + 1)
          end

          local name = rel_path:match("([^/]+/?)$") or rel_path
          if is_col and name:sub(-1) ~= "/" then
            name = name .. "/"
          end

          if is_col and rel_path:sub(-1) ~= "/" then
            rel_path = rel_path .. "/"
          end

          local child_uri = string.format("moo://%s/%s", authority, rel_path)

          local to_string = function(val)
            if type(val) == "table" then
              if #val > 0 then
                return tostring(val[1])
              end
              return ""
            end
            if val == nil then
              return ""
            end
            return tostring(val)
          end

          local owner = to_string(props["M:owner"] or props["moo-owner"] or props["owner"])
          local perms = to_string(props["M:permissions"] or props["moo-permissions"] or props["permissions"])
          local names = to_string(props["M:names"] or props["moo-names"] or props["names"])
          local args_str = to_string(props["M:arguments"] or props["moo-arguments"] or props["arguments"])

          table.insert(children, {
            name = name,
            owner = owner,
            perms = perms,
            names = names,
            args = args_str,
            uri = child_uri,
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

function M.canonical_object_uri(uri)
  local authority, path = parse_uri(uri)
  if not authority or not path then
    return uri
  end

  local id, rest = path:match("^owned/(%-?%d+)(/.*)$")
  if id and rest then
    return string.format("moo://%s/object/%s%s", authority, id, rest)
  end

  return uri
end

return M
