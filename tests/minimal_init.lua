local M = {}

-- Add repository root to runtimepath
local repo_root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h")
vim.opt.rtp:prepend(repo_root)
vim.opt.swapfile = false

-- Look for plenary in .ci or Neovim's installed packpath
local plenary_paths = {
  repo_root .. "/.ci/plenary.nvim",
  vim.fn.stdpath("data") .. "/site/pack/plugins/start/plenary.nvim",
}

local plenary_found = false
for _, path in ipairs(plenary_paths) do
  if vim.fn.isdirectory(path) == 1 then
    vim.opt.rtp:prepend(path)
    plenary_found = true
    break
  end
end

local xml2lua_paths = {
  repo_root .. "/.ci/xml2lua.nvim",
  vim.fn.stdpath("data") .. "/site/pack/plugins/start/xml2lua.nvim",
}
for _, path in ipairs(xml2lua_paths) do
  if vim.fn.isdirectory(path) == 1 then
    vim.opt.rtp:prepend(path)
    break
  end
end

if not plenary_found then
  local plenary_files = vim.api.nvim_get_runtime_file("lua/plenary/busted.lua", false)
  if #plenary_files == 0 then
    error("plenary.nvim not found! Please clone plenary.nvim into .ci/plenary.nvim or install it.")
  end
end

vim.cmd("runtime! plugin/plenary.vim")

return M
