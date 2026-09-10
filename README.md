# nvim-lambdamoo

A Neovim plugin for LambdaMOO development, providing virtual filesystem (VFS) access over WebDAV and integration with the [`moo-lsp-rs`](https://github.com/kruton/moo-lsp-rs) language server.

---

## Features

- **Transparent WebDAV VFS (`moo://`)**: Edit remote LambdaMOO verbs and objects directly in Neovim (e.g., `:edit moo://codepoint/object/168/verb/test2`).
- **Concurrency Control**: Automatically caches and sends HTTP `ETag` / `If-Match` headers on save to prevent clobbering concurrent edits.
- **`moo-lsp-rs` Integration**:
  - **Auto-installation**: Automatically downloads and installs the platform-specific `moo-lsp-rs` binary (Linux & macOS) if not already present on `PATH`.
  - **Inlay Hints**: Displays parameter names for built-in function calls (e.g., `index(str1: x, str2: ":")`).
  - **Hover (`K`)**: Shows built-in function signatures and resolves verb definition origins.
  - **Go to Definition (`gd`)**: Resolves remote verb calls across object-valued property chains (e.g., `$you:say_action()`) and queries server inheritance to jump to the actual defining object.

---

## Requirements

- Neovim `>= 0.10.0`
- [`nvim-lua/plenary.nvim`](https://github.com/nvim-lua/plenary.nvim)
- `curl`

---

## Installation

### Using [lazy.nvim](https://github.com/folke/lazy.nvim)

```lua
{
  "kruton/nvim-lambdamoo",
  dependencies = {
    "nvim-lua/plenary.nvim",
  },
  opts = {
    connections = {
      {
        authority = "codepoint",
        endpoint = "https://codepoint.the-b.org/dav/",
      },
    },
    lsp = {
      inlay_hints = true,
    },
  },
}
```

### Using [packer.nvim](https://github.com/wbthomason/packer.nvim)

```lua
use({
  "kruton/nvim-lambdamoo",
  requires = { "nvim-lua/plenary.nvim" },
  config = function()
    require("lambdamoo").setup({
      connections = {
        {
          authority = "codepoint",
          endpoint = "https://codepoint.the-b.org/dav/",
        },
      },
    })
  end,
})
```

---

## Authentication (`~/.netrc`)

Credentials are read automatically via `curl` from your `~/.netrc` file:

```netrc
machine codepoint.the-b.org
login your-username
password your-password
```

Ensure correct file permissions:
```bash
chmod 600 ~/.netrc
```

---

## Configuration

Default options:

```lua
require("lambdamoo").setup({
  lsp = {
    cmd = { "moo-lsp-rs" }, -- Command to start language server (auto-downloads if missing)
    inlay_hints = true,     -- Automatically enable LSP inlay hints in moo buffers
  },
  connections = {
    -- Map URI authority names to remote WebDAV endpoints
    -- {
    --   authority = "codepoint",
    --   endpoint = "https://codepoint.the-b.org/dav/",
    -- },
  },
})
```

---

## Usage

Open any remote verb or object using the `moo://` scheme:

```vim
:edit moo://codepoint/object/168/verb/test2
```

Or from the command line:

```bash
nvim moo://codepoint/object/168/verb/test2
```

- Saving the buffer (`:write`) automatically issues a WebDAV `PUT` with the current `If-Match` ETag.
- Pressing `K` over a built-in function like `index()` displays documentation and signature hints.
- Pressing `K` or `gd` over a verb call like `$you:say_action()` queries the remote server to find the object where the verb is defined and navigates or displays its definition.

---

## Development & Testing

A `Makefile` is provided to run the headless plenary test suite:

```bash
# Run all unit and integration tests
make test

# Run a specific spec file
make test FILE=tests/fixture_spec.lua

# Verify formatting
make fmt-check
```
