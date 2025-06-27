local M = {}

local session_manager = require("rittli.core.session_manager")
local task_manager = require("rittli.core.task_manager")
local config = require("rittli.config").config

---@param task Task
local function launch_task(task)
  local connection = session_manager.find_connection(task.name)
  if connection then
    task:rerun(connection.terminal_handler)
    connection.terminal_handler.focus()
  else
    local res = task:launch(config.terminal_provider)
    if not res.is_success then
      vim.notify(string.format("ABORT: %s", res.error_msg), vim.log.levels.ERROR)
      Snacks.picker.resume() -- Resume the picker
      return
    end
    session_manager.register_connection(task.name, res.terminal_handler)
  end
end

---@param opts? table
---@param task_to_launch Task
local terminal_handlers_picker = function(opts, task_to_launch)
  opts = opts or {}
  local terminals = session_manager.get_all_terminal_handlers()

  --- @class snacks.picker.Config
  local picker_config = {
    title = "Select a terminal window/pane to launch the task",
    finder = function()
      local items = {}
      for _, handler in ipairs(terminals) do
        items[#items + 1] = {
          text = handler.get_name(),
          pane_id = handler.get_info_to_reattach(),
          is_alive = handler.is_alive(),
          item = handler,
        }
      end
      return items
    end,
    format = function(item)
      return {
        { item.text },
      }
    end,
    layout = "dropdown",
    preview = function(ctx)
      local pre = ctx.preview --- @type snacks.picker.Preview
      local hanlder = ctx.item.item
      pre:set_title("Terminal Preview")
      pre:reset()
      pre:set_lines(hanlder.get_text())
      pre:highlight({ ft = "bash" })
    end,
    actions = {
      confirm = function(picker)
        local selections = picker:selected({ fallback = true })
        if #selections > 1 then
          vim.notify("Cannot select more than 1 pane to attach", vim.log.levels.ERROR)
          return
        end
        picker:close()
        local handler = selections[1].item
        session_manager.register_connection(task_to_launch.name, handler)
        launch_task(task_to_launch)
        handler.focus()
        vim.notify("[" .. task_to_launch.name .. "] launched in " .. handler.get_name())
      end,
    },
  }

  Snacks.picker.pick(picker_config)
end

local reuse_as_template = function(entry)
  if #entry > 1 then
    vim.notify("Cannot select more than one task to reuse as template", vim.log.levels.ERROR)
    return
  end

  entry = entry[1]

  local path_to_folder_with_tasks = string.format("%s/%s/", vim.uv.cwd(), config.folder_name_with_tasks)
  if vim.fn.isdirectory(path_to_folder_with_tasks) == 0 then
    vim.fn.mkdir(path_to_folder_with_tasks)
  end

  local template_name = vim.fn.input({ prompt = "Enter template name: " })
  local copy_to = path_to_folder_with_tasks .. template_name .. ".lua"
  if vim.fn.filereadable(copy_to) == 1 then
    vim.notify("ABORT: File with this name already exists!", vim.log.levels.ERROR)
    return
  end

  vim.uv.fs_copyfile(entry.file, copy_to)
  vim.schedule(function()
    vim.cmd("edit " .. vim.fn.fnameescape(copy_to))
    vim.cmd(entry.task_begin_line_number)
  end)
end

local launch_the_picked_tasks = function(entries)
  if not entries then
    return
  end

  for _, entry in ipairs(entries) do
    ---@type Task
    local task = entry.item
    launch_task(task)
  end
end

local attach_to_terminal_handler_and_launch = function(entries)
  if #entries > 1 then
    vim.notify("Cannot select more than 1 task for attaching", vim.log.levels.ERROR)
    return
  end

  terminal_handlers_picker({}, entries[1].item)
end

--- @class snacks.picker.Config
M.picker_config = {
  title = "Select task to launch",
  items = tasks,
  finder = function()
    local items = {}
    local tasks = task_manager.collect_tasks()
    for _, task in ipairs(tasks) do
      -- TODO: the task_begin_line_number does not work with local tasks
      items[#items + 1] = {
        text = task.name,
        file = task.task_source_file_path,
        pos = { task.task_begin_line_number, 0 },
        item = task,
      }
    end
    return items
  end,
  format = function(item)
    local task_name = item.text
    local connection = session_manager.find_connection(task_name)
    local pane_id = ""
    if connection then
      pane_id = connection.terminal_handler.get_info_to_reattach()
    end
    local utils = require("snacks.picker.util")
    task_name = utils.align(task_name .. "     ", 60, { align = "left", truncate = true })

    return {
      { utils.align(pane_id, 4), "SnacksPickerPathHidden", virtual = true },
      { task_name },
    }
  end,
  matcher = {
    fuzzy = true,
    smartcase = true,
  },
  layout = "dropdown",
  preview = function(ctx)
    ctx.preview:reset()
    local path = ctx.item.file
    local lines = { "⚠️ File not found: " .. path }
    if vim.fn.filereadable(path) == 1 then
      lines = vim.fn.readfile(path)
    end
    ctx.preview:set_lines(lines)
    ctx.preview:set_title("Task Preview")
    ctx.preview:highlight({ ft = "lua" })
    ctx.preview:loc()
    ctx.preview:wo({ cursorline = true })
  end,
  win = {
    input = {
      keys = {
        ["<c-e>"] = { "reuse_as_template", mode = { "n", "i" } },
        ["<c-r>"] = { "attach_to_existing_terminal", mode = { "n", "i" } },
      },
    },
  },
  actions = {
    confirm = function(picker)
      picker:close()
      launch_the_picked_tasks(picker:selected({ fallback = true }))
    end,
    reuse_as_template = function(picker)
      picker:close()
      reuse_as_template(picker:selected({ fallback = true }))
    end,
    attach_to_existing_terminal = function(picker)
      picker:close()
      attach_to_terminal_handler_and_launch(picker:selected({ fallback = true }))
    end,
  },
  on_show = function(picker)
    local last_runned = session_manager.get_last_runned_task_name()
    if not last_runned then
      return
    end
    for i, item in ipairs(picker:items()) do
      if item.text == last_runned then
        picker.list:view(i)
        Snacks.picker.actions.list_scroll_center(picker)
        break
      end
    end
  end,
}

---@param opts? table
M.pick = function(opts)
  if Snacks == nil then
    return
  end

  opts = opts or {}

  Snacks.picker.pick("rittli", opts)
end

return M
