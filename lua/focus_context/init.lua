local M = {}

M.config = {
  tmux_env_vars = {
    "TMUX",
  },

  herdr_env_vars = {
    "HERDR_ENV",
  },
}

M.state = {
  herdr_fc_out_tab_id = nil,
  herdr_fc_out_pane_id = nil,
  herdr_fc_out_cwd = nil,
}

local function run_system(args)
  local result = vim.system(args, {
    text = true,
  }):wait()

  if result.code ~= 0 then
    local error_message = result.stderr

    if error_message == nil or error_message == "" then
      error_message = result.stdout
    end

    return nil, error_message
  end

  return result.stdout, nil
end

local function decode_json(output)
  local ok, decoded = pcall(vim.json.decode, output)

  if not ok then
    return nil, "Could not decode Herdr JSON response: " .. tostring(decoded)
  end

  return decoded, nil
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
  if vim.env.TMUX and vim.env.TMUX ~= "" then
    return "tmux"
  end

  if vim.env.HERDR_ENV == "1" then
    return "herdr"
  end

  return "na"
end

function M.refresh()
  local bufnr = vim.api.nvim_get_current_buf()
  local language = M.detect_language(bufnr)
  local multiplexer = M.detect_multiplexer()

  vim.g.focus_context_language = language
  vim.g.focus_context_multiplexer = multiplexer

  vim.api.nvim_buf_set_var(bufnr, "focus_context_language", language)

  return {
    language = language,
    multiplexer = multiplexer,
  }
end

function M.create_herdr_python_tab(opts)
  opts = opts or {}

  local context = M.refresh()

  if context.multiplexer ~= "herdr" then
    return nil, "Not running inside a Herdr pane"
  end

  if context.language ~= "python" then
    return nil, "Current buffer is not a Python file"
  end

  local workspace_id = vim.env.HERDR_WORKSPACE_ID

  if not workspace_id or workspace_id == "" then
    return nil, "HERDR_WORKSPACE_ID is not available in Neovim"
  end

  if vim.fn.executable("herdr") ~= 1 then
    return nil, "`herdr` executable was not found in Neovim's PATH"
  end

  local cwd = opts.cwd or vim.fn.getcwd()
  local label = opts.label or "fcOut"
  local focus = opts.focus == true

  local command = {
    "herdr",
    "tab",
    "create",
    "--workspace",
    workspace_id,
    "--cwd",
    cwd,
    "--label",
    label,
  }

  if focus then
    table.insert(command, "--focus")
  else
    table.insert(command, "--no-focus")
  end

  local output, system_error = run_system(command)

  if not output then
    return nil, "Herdr could not create a tab: " .. system_error
  end

  local response, json_error = decode_json(output)

  if not response then
    return nil, json_error
  end

  local tab = response.result and response.result.tab
  local root_pane = response.result and response.result.root_pane

  local tab_id = tab and tab.tab_id
  local pane_id = root_pane and root_pane.pane_id

  if not tab_id then
    return nil, "Herdr created a tab but returned no `result.tab.tab_id`"
  end

  if not pane_id then
    return nil, "Herdr created a tab but returned no `result.root_pane.pane_id`"
  end

  M.state.herdr_fc_out_tab_id = tab_id
  M.state.herdr_fc_out_pane_id = pane_id
  M.state.herdr_fc_out_cwd = cwd

  return {
    tab_id = tab_id,
    pane_id = pane_id,
    cwd = cwd,
  }, nil
end

function M.ipyoutinit()
  local context = M.refresh()

  if context.multiplexer ~= "herdr" then
    return nil, "Not running inside a Herdr pane"
  end

  if context.language ~= "python" then
    return nil, "Current buffer is not a Python file"
  end

  local pane_id = M.state.herdr_fc_out_pane_id
  local cwd = M.state.herdr_fc_out_cwd

  if not pane_id or pane_id == "" then
    return nil, "No fcOut pane is registered. Create one first."
  end

  if not cwd or cwd == "" then
    return nil, "No working directory is saved for fcOut."
  end

  if vim.fn.executable("herdr") ~= 1 then
    return nil, "`herdr` executable was not found in Neovim's PATH"
  end

  local _, get_error = run_system({
    "herdr",
    "pane",
    "get",
    pane_id,
  })

  if get_error then
    M.state.herdr_fc_out_tab_id = nil
    M.state.herdr_fc_out_pane_id = nil
    M.state.herdr_fc_out_cwd = nil

    return nil,
      "The saved fcOut pane no longer exists; saved state was cleared. "
        .. get_error
  end

  local activate_script = cwd .. "/.venv/bin/activate"

  if vim.fn.filereadable(activate_script) ~= 1 then
    return nil, "Could not find virtual environment activation script: " .. activate_script
  end

  local ipython_command = "source "
    .. vim.fn.shellescape(activate_script)
    .. " && exec ipython"

  local _, run_error = run_system({
    "herdr",
    "pane",
    "run",
    pane_id,
    ipython_command,
  })

  if run_error then
    return nil, "Could not start IPython in fcOut: " .. run_error
  end

  return pane_id, nil
