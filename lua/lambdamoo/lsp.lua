local M = {}
local config = require("lambdamoo").config
local webdav = require("lambdamoo.webdav")

local function resolve_location(loc)
  if not loc then
    return loc
  end
  local resolver = webdav.canonical_verb_uri or webdav.resolve_verb_definition
  if loc.uri and loc.uri:match("^moo://") then
    loc.uri = resolver(loc.uri)
  elseif loc.targetUri and loc.targetUri:match("^moo://") then
    loc.targetUri = resolver(loc.targetUri)
  end
  return loc
end

local function definition_handler(err, result, ctx, handler_config)
  if result then
    if vim.islist(result) then
      for _, loc in ipairs(result) do
        resolve_location(loc)
      end
    else
      resolve_location(result)
    end
  end
  return vim.lsp.handlers["textDocument/definition"](err, result, ctx, handler_config)
end

local function lsp_request(client, method, params, handler, bufnr)
  -- Neovim 0.11+ uses client:request(method, params, handler, bufnr)
  -- Neovim 0.10.x uses client.request(method, params, handler, bufnr)
  local ok = pcall(function()
    client:request(method, params, handler, bufnr)
  end)
  if not ok then
    client.request(method, params, handler, bufnr)
  end
end

function M.parse_verb_header(content)
  if not content or content == "" then
    return { comments = {}, args = nil }
  end

  local lines = vim.split(content, "\r?\n")
  local comments = {}
  local args = nil

  for _, line in ipairs(lines) do
    if line:match("^%s*$") then
      if #comments > 0 and comments[#comments] ~= "" then
        table.insert(comments, "")
      end
    else
      local comment = line:match('^%s*"(.*)"%s*;?%s*$')
      if comment then
        local unescaped = comment:gsub('\\(["\\])', "%1")
        local trimmed = vim.trim(unescaped)
        table.insert(comments, trimmed)
      else
        local args_match = line:match("^%s*(.-)%s*=%s*args%s*;?%s*$")
        if args_match and not args then
          local trimmed = vim.trim(line)
          if not trimmed:match(";%s*$") then
            trimmed = trimmed .. ";"
          end
          args = trimmed
        else
          break
        end
      end
    end
  end

  while #comments > 0 and comments[#comments] == "" do
    table.remove(comments)
  end

  return { comments = comments, args = args }
end

function M.format_hover_markdown(target_uri, header)
  local parts = {}

  if header and header.args then
    table.insert(parts, string.format("```moo\n%s\n```", header.args))
  end

  if header and #header.comments > 0 then
    table.insert(parts, table.concat(header.comments, "\n"))
  end

  table.insert(parts, string.format("```moo\nDefined on: %s\n```", target_uri))

  return table.concat(parts, "\n\n")
end

local function get_verb_content(uri)
  if not uri then
    return nil
  end

  -- Check open Neovim buffers
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(buf) and vim.api.nvim_buf_get_name(buf) == uri then
      local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
      return table.concat(lines, "\n")
    end
  end

  -- Remote WebDAV file
  if uri:match("^moo://") then
    local content, _ = webdav.read_file(uri)
    return content
  end

  -- Local file path
  local file_path = uri:match("^file://(.+)$") or uri
  if vim.fn.filereadable(file_path) == 1 then
    local lines = vim.fn.readfile(file_path)
    return table.concat(lines, "\n")
  end

  return nil
end

local function resolve_hover_from_definition(client, params, bufnr, callback)
  local def_params = {
    textDocument = params and params.textDocument or vim.lsp.util.make_text_document_params(bufnr),
    position = params and params.position,
  }

  lsp_request(client, "textDocument/definition", def_params, function(_def_err, def_result)
    if def_result then
      local loc = vim.islist(def_result) and def_result[1] or def_result
      if loc then
        resolve_location(loc)
        local target_uri = loc.uri or loc.targetUri
        if target_uri then
          local hover_value
          if target_uri:match("/verb/") then
            local content = get_verb_content(target_uri)
            local header = M.parse_verb_header(content)
            hover_value = M.format_hover_markdown(target_uri, header)
          else
            hover_value = string.format("```moo\nDefined on: %s\n```", target_uri)
          end

          local hover_result = {
            contents = {
              kind = "markdown",
              value = hover_value,
            },
            range = loc.range or loc.targetRange,
          }
          return callback(hover_result)
        end
      end
    end
    return callback(nil)
  end, bufnr)
end

local function hover_handler(err, result, ctx, handler_config)
  local has_content = false
  if result and result.contents then
    local contents = result.contents
    if type(contents) == "table" then
      if contents.value and contents.value ~= "" then
        has_content = true
      elseif #contents > 0 then
        has_content = true
      end
    elseif type(contents) == "string" and contents ~= "" then
      has_content = true
    end
  end

  if has_content then
    return vim.lsp.handlers["textDocument/hover"](err, result, ctx, handler_config)
  end

  local client = vim.lsp.get_client_by_id(ctx.client_id)
  if not client then
    return vim.lsp.handlers["textDocument/hover"](err, result, ctx, handler_config)
  end

  resolve_hover_from_definition(client, ctx.params, ctx.bufnr, function(hover_result)
    if hover_result then
      return vim.lsp.handlers["textDocument/hover"](nil, hover_result, ctx, handler_config)
    end
    return vim.lsp.handlers["textDocument/hover"](err, result, ctx, handler_config)
  end)
end

local function wrap_client(client)
  if not client or client._lambdamoo_wrapped then
    return
  end
  client._lambdamoo_wrapped = true

  local orig_request = client.request
  client.request = function(self, method, params, handler, bufnr)
    if method == "textDocument/hover" and handler then
      return orig_request(self, method, params, function(err, result, ctx, req_config)
        local has_content = false
        if result and result.contents then
          local contents = result.contents
          if type(contents) == "table" then
            if contents.value and contents.value ~= "" then
              has_content = true
            elseif #contents > 0 then
              has_content = true
            end
          elseif type(contents) == "string" and contents ~= "" then
            has_content = true
          end
        end

        if has_content then
          return handler(err, result, ctx, req_config)
        end

        resolve_hover_from_definition(self, params, bufnr or (ctx and ctx.bufnr), function(hover_result)
          if hover_result then
            return handler(nil, hover_result, ctx, req_config)
          end
          return handler(err, result, ctx, req_config)
        end)
      end, bufnr)
    end
    return orig_request(self, method, params, handler, bufnr)
  end
end

function M.setup()
  local group = vim.api.nvim_create_augroup("LambdaMooLSP", { clear = true })

  -- Attach LSP to local .moo files and remote moo:// buffers
  vim.api.nvim_create_autocmd("FileType", {
    group = group,
    pattern = "moo",
    callback = function(args)
      local client_id = vim.lsp.start({
        name = "moo-lsp-rs",
        cmd = config.lsp.cmd,
        root_dir = vim.fs.dirname(vim.fs.find({ ".git", ".vscode" }, { upward = true })[1]) or vim.fn.getcwd(),
        handlers = {
          ["textDocument/definition"] = definition_handler,
          ["textDocument/hover"] = hover_handler,
        },
      })
      if client_id then
        local client = vim.lsp.get_client_by_id(client_id)
        wrap_client(client)
        vim.lsp.buf_attach_client(args.buf, client_id)

        -- Enable inlay hints if supported and enabled in config
        if config.lsp.inlay_hints ~= false and vim.lsp.inlay_hint then
          pcall(vim.lsp.inlay_hint.enable, true, { bufnr = args.buf })
          pcall(vim.lsp.inlay_hint.enable, args.buf, true)
        end
      end
    end,
  })
end

return M
