local M = {}
local config = require("lambdamoo").config
local webdav = require("lambdamoo.webdav")

local function find_buffer(uri)
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(buf) and vim.api.nvim_buf_get_name(buf) == uri then
      return buf
    end
  end
  return nil
end

local function read_document(_, params)
  if type(params) ~= "table" or type(params.uri) ~= "string" or not params.uri:match("^moo://") then
    return nil, vim.lsp.rpc_response_error(vim.lsp.protocol.ErrorCodes.InvalidParams, "Expected a configured moo: URI")
  end
  local buf = find_buffer(params.uri)
  if buf then
    return { text = table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), "\n") }
  end
  local content, err = webdav.read_file(params.uri)
  if not content then
    return nil, vim.lsp.rpc_response_error(vim.lsp.protocol.ErrorCodes.InternalError, err or "Remote read failed")
  end
  return { text = content }
end

local function replace_document(uri, canonical_uri)
  local buf = find_buffer(uri)
  if not buf or uri == canonical_uri then
    return
  end
  if vim.bo[buf].modified then
    vim.api.nvim_create_autocmd({ "BufWritePost", "BufDelete" }, {
      buffer = buf,
      once = true,
      callback = function(args)
        if args.event == "BufWritePost" then
          vim.schedule(function()
            replace_document(uri, canonical_uri)
          end)
        end
      end,
    })
    return
  end

  local windows = vim.fn.win_findbuf(buf)
  if #windows == 0 then
    vim.api.nvim_buf_call(buf, function()
      vim.cmd("silent keepalt edit " .. vim.fn.fnameescape(canonical_uri))
    end)
  else
    for _, win in ipairs(windows) do
      vim.api.nvim_win_call(win, function()
        vim.cmd("silent keepalt edit " .. vim.fn.fnameescape(canonical_uri))
      end)
    end
  end
  if vim.api.nvim_buf_is_valid(buf) and not vim.bo[buf].modified then
    pcall(vim.api.nvim_buf_delete, buf, { force = true })
  end
end

local function canonicalize_document(_, params)
  if type(params) ~= "table" or type(params.uri) ~= "string" or type(params.canonicalUri) ~= "string" then
    return
  end
  if not params.uri:match("^moo://") or not params.canonicalUri:match("^moo://") then
    return
  end
  vim.schedule(function()
    replace_document(params.uri, params.canonicalUri)
  end)
end

function M.setup()
  local group = vim.api.nvim_create_augroup("LambdaMooLSP", { clear = true })

  vim.api.nvim_create_autocmd("FileType", {
    group = group,
    pattern = "moo",
    callback = function(args)
      local client_id = vim.lsp.start({
        name = "moo-lsp-rs",
        cmd = config.lsp.cmd,
        root_dir = vim.fs.dirname(vim.fs.find({ ".git", ".vscode" }, { upward = true })[1]) or vim.fn.getcwd(),
        init_options = {
          lambdamoo = { remoteDocuments = 1 },
        },
        handlers = {
          ["lambdamoo/readDocument"] = read_document,
          ["lambdamoo/canonicalizeDocument"] = canonicalize_document,
        },
      })
      if client_id then
        vim.lsp.buf_attach_client(args.buf, client_id)
        if config.lsp.inlay_hints ~= false and vim.lsp.inlay_hint then
          pcall(vim.lsp.inlay_hint.enable, true, { bufnr = args.buf })
          pcall(vim.lsp.inlay_hint.enable, args.buf, true)
        end
      end
    end,
  })
end

return M
