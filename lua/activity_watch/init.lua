---@brief [[
--- activity-watch.nvim - ActivityWatch integration for Neovim
---
--- Track your coding activity with ActivityWatch time tracker.
--- Automatically reports file, project, branch, and language information.
---
--- Usage:
---   require("activity_watch").setup({})
---@brief ]]

local M = {}

---@class AWBucketConfig
---@field hostname? string Hostname for the bucket (default: system hostname)
---@field name? string Bucket name (default: "aw-watcher-neovim_" .. hostname)

---@class AWServerConfig
---@field host? string ActivityWatch server host (default: "127.0.0.1")
---@field port? number ActivityWatch server port (default: 5600)
---@field ssl? boolean Use HTTPS (default: false)
---@field pulsetime? number Heartbeat pulse time in seconds (default: 30)

---@class AWConfig
---@field bucket? AWBucketConfig Bucket configuration
---@field server? AWServerConfig Server configuration

---@type AWConfig
M.config = {
  bucket = {
    hostname = nil,
    name = nil,
  },
  server = {
    host = "127.0.0.1",
    port = 5600,
    ssl = false,
    pulsetime = 30,
  },
}

---@type table?
M._client = nil

---@type string?
M._branch = nil

---@type string?
M._project = nil

---@type number
M._last_heartbeat = 0

---@type boolean
M._enabled = true

local HEARTBEAT_INTERVAL_MS = 8000

---@private
---Find git root directory from current buffer
---@return string?
local function find_git_root()
  local path = vim.api.nvim_buf_get_name(0)
  if path == "" then
    return nil
  end

  local git_dir = vim.fs.find(".git", {
    path = vim.fs.dirname(path),
    upward = true,
    type = "file",
  })[1]
  if git_dir then
    return vim.fs.dirname(git_dir)
  end

  git_dir = vim.fs.find(".git", {
    path = vim.fs.dirname(path),
    upward = true,
    type = "directory",
  })[1]
  if git_dir then
    return vim.fs.dirname(git_dir)
  end

  return nil
end

---@private
---Update cached branch name (async)
---@param git_root string?
local function update_branch(git_root)
  local stdout = vim.uv.new_pipe()
  local handle, err = vim.uv.spawn("git", {
    args = { "rev-parse", "--abbrev-ref", "HEAD" },
    cwd = git_root,
    stdio = { nil, stdout, nil },
  }, function(code)
    if stdout and not stdout:is_closing() then
      stdout:close()
    end
  end)

  if not handle then
    M._branch = nil
    if stdout and not stdout:is_closing() then
      stdout:close()
    end
    return
  end

  local output = ""
  stdout:read_start(function(read_err, chunk)
    if chunk then
      output = output .. chunk
    else
      local branch = output:gsub("%s+$", "")
      vim.schedule(function()
        M._branch = (branch ~= "" and not branch:match("^fatal")) and branch or nil
      end)
    end
  end)
end

---@private
---Update cached project name
---@param git_root string?
local function update_project(git_root)
  local project_dir = git_root or vim.fn.getcwd()
  M._project = vim.fs.basename(vim.fs.normalize(project_dir))
end

---@private
local function update_context()
  local git_root = find_git_root()
  update_branch(git_root)
  update_project(git_root)
end

---Send a heartbeat to the ActivityWatch server.
function M.heartbeat()
  if not M._client or not M._enabled then
    return
  end

  local now = vim.uv.now()
  if now - M._last_heartbeat < HEARTBEAT_INTERVAL_MS then
    return
  end
  M._last_heartbeat = now

  local client = require("activity_watch.client")
  client.heartbeat(M._client, {
    file = vim.fn.expand("%:p"),
    project = M._project,
    branch = M._branch,
    language = vim.bo.filetype,
  })
end

---Create or reconnect the bucket.
function M.start()
  if not M._client then
    vim.notify("[activity-watch] Not initialized. Call setup() first.", vim.log.levels.WARN)
    return
  end
  M._enabled = true
  local client = require("activity_watch.client")
  client.create_bucket(M._client)
end

---Stop tracking activity. Pauses heartbeats until :AWStart.
function M.stop()
  M._enabled = false
  if M._client then
    M._client.connected = false
  end
end

---Check connection status.
---@return boolean
function M.is_connected()
  return M._client and M._client.connected or false
end

---Get current status message.
---@return string
function M.status()
  if not M._client then
    return "not initialized"
  end
  if not M._enabled then
    return "paused"
  end
  return M._client.connected and "connected" or "disconnected"
end

---@private
local function create_autocommands()
  local group = vim.api.nvim_create_augroup("ActivityWatch", { clear = true })

  -- Heartbeat triggers (deferred to avoid startup lag)
  vim.defer_fn(function()
    vim.api.nvim_create_autocmd({
      "CursorMoved",
      "CursorMovedI",
      "BufEnter",
      "BufLeave",
      "CmdlineEnter",
      "CmdlineChanged",
    }, {
      group = group,
      callback = M.heartbeat,
    })
  end, 1000)

  -- Update git info on buffer/focus changes
  vim.api.nvim_create_autocmd({ "BufEnter", "FocusGained", "FileType" }, {
    group = group,
    callback = function()
      update_context()
    end,
  })

  -- Create bucket on VimEnter
  vim.api.nvim_create_autocmd("VimEnter", {
    group = group,
    callback = M.start,
  })
end

---@private
local function create_commands()
  vim.api.nvim_create_user_command("AWStart", M.start, {
    desc = "Connect to ActivityWatch server",
  })

  vim.api.nvim_create_user_command("AWStatus", function()
    vim.notify("[activity-watch] " .. M.status(), vim.log.levels.INFO)
  end, {
    desc = "Show ActivityWatch connection status",
  })

  vim.api.nvim_create_user_command("AWStop", function()
    M.stop()
    vim.notify("[activity-watch] Tracking paused. Use :AWStart to resume.", vim.log.levels.INFO)
  end, {
    desc = "Pause ActivityWatch tracking",
  })

  vim.api.nvim_create_user_command("AWHeartbeat", M.heartbeat, {
    desc = "Send manual heartbeat to ActivityWatch",
  })
end

---Initialize the plugin.
---@param opts? AWConfig
function M.setup(opts)
  M.config = vim.tbl_deep_extend("force", M.config, opts or {})

  -- Resolve hostname
  local hostname = M.config.bucket.hostname or vim.uv.os_gethostname()
  local bucket_name = M.config.bucket.name or ("aw-watcher-neovim_" .. hostname)

  -- Create client
  local client = require("activity_watch.client")
  M._client = client.new({
    hostname = hostname,
    bucket_name = bucket_name,
    host = M.config.server.host,
    port = M.config.server.port,
    ssl = M.config.server.ssl,
    pulsetime = M.config.server.pulsetime,
  })

  -- Initial git info
  update_context()

  -- Create bucket
  client.create_bucket(M._client)

  create_commands()
  create_autocommands()
end

return M
