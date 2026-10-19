describe("ActivityWatch curl requests", function()
  local original_spawn
  local original_new_pipe
  local client
  local requests

  before_each(function()
    package.loaded["activity_watch.client"] = nil
    client = require("activity_watch.client")
    requests = {}
    original_spawn = vim.uv.spawn
    original_new_pipe = vim.uv.new_pipe
    vim.uv.new_pipe = function()
      return {
        read_start = function(_, callback)
          callback(nil, "200")
        end,
        is_closing = function()
          return false
        end,
        close = function() end,
      }
    end
    vim.uv.spawn = function(command, options)
      table.insert(requests, { command = command, args = options.args })
      return {
        is_closing = function()
          return false
        end,
        close = function() end,
      }
    end
  end)

  after_each(function()
    vim.uv.spawn = original_spawn
    vim.uv.new_pipe = original_new_pipe
  end)

  it("uses an explicit POST method without treating POST as another URL", function()
    local connection = client.new({
      hostname = "test-host",
      bucket_name = "test-bucket",
      host = "127.0.0.1",
      port = 5600,
      ssl = false,
      pulsetime = 30,
    })
    client.create_bucket(connection)
    client.heartbeat(connection, { file = "/tmp/example.lua", language = "lua" })

    assert.equals(2, #requests)
    for index, url in ipairs({ connection.bucket_url, connection.heartbeat_url }) do
      local request = requests[index]
      assert.equals("curl", request.command)
      assert.are.same({ "-X", "POST", url }, vim.list_slice(request.args, 1, 3))
    end
  end)
end)
