describe("asynchronous branch context", function()
  local aw, client, original_pipe, original_spawn, original_bucket
  local reads, root, original_buffer

  before_each(function()
    package.loaded["activity_watch"] = nil
    aw = require("activity_watch")
    client = require("activity_watch.client")
    original_pipe = vim.uv.new_pipe
    original_spawn = vim.uv.spawn
    original_bucket = client.create_bucket
    original_buffer = vim.api.nvim_get_current_buf()
    reads = {}
    root = vim.fn.tempname()
    for _, name in ipairs({ "first", "second" }) do
      vim.fn.mkdir(root .. "/" .. name, "p")
      vim.fn.writefile({ "gitdir: /unused" }, root .. "/" .. name .. "/.git")
      vim.fn.writefile({}, root .. "/" .. name .. "/file.lua")
    end
    vim.fn.writefile({}, root .. "/notes.lua")
    client.create_bucket = function() end
    vim.uv.new_pipe = function()
      return {
        read_start = function(_, callback)
          table.insert(reads, callback)
        end,
        is_closing = function()
          return false
        end,
        close = function() end,
      }
    end
    vim.uv.spawn = function()
      return {
        is_closing = function()
          return false
        end,
        close = function() end,
      }
    end
    vim.cmd.edit(root .. "/first/file.lua")
    aw.setup({})
  end)

  after_each(function()
    vim.uv.new_pipe = original_pipe
    vim.uv.spawn = original_spawn
    client.create_bucket = original_bucket
    vim.api.nvim_clear_autocmds({ group = "ActivityWatch" })
    vim.api.nvim_set_current_buf(original_buffer)
    vim.fn.delete(root, "rf")
  end)

  local function complete(index, branch)
    reads[index](nil, branch .. "\n")
    reads[index](nil, nil)
    vim.wait(20, function()
      return false
    end)
  end

  it("ignores an older lookup that finishes after the new buffer lookup", function()
    vim.cmd.edit(root .. "/second/file.lua")
    complete(#reads, "second-branch")
    complete(1, "first-branch")
    assert.equals("second", aw._project)
    assert.equals("second-branch", aw._branch)
  end)

  it("does not restore an old branch after leaving git", function()
    vim.cmd.edit(root .. "/notes.lua")
    complete(1, "first-branch")
    assert.is_nil(aw._branch)
  end)

  it("clears the previous branch while the new lookup is pending", function()
    complete(1, "first-branch")
    assert.equals("first-branch", aw._branch)
    vim.cmd.edit(root .. "/second/file.lua")
    assert.is_nil(aw._branch)
  end)
end)
