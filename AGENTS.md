# AGENTS.md

AI agent guide for working in activity-watch.nvim.

## Project Overview

**activity-watch.nvim** is a Neovim plugin that integrates with [ActivityWatch](https://activitywatch.net/) time tracker. It automatically reports coding activity including files, projects, git branches, and languages.

- **Language**: Lua (Neovim plugin)
- **Requirements**: Neovim >= 0.9, curl, ActivityWatch running
- **Author**: Tai Groot (taigrr)

## Directory Structure

```
lua/activity_watch/
├── init.lua      # Main module: setup, config, API, autocommands
├── client.lua    # HTTP client: curl-based async requests to AW API
├── health.lua    # Health check: :checkhealth activity_watch

plugin/
└── activity_watch.lua  # Plugin loader (guards double-load)

doc/
└── activity-watch.txt  # Vim help documentation
```

## Code Conventions

### Formatting

- **Indent**: 2 spaces (per `.editorconfig`)
- **Line endings**: LF
- **Quotes**: Double preferred
- **Trailing whitespace**: Trimmed

### Module Pattern

All modules return a table `M` with public functions. Private state prefixed with `_`:

```lua
local M = {}
M.config = {}
M._client = nil

function M.setup(opts) end
function M.heartbeat() end

return M
```

### Type Annotations

Uses LuaCATS (`---@class`, `---@param`, `---@return`, `---@type`) for type hints:

```lua
---@class AWConfig
---@field bucket? AWBucketConfig
---@field server? AWServerConfig

---@param opts? AWConfig
function M.setup(opts)
```

### Async Patterns

- `vim.uv.spawn()` for curl subprocess (non-blocking)
- `vim.schedule()` for deferred UI notifications
- `vim.defer_fn()` for delayed autocommand registration

## Key Concepts

### Client Architecture

`client.lua` manages HTTP communication via curl:
- `M.new(opts)` creates client with bucket/server URLs
- `M.create_bucket(client)` creates AW bucket via POST
- `M.heartbeat(client, data)` sends activity events

Curl runs async via `vim.uv.spawn()`. Connection status tracked via HTTP response codes.

### Heartbeat System

Triggers on cursor/buffer events with 8-second minimum interval:
- `CursorMoved`, `CursorMovedI`, `BufEnter`, `BufLeave`
- `CmdlineEnter`, `CmdlineChanged`

Data sent: `{ file, project, branch, language }`

### Git Integration

- Branch: `git rev-parse --abbrev-ref HEAD`
- Project: Git root directory name, or cwd basename
- Updated on `BufEnter`, `FocusGained`, `FileType`

## Commands

| Command | Description |
|---------|-------------|
| `:AWStart` | Create bucket / reconnect |
| `:AWStatus` | Show connection status |
| `:AWHeartbeat` | Manual heartbeat |
| `:checkhealth activity_watch` | Health check |

## API Reference

Main module (`require("activity_watch")`):

- `setup(opts)` - Initialize with config
- `heartbeat()` - Send heartbeat event
- `start()` - Create bucket / reconnect
- `is_connected()` - Returns boolean
- `status()` - Returns "connected"/"disconnected"/"not initialized"

Client module (`require("activity_watch.client")`):

- `new(opts)` - Create client instance
- `create_bucket(client)` - POST bucket creation
- `heartbeat(client, data)` - POST heartbeat event

## Configuration

Default config in `init.lua`:

```lua
M.config = {
  bucket = {
    hostname = nil,  -- system hostname
    name = nil,      -- "aw-watcher-neovim_" .. hostname
  },
  server = {
    host = "127.0.0.1",
    port = 5600,
    ssl = false,
    pulsetime = 30,
  },
}
```

## Common Tasks

### Adding Config Options

1. Add to `---@class AWConfig` type in `init.lua`
2. Add default in `M.config`
3. Handle in `M.setup()`
4. Document in README and help file

### Adding Commands

Add in `create_commands()` via `vim.api.nvim_create_user_command()`.

### Adding Health Checks

Add in `health.lua:check()` using `vim.health.ok/warn/error/info`.

## Gotchas

1. **curl dependency**: All HTTP done via curl spawn (no Lua HTTP lib)

2. **Async responses**: `client.connected` updated async after curl completes

3. **Error throttling**: Connection errors notify at most every 60 seconds

4. **Deferred autocommands**: Heartbeat autocommands deferred 1000ms to avoid startup lag

5. **Git error suppression**: Uses `2>/dev/null` to suppress errors in non-git dirs

6. **Plugin load guard**: `vim.g.loaded_activity_watch` prevents double-load

## Testing

Manual testing:

```lua
-- In Neovim with ActivityWatch running:
:luafile %                     -- Reload current file
require("activity_watch").setup({})
:AWStatus                      -- Should show "connected"
:checkhealth activity_watch    -- Verify setup
```

No automated test suite currently.
