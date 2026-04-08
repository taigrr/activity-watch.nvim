---@brief [[
--- activity-watch.nvim health check
--- Run with :checkhealth activity_watch
---@brief ]]

local M = {}

function M.check()
  vim.health.start("activity-watch.nvim")

  -- Check Neovim version
  if vim.fn.has("nvim-0.9") == 1 then
    vim.health.ok("Neovim >= 0.9")
  else
    vim.health.error("Neovim >= 0.9 required", { "Upgrade Neovim to 0.9 or later" })
  end

  -- Check curl (required)
  if vim.fn.executable("curl") == 1 then
    vim.health.ok("curl found")
  else
    vim.health.error("curl not found", {
      "curl is required for communicating with ActivityWatch",
      "Install curl via your package manager",
    })
  end

  -- Check git (optional, for branch tracking)
  if vim.fn.executable("git") == 1 then
    vim.health.ok("git found (branch tracking enabled)")
  else
    vim.health.info("git not found (branch tracking disabled)")
  end

  -- Check plugin state
  local aw = require("activity_watch")
  if not aw._client then
    vim.health.warn("Plugin not initialized", {
      "Call require('activity_watch').setup({}) in your config",
    })
    return
  end

  -- Check if paused
  if not aw._enabled then
    vim.health.info("Tracking is paused. Run :AWStart to resume.")
  end

  -- Check connection
  if aw._client.connected then
    vim.health.ok("Connected to ActivityWatch server")
    vim.health.info("  Bucket: " .. aw._client.bucket_name)
  else
    vim.health.warn("Not connected to ActivityWatch server", {
      "Ensure ActivityWatch is running",
      "Check server settings: host=" .. aw.config.server.host .. ", port=" .. aw.config.server.port,
      "Run :AWStart to reconnect",
    })
  end

  -- Show current tracking info
  if aw._project then
    vim.health.info("  Project: " .. aw._project)
  end
  if aw._branch then
    vim.health.info("  Branch: " .. aw._branch)
  end
end

return M
