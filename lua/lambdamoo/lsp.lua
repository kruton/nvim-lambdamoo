local M = {}
local config = require("lambdamoo").config
local webdav = require("lambdamoo.webdav")

local function resolve_location(loc)
  if not loc then
    return loc
  end
  if loc.uri and loc.uri:match("^moo://") then
    loc.uri = webdav.resolve_verb_definition(loc.uri)
  elseif loc.targetUri and loc.targetUri:match("^moo://") then
    loc.targetUri = webdav.resolve_verb_definition(loc.targetUri)
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

  -- Fallback: if no hover documentation (e.g. on a custom verb call like $you:say_action),
  -- query definition to find where the verb is defined and display it in hover
  local client = vim.lsp.get_client_by_id(ctx.client_id)
  if not client then
    return vim.lsp.handlers["textDocument/hover"](err, result, ctx, handler_config)
  end

  local params = {
    textDocument = ctx.params and ctx.params.textDocument or vim.lsp.util.make_text_document_params(ctx.bufnr),
    position = ctx.params and ctx.params.position,
  }

  lsp_request(client, "textDocument/definition", params, function(_def_err, def_result)
    if def_result then
      local loc = vim.islist(def_result) and def_result[1] or def_result
      if loc then
        resolve_location(loc)
        local target_uri = loc.uri or loc.targetUri
        if target_uri then
          local hover_result = {
            contents = {
              kind = "markdown",
              value = string.format("```moo\nDefined on: %s\n```", target_uri),
            },
            range = loc.range or loc.targetRange,
          }
          return vim.lsp.handlers["textDocument/hover"](nil, hover_result, ctx, handler_config)
        end
      end
    end
    return vim.lsp.handlers["textDocument/hover"](err, result, ctx, handler_config)
  end, ctx.bufnr)
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
