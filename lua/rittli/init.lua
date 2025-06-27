local M = {}

local config = require("rittli.config")

---@param opts Rittli.config
function M.setup(opts)
  config.config = vim.tbl_deep_extend("force", {}, config.config, opts or {})
  require("rittli.core")

  if config.config.picker == "snacks" and Snacks then
    Snacks.picker.sources.rittli = require("rittli.core.snacks").picker_config
  elseif config.config.picker == "telescope" then
    vim.notify("Telescope is not configured, need to call require('rittli.core.telescope').task_picker() directly")
  end

  if config.config.conveniences.enable then
    require("rittli.conveniences.tab_tweaks")
    require("rittli.conveniences.terminal_tweaks")
  end
end

return M
