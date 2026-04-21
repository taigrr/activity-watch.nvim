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

  describe("stop", function()
    it("pauses heartbeats", function()
      aw.setup({})
      aw.stop()
      assert.is_false(aw._enabled)
      assert.equals("paused", aw.status())
    end)

    it("start resumes after stop", function()
      aw.setup({})
      aw.stop()
      assert.equals("paused", aw.status())
      -- start() reconnects and re-enables
      aw._enabled = true
      assert.is_true(aw._enabled)
    end)
  end)

  describe("git context", function()
    it("runs branch detection from the current buffer git root", function()
      local client = require("activity_watch.client")
      local original_create_bucket = client.create_bucket
      local original_spawn = vim.uv.spawn
      local original_new_pipe = vim.uv.new_pipe
      local temp_root = vim.fn.tempname()
      local repo_root = temp_root .. "/worktree-repo"
      local file_path = repo_root .. "/lua/example.lua"
      local spawn_cwds = {}

      vim.fn.mkdir(repo_root .. "/lua", "p")
      vim.fn.writefile({ "gitdir: /tmp/fake-worktree" }, repo_root .. "/.git")
      vim.fn.writefile({ "print('hi')" }, file_path)
      vim.cmd.edit(file_path)

      client.create_bucket = function(_) end
      vim.uv.new_pipe = function()
        return {
          read_start = function(_, cb)
            cb(nil, "feature/test\n")
            cb(nil, nil)
          end,
          is_closing = function()
            return false
          end,
          close = function() end,
        }
      end
      vim.uv.spawn = function(cmd, opts, on_exit)
        if cmd == "git" then
          table.insert(spawn_cwds, opts.cwd)
          if on_exit then
            on_exit(0)
          end
          return {
            is_closing = function()
              return false
            end,
            close = function() end,
          }
        end
        return original_spawn(cmd, opts, on_exit)
      end

      aw.setup({})
      vim.wait(100, function()
        return aw._branch == "feature/test"
      end)

      assert.are.same({ repo_root }, spawn_cwds)
      assert.equals("worktree-repo", aw._project)
      assert.equals("feature/test", aw._branch)

      vim.uv.spawn = original_spawn
      vim.uv.new_pipe = original_new_pipe
      client.create_bucket = original_create_bucket
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

    it("skips when paused", function()
      aw.setup({})
      aw._client.connected = true
      aw._last_heartbeat = 0
      aw._enabled = false

      aw.heartbeat()
      assert.equals(0, aw._last_heartbeat)
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

  describe("heartbeat", function()
    it("does nothing when not connected", function()
      local c = client.new({
        hostname = "test-host",
        bucket_name = "test-bucket",
        host = "127.0.0.1",
        port = 5600,
        ssl = false,
        pulsetime = 30,
      })

      assert.has_no.errors(function()
        client.heartbeat(c, {
          file = "/tmp/test.lua",
          project = "test",
          branch = "main",
          language = "lua",
        })
      end)
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
