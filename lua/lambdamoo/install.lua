local M = {}
local curl = require("plenary.curl")

function M.install()
  local sysname = vim.loop.os_uname().sysname
  local arch = vim.loop.os_uname().machine
  local target

  if sysname == "Linux" then
    target = arch == "aarch64" and "linux-arm64" or "linux-x64"
  elseif sysname == "Darwin" then
    target = arch == "arm64" and "darwin-arm64" or "darwin-x64"
  else
    vim.notify("Unsupported OS for auto-install", vim.log.levels.ERROR)
    return
  end

  local repo = "kruton/moo-lsp-rs"
  local api_url = "https://api.github.com/repos/" .. repo .. "/releases/latest"

  vim.notify("Fetching latest moo-lsp-rs release info...", vim.log.levels.INFO)

  local res = curl.get(api_url, { headers = { ["User-Agent"] = "nvim-lambdamoo" } })
  if res.status ~= 200 then
    vim.notify("Failed to fetch release info", vim.log.levels.ERROR)
    return
  end

  local data = vim.json.decode(res.body)
  local asset_name = "moo-lsp-rs-" .. target .. ".tar.gz"
  local download_url = nil

  for _, asset in ipairs(data.assets) do
    if asset.name == asset_name then
      download_url = asset.browser_download_url
      break
    end
  end

  if not download_url then
    vim.notify("No matching binary found for " .. target, vim.log.levels.ERROR)
    return
  end

  local install_dir = vim.fn.stdpath("data") .. "/lambdamoo"
  vim.fn.mkdir(install_dir, "p")
  local archive_path = install_dir .. "/moo-lsp-rs.tar.gz"

  vim.notify("Downloading moo-lsp-rs...", vim.log.levels.INFO)
  curl.get(download_url, { output = archive_path })

  vim.notify("Extracting...", vim.log.levels.INFO)
  vim.system({ "tar", "-xzf", archive_path, "-C", install_dir }):wait()
  vim.fn.delete(archive_path)

  -- Update config to use the downloaded binary
  local config = require("lambdamoo").config
  config.lsp.cmd = { install_dir .. "/" .. target .. "/moo-lsp-rs" }

  vim.notify("moo-lsp-rs installed successfully!", vim.log.levels.INFO)
end

return M
