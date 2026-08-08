# focus-context.nvim

A minimal Neovim plugin that tracks context for the currently focused buffer.

## Requirements

- Neovim `>= 0.12`
- Lua-enabled Neovim

## State

The plugin updates these global variables:

| Variable | Possible values |
| --- | --- |
| `vim.g.focus_context_language` | `"python"`, `"shell"`, `"na"` |
| `vim.g.focus_context_multiplexer` | `"tmux"`, `"herdr"`, `"na"` |

Language detection is based on the current buffer filename:

- `*.py` → `"python"`
- `*.sh` → `"shell"`
- everything else → `"na"`

Multiplexer detection checks environment variables:

- `$TMUX` → `"tmux"`
- `$HERDR` or `$HERDR_SESSION` → `"herdr"`
- otherwise → `"na"`

## lazy.nvim

```lua
{
  "YOUR_GITHUB_USERNAME/focus-context.nvim",
  config = function()
    require("focus_context").setup()
  end,
}
