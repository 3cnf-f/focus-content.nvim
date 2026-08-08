
if vim.g.loaded_focus_context == 1 then
  return
end

vim.g.loaded_focus_context = 1

require("focus_context").setup()