end

function M.run_current_python_in_fc_out()
  local context = M.refresh()

  if context.multiplexer ~= "herdr" then
    return nil, "Not running inside a Herdr pane"
  end

  if context.language ~= "python" then
    return nil, "Current buffer is not a Python file"
  end

  local pane_id = M.state.herdr_fc_out_pane_id
  local cwd = M.state.herdr_fc_out_cwd
  local filename = vim.api.nvim_buf_get_name(0)

  if not pane_id or pane_id == "" then
    return nil, "No fcOut pane is registered. Create one first."
  end

  if not cwd or cwd == "" then
    return nil, "No working directory is saved for fcOut."
  end

  if filename == "" then
    return nil, "Current Python buffer has no file name. Save it first."
  end

  if vim.fn.filereadable(filename) ~= 1 then
    return nil, "Current Python file does not exist on disk: " .. filename
  end

  if vim.fn.executable("herdr") ~= 1 then
    return nil, "`herdr` executable was not found in Neovim's PATH"
  end

  local _, get_error = run_system({
    "herdr",
    "pane",
    "get",
    pane_id,
  })

  if get_error then
    M.state.herdr_fc_out_tab_id = nil
    M.state.herdr_fc_out_pane_id = nil
    M.state.herdr_fc_out_cwd = nil

    return nil,
      "The saved fcOut pane no longer exists; saved state was cleared. "
        .. get_error
  end

  local activate_script = cwd .. "/.venv/bin/activate"

  if vim.fn.filereadable(activate_script) ~= 1 then
    return nil, "Could not find virtual environment activation script: " .. activate_script
  end

  local run_command = "source "
    .. vim.fn.shellescape(activate_script)
    .. " && python "
    .. vim.fn.shellescape(filename)

  local _, run_error = run_system({
    "herdr",
    "pane",
    "run",
    pane_id,
    run_command,
  })

  if run_error then
    return nil, "Could not run the current Python file in fcOut: " .. run_error
  end

  return pane_id, nil
end

function M.setup(opts)
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
    desc = "Refresh focus context state",
    callback = function()
      M.refresh()
    end,
  })

  vim.api.nvim_create_user_command("FocusContextRefresh", function()
    M.refresh()
  end, {
    desc = "Refresh focus context state",
  })

  vim.api.nvim_create_user_command("FocusContextHerdrPythonTab", function(command_opts)
    local result, err = M.create_herdr_python_tab({
      label = command_opts.args ~= "" and command_opts.args or "fcOut",
      focus = command_opts.bang,
    })

    if not result then
      vim.notify(err, vim.log.levels.ERROR)
      return
    end

    vim.notify(
      "Created Herdr fcOut tab: " .. result.tab_id
        .. " (pane: " .. result.pane_id .. ")",
      vim.log.levels.INFO
    )
  end, {
    bang = true,
    nargs = "?",
    desc = "Create a Herdr fcOut tab for the current Python buffer",
  })

  vim.api.nvim_create_user_command("FocusContextIpyOutInit", function()
    local pane_id, err = M.ipyoutinit()

    if not pane_id then
      vim.notify(err, vim.log.levels.WARN)
      return
    end

    vim.notify(
      "Activated .venv and started IPython in fcOut pane: " .. pane_id,
      vim.log.levels.INFO
    )
  end, {
    desc = "Activate .venv and start IPython in the saved Herdr fcOut pane",
  })

  vim.api.nvim_create_user_command("FocusContextRunPythonInFcOut", function()
    local pane_id, err = M.run_current_python_in_fc_out()

    if not pane_id then
      vim.notify(err, vim.log.levels.WARN)
      return
    end

    vim.notify(
      "Running current Python file in fcOut pane: " .. pane_id,
      vim.log.levels.INFO
    )
  end, {
    desc = "Run the current Python file in the saved Herdr fcOut pane",
  })

  M.refresh()
end

return M
