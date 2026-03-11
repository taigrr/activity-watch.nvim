---@brief [[
--- activity-watch.nvim tests
--- Run with: nvim --headless -c "PlenaryBustedDirectory tests/ { minimal_init = 'tests/minimal_init.lua' }"
---@brief ]]

describe("activity_watch", function()
  local aw

  before_each(function()
    package.loaded["activity_watch"] = nil
    package.loaded["activity_watch.client"] = nil
    aw = require("activity_watch")
  end)

  describe("config", function()
    it("has default config values", function()
      assert.is_table(aw.config)
      assert.is_table(aw.config.bucket)
      assert.is_table(aw.config.server)
      assert.equals("127.0.0.1", aw.config.server.host)
      assert.equals(5600, aw.config.server.port)
      assert.equals(false, aw.config.server.ssl)
      assert.equals(30, aw.config.server.pulsetime)
    end)

    it("merges user config with defaults", function()
      aw.setup({
        server = {
          port = 5601,
        },
      })

      assert.equals(5601, aw.config.server.port)
      assert.equals("127.0.0.1", aw.config.server.host)
      assert.equals(false, aw.config.server.ssl)
    end)

    it("allows custom bucket name", function()
      aw.setup({
        bucket = {
          name = "custom-bucket",
        },
      })

      assert.is_not_nil(aw._client)
      assert.equals("custom-bucket", aw._client.bucket_name)
    end)
  end)

  describe("status", function()
    it("returns 'not initialized' before setup", function()
      assert.equals("not initialized", aw.status())
    end)

    it("returns 'disconnected' after setup (no server)", function()
      aw.setup({})
      assert.equals("disconnected", aw.status())
    end)
  end)

  describe("is_connected", function()
    it("returns false before setup", function()
      assert.is_false(aw.is_connected())
    end)

    it("returns false after setup (no server)", function()
      aw.setup({})
      assert.is_false(aw.is_connected())
    end)
  end)

  describe("heartbeat", function()
    it("does nothing when not initialized", function()
      assert.has_no.errors(function()
        aw.heartbeat()
      end)
    end)

    it("respects minimum interval", function()
      aw.setup({})
      aw._client.connected = true
      aw._last_heartbeat = vim.uv.now()

      local initial = aw._last_heartbeat
      aw.heartbeat()
      assert.equals(initial, aw._last_heartbeat)
    end)
  end)
end)

describe("activity_watch.client", function()
  local client

  before_each(function()
    package.loaded["activity_watch.client"] = nil
    client = require("activity_watch.client")
  end)

  describe("new", function()
    it("creates client with correct URLs", function()
      local c = client.new({
        hostname = "test-host",
        bucket_name = "test-bucket",
        host = "127.0.0.1",
        port = 5600,
        ssl = false,
        pulsetime = 30,
      })

      assert.equals("test-host", c.hostname)
      assert.equals("test-bucket", c.bucket_name)
      assert.equals("http://127.0.0.1:5600/api/0/buckets/test-bucket", c.bucket_url)
      assert.equals("http://127.0.0.1:5600/api/0/buckets/test-bucket/heartbeat?pulsetime=30", c.heartbeat_url)
      assert.is_false(c.connected)
    end)

    it("uses https when ssl is true", function()
      local c = client.new({
        hostname = "test-host",
        bucket_name = "test-bucket",
        host = "127.0.0.1",
        port = 5600,
        ssl = true,
        pulsetime = 30,
      })

      assert.truthy(c.bucket_url:match("^https://"))
    end)

    it("uses custom port", function()
      local c = client.new({
        hostname = "test-host",
        bucket_name = "test-bucket",
        host = "127.0.0.1",
        port = 5601,
        ssl = false,
        pulsetime = 30,
      })

      assert.truthy(c.bucket_url:match(":5601/"))
    end)
  end)
end)

describe("activity_watch.health", function()
  local health

  before_each(function()
    package.loaded["activity_watch.health"] = nil
    health = require("activity_watch.health")
  end)

  it("exports check function", function()
    assert.is_function(health.check)
  end)
end)
