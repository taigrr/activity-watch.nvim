---@brief [[
--- activity-watch.nvim HTTP client
--- Handles communication with ActivityWatch server via curl
---@brief ]]

local M = {}

---@private
local ERR_NOTIFY_INTERVAL_MS = 60000

---@class AWClient
---@field hostname string
---@field bucket_name string
---@field bucket_url string
---@field heartbeat_url string
---@field connected boolean
---@field last_error_notify number

---Build base URL for ActivityWatch API.
---@param ssl boolean
---@param host string
---@param port number
---@return string
local function make_base_url(ssl, host, port)
  local protocol = ssl and "https://" or "http://"
  return protocol .. host .. ":" .. port .. "/api/0"
end

---Create a new ActivityWatch client.
---@param opts { hostname: string, bucket_name: string, host: string, port: number, ssl: boolean, pulsetime: number }
---@return AWClient
function M.new(opts)
  local base_url = make_base_url(opts.ssl, opts.host, opts.port)
  local bucket_url = base_url .. "/buckets/" .. opts.bucket_name
  local heartbeat_url = bucket_url .. "/heartbeat?pulsetime=" .. opts.pulsetime

  return {
    hostname = opts.hostname,
    bucket_name = opts.bucket_name,
    bucket_url = bucket_url,
    heartbeat_url = heartbeat_url,
    connected = false,
    last_error_notify = 0,
  }
end

---@private
---Send POST request via curl (async).
---@param client AWClient
---@param url string
---@param data table
local function post(client, url, data)
  local body = vim.fn.json_encode(data)
  local args = {
    "POST",
    url,
    "-H",
    "Content-Type: application/json",
    "--data-raw",
    body,
    "-s",
    "-o",
    "/dev/null",
    "-w",
    "%{http_code}",
  }

  local handle
  local stdout = vim.uv.new_pipe()

  handle = vim.uv.spawn("curl", {
    args = args,
    stdio = { nil, stdout, nil },
  }, function(code)
    client.connected = code == 0

    if stdout then
      stdout:close()
    end
    if handle and not handle:is_closing() then
      handle:close()
    end
  end)

  if stdout then
    stdout:read_start(function(err, chunk)
      if not err and chunk then
        local status = tonumber(chunk:match("%d+"))
        client.connected = status and status >= 200 and status < 300
      end
    end)
  end
end

---Create the bucket on the ActivityWatch server.
---@param client AWClient
function M.create_bucket(client)
  local body = {
    name = client.bucket_name,
    hostname = client.hostname,
    client = "neovim-watcher",
    type = "app.editor.activity",
  }
  post(client, client.bucket_url, body)
end

---Send a heartbeat event.
---@param client AWClient
---@param data { file: string, project: string?, branch: string?, language: string }
function M.heartbeat(client, data)
  if not client.connected then
    local now = vim.uv.now()
    if now - client.last_error_notify > ERR_NOTIFY_INTERVAL_MS then
      vim.schedule(function()
        vim.notify("[activity-watch] Not connected. Use :AWStart to reconnect.", vim.log.levels.WARN)
      end)
      client.last_error_notify = now
    end
    return
  end

  local body = {
    timestamp = os.date("!%Y-%m-%dT%H:%M:%SZ"),
    duration = 0,
    data = {
      file = data.file or "",
      project = data.project or "",
      branch = data.branch or "",
      language = data.language or "",
    },
  }

  post(client, client.heartbeat_url, body)
end

return M
