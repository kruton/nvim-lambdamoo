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
      if uri:sub(-1) == "/" then
        -- Directory browsing mode
        local children, err = webdav.list_dir(uri)
        if children then
          local lines = {}
          for _, child in ipairs(children) do
            -- Format name and custom info nicely
            local info = {}
            if type(child.owner) == "string" and child.owner ~= "" then
              table.insert(info, child.owner)
            end
            if type(child.perms) == "string" and child.perms ~= "" then
              table.insert(info, child.perms)
            end
            if type(child.args) == "string" and child.args ~= "" then
              table.insert(info, child.args)
            end
            if type(child.names) == "string" and child.names ~= "" and child.names ~= child.name:gsub("/$", "") then
              table.insert(info, "(" .. child.names .. ")")
            end

            local info_str = table.concat(info, "  ")
            if info_str ~= "" then
              table.insert(lines, string.format("%-30s %s", child.name, info_str))
            else
              table.insert(lines, child.name)
            end
          end
          vim.api.nvim_buf_set_lines(args.buf, 0, -1, false, lines)
          vim.bo[args.buf].buftype = "nofile"
          vim.bo[args.buf].filetype = "moo_dir"
          vim.bo[args.buf].modifiable = false

          -- Map <CR> to edit the file/directory under the cursor
          vim.keymap.set("n", "<CR>", function()
            local line_num = vim.api.nvim_win_get_cursor(0)[1]
            local child = children[line_num]
            if child and child.uri then
              local target = child.uri
              vim.cmd("edit " .. vim.fn.fnameescape(target))
            end
          end, { buffer = args.buf, silent = true, desc = "Open item under cursor" })

          -- Map - to go up a directory
          vim.keymap.set("n", "-", function()
            local base_uri = uri:gsub("/+$", "")
            local parent = base_uri:match("^(moo://[^/]+/.*)/[^/]+$")
            if not parent then
              parent = base_uri:match("^(moo://[^/]+)/?$")
              if parent and parent:sub(-1) ~= "/" then
                parent = parent .. "/"
              end
            else
              parent = parent .. "/"
            end
            if parent and parent ~= uri then
              vim.cmd("edit " .. vim.fn.fnameescape(parent))
            end
          end, { buffer = args.buf, silent = true, desc = "Go up directory" })
        else
          vim.notify("Failed to list directory " .. uri .. (err and (": " .. err) or ""), vim.log.levels.ERROR)
        end
      else
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
