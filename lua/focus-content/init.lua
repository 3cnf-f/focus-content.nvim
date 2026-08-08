
local M = {}

M.config = {
  tmux_env_vars = {
    "TMUX",
  },

  herdr_env_vars = {
    "HERDR",
    "HERDR_SESSION",
  },
}

local function has_env_var(names)
  for _, name in ipairs(names) do
    local value = vim.env[name]

    if value ~= nil and value ~= "" then
      return true
    end
  end

  return false
end

function M.detect_language(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()

  local filename = vim.api.nvim_buf_get_name(bufnr)

  if filename:sub(-3) == ".py" then
    return "python"
  end

  if filename:sub(-3) == ".sh" then
    return "shell"
  end

  return "na"
end

function M.detect_multiplexer()
  if has_env_var(M.config.tmux_env_vars) then
    return "tmux"
  end

  if has_env_var(M.config.herdr_env_vars) then
    return "herdr"
  end

  return "na"
end

function M.refresh()
  local bufnr = vim.api.nvim_get_current_buf()
  local language = M.detect_language(bufnr)
  local multiplexer = M.detect_multiplexer()

  -- Global values for the currently focused buffer.
  vim.g.focus_context_language = language
  vim.g.focus_context_multiplexer = multiplexer

  -- Also retain the language value on the individual buffer.
  vim.api.nvim_buf_set_var(bufnr, "focus_context_language", language)

  return {
    language = language,
    multiplexer = multiplexer,
  }
end

function M.setup(opts)
  if vim.fn.has("nvim-0.12") ~= 1 then
    vim.notify(
      "focus-context.nvim requires Neovim 0.12 or newer",
      vim.log.levels.ERROR
    )
    return
  end

  M.config = vim.tbl_deep_extend("force", M.config, opts or {})

  local group = vim.api.nvim_create_augroup("FocusContext", {
    clear = true,
  })

  vim.api.nvim_create_autocmd({
    "BufEnter",
    "BufWinEnter",
    "WinEnter",
    "TabEnter",
    "FocusGained",
  }, {
    group = group,
    desc = "Refresh focus-context.nvim state",
    callback = function()
      M.refresh()
    end,
  })

  vim.api.nvim_create_user_command("FocusContextRefresh", function()
    M.refresh()
  end, {
    desc = "Refresh focus-context.nvim state",
    force = true,
  })

  M.refresh()
end

return M
