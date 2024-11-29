local M = {}

local finders = require("telescope.finders")
local pickers = require("telescope.pickers")
local previewers = require("telescope.previewers")
local actions = require("telescope.actions")
local session_manager = require("rittli.core.session_manager")
local action_state = require("telescope.actions.state")
local conf = require("telescope.config").values

---@param task_to_launch Task
M.terminal_handlers_picker = function(opts, task_to_launch)
  opts = {}
  local picker = pickers.new(opts, {
    prompt_title = "SelectTerminalToLaunchTask",
    finder = finders.new_table({
      results = session_manager.get_all_lonely_terminal_handlers(),
      ---@param handler ITerminalHandler
      entry_maker = function(handler)
        local name = handler.get_name()
        return {
          value = handler,
          display = name,
          ordinal = name,
        }
      end,
    }),
    previewer = previewers.new_buffer_previewer({
      title = "TerminalPreview",
      define_preview = function(self, entry, status)
        local handler = entry.value
        local text = handler.get_text()
        vim.bo[self.state.bufnr].filetype = "bash"
        vim.api.nvim_buf_set_lines(self.state.bufnr, 0, -1, false, text)
      end,
    }),
    sorter = conf.generic_sorter(opts),
    attach_mappings = function(prompt_bufnr, map)
      map({ "i", "n" }, "<Enter>", function()
        local selection = action_state.get_selected_entry()
        if not selection or not selection.value.focus then
          return
        end
        session_manager.register_connection(task_to_launch.name, selection.value)
        actions.close(prompt_bufnr)
        M.launch_task(task_to_launch)
      end)
      return true
    end,
  })
  picker:find()
end

return M
