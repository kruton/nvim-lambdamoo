local M = {}
local webdav = require("lambdamoo.webdav")

function M.setup()
  local group = vim.api.nvim_create_augroup("LambdaMooVFS", { clear = true })

  -- Handle reading moo:// files
  vim.api.nvim_create_autocmd({ "BufReadCmd", "FileReadCmd" }, {
    group = group,
    pattern = "moo://*",
    callback = function(args)
      local uri = args.match
      local content, err = webdav.read_file(uri)
      if content then
        -- Normalize line breaks and avoid trailing empty line
        content = content:gsub("\r\n", "\n"):gsub("\r", "\n")
        if content:sub(-1) == "\n" then
          content = content:sub(1, -2)
        end
        local lines = vim.split(content, "\n", { plain = true })
        vim.api.nvim_buf_set_lines(args.buf, 0, -1, false, lines)
        vim.bo[args.buf].buftype = "acwrite"
        vim.bo[args.buf].filetype = "moo"
        vim.bo[args.buf].modified = false
      else
        vim.notify("Failed to read " .. uri .. (err and (": " .. err) or ""), vim.log.levels.ERROR)
      end
    end,
  })

  -- Handle writing moo:// files
  vim.api.nvim_create_autocmd({ "BufWriteCmd", "FileWriteCmd" }, {
    group = group,
    pattern = "moo://*",
    callback = function(args)
      local uri = args.match
      local lines = vim.api.nvim_buf_get_lines(args.buf, 0, -1, false)
      local content = table.concat(lines, "\n") .. "\n"
      local success, err = webdav.write_file(uri, content)
      if success then
        vim.bo[args.buf].modified = false
        vim.notify("Saved " .. uri, vim.log.levels.INFO)
      else
        vim.notify("Failed to save " .. uri .. (err and (": " .. err) or ""), vim.log.levels.ERROR)
      end
    end,
  })
end

return M
