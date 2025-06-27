local config = require("rittli.config").config
local neovim_terminal_provider = config.conveniences.terminal_provider
local session_manager = require("rittli.core.session_manager")
local utils = require("rittli.utils")

local M = {}

---@class TerminalEnterInfo
---@field bufnr number
---@field winid number
---@field window_config vim.api.keyset.win_config
---@field windows_in_the_tab number[]

---@type TerminalEnterInfo[]
local terminals_enters_stack = {}

local function keep_pop_until_find_existing_terminal()
  while #terminals_enters_stack ~= 0 do
    local enter_info = terminals_enters_stack[#terminals_enters_stack]
    if vim.api.nvim_buf_is_valid(enter_info.bufnr) then
      return
    end
    table.remove(terminals_enters_stack)
  end
end

local function register_terminal_enter()
  ---@type TerminalEnterInfo
  local enter_info = {
    winid = vim.fn.win_getid(),
    bufnr = vim.fn.bufnr("%"),
    windows_in_the_tab = utils.get_all_windows_in_cur_tabpage(),
    window_config = vim.api.nvim_win_get_config(0),
  }
  table.insert(terminals_enters_stack, enter_info)
end

-- TODO: move this elsewhere since this only concerns nvim terminals
local current_pane_id = nil
local previous_pane_id = nil
function M.toggle_last_openned_terminal_wezterm()
  local focused_now = utils.rm_endline(os.getenv("WEZTERM_PANE"))

  if not previous_pane_id then
    -- First time toggling: track current, then switch to session pane
    local last_runned = session_manager.get_last_runned_task_name()
    if not last_runned then
      vim.notify("No terminal tracked by Rittli")
      return
    end
    local connection = session_manager.find_connection(last_runned)
    if connection then
      current_pane_id = focused_now
      previous_pane_id = connection.terminal_handler.get_info_to_reattach()
      connection.terminal_handler.focus()
    end
  else
    -- Toggle between the two panes
    local target_pane_id
    if focused_now == current_pane_id then
      -- Currently on original pane, switch to terminal
      target_pane_id = previous_pane_id
    else
      -- Currently on terminal pane, switch back to original
      target_pane_id = current_pane_id
    end

    vim.system({ "wezterm", "cli", "activate-pane", "--pane-id", target_pane_id }):wait()
  end
end

function M.toggle_last_openned_terminal()
  keep_pop_until_find_existing_terminal()
  if #terminals_enters_stack == 0 then
    neovim_terminal_provider.create({})
    return
  end

  local last_enter_info = terminals_enters_stack[#terminals_enters_stack]

  -- Case when the terminal is currently focused
  if last_enter_info.winid == vim.fn.win_getid() then
    vim.api.nvim_command("silent! hide")
    return
  end

  -- Case when the terminal is not currently focused (Buffer exists and window does not)
  if vim.api.nvim_win_is_valid(last_enter_info.winid) then
    vim.fn.win_gotoid(last_enter_info.winid)
  else
    -- HACK: We need this hack because window_config can't restore window properly if it was opened in a new tab
    if #last_enter_info.windows_in_the_tab == 1 and last_enter_info.windows_in_the_tab[1] == last_enter_info.winid then
      vim.cmd("tabnew")
      local tab_bufnr = vim.fn.bufnr("%")
      vim.api.nvim_command("b " .. last_enter_info.bufnr)
      vim.api.nvim_buf_delete(tab_bufnr, {})
    else
      vim.api.nvim_open_win(last_enter_info.bufnr, true, last_enter_info.window_config)
    end
  end
end

vim.api.nvim_create_autocmd("TermOpen", {
  callback = function()
    if not config.conveniences.should_register_terminal_enter() then
      return
    end
    vim.api.nvim_command("set ft=terminal")
    -- Doesn't work without vim.schedule properly
    -- I definitely should read about main event-loop somewhere
    -- https://en.wikipedia.org/wiki/Event_loop
    -- :help event-loop
    if config.conveniences.auto_insert then
      vim.schedule(function()
        vim.api.nvim_command("startinsert")
      end)
    end
    vim.api.nvim_command("setlocal nonumber norelativenumber signcolumn=no")
    register_terminal_enter()
  end,
})

vim.api.nvim_create_autocmd({ "BufEnter", "BufWinEnter" }, {
  group = vim.api.nvim_create_augroup("TerminalEnterRegistrator", { clear = true }),
  callback = function()
    if vim.bo.filetype == "terminal" and config.conveniences.should_register_terminal_enter() then
      if config.conveniences.auto_insert then
        vim.schedule(function()
          vim.api.nvim_command("startinsert")
        end)
      end
      register_terminal_enter()
    end
  end,
})

vim.api.nvim_create_autocmd("SessionLoadPost", {
  group = vim.api.nvim_create_augroup("RegisterAllOpennedTerminalsIfSessionIsRestored", { clear = true }),
  callback = function()
    for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
      local buf_name = vim.api.nvim_buf_get_name(bufnr)
      if string.sub(buf_name, 1, 7) == "term://" then
        vim.api.nvim_command("set ft=terminal")
        vim.api.nvim_command("setlocal nonumber norelativenumber signcolumn=no")
        register_terminal_enter()
      end
    end
  end,
})

return M
