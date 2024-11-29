-- This module contains and export convinient functions / templates, what user can use when creating tasks

local M = {}

---@param command string
M.single = function(command) local res = function()
    vim.cmd("wall")
    return {
      cmd = {
        command,
      },
    }
  end
  return res
end

---@param command string
M.run_cur = function(command)
  local res = function()
    vim.cmd("wall")
    local file_name = vim.fn.expand("%")
    return {
      cmd = {
        string.format("%s %s", command, file_name),
      },
    }
  end
  return res
end

return M
