# activity-watch.nvim

[ActivityWatch](https://activitywatch.net/) integration for Neovim. Track your coding activity automatically.

## Features

- **File tracking** - Records which files you edit
- **Project detection** - Identifies projects via git root or cwd
- **Branch tracking** - Tracks current git branch
- **Language detection** - Reports file type/language

## Requirements

- Neovim >= 0.9.0
- curl
- [ActivityWatch](https://activitywatch.net/) running locally

## Installation

### lazy.nvim

```lua
{
  "taigrr/activity-watch.nvim",
  opts = {},
}
```

### packer.nvim

```lua
use {
  "taigrr/activity-watch.nvim",
  config = function()
    require("activity_watch").setup({})
  end,
}
```

## Configuration

Default configuration:

```lua
require("activity_watch").setup({
  bucket = {
    hostname = nil, -- default: system hostname
    name = nil,     -- default: "aw-watcher-neovim_" .. hostname
  },
  server = {
    host = "127.0.0.1",
    port = 5600,
    ssl = false,
    pulsetime = 30,
  },
})
```

## Commands

| Command | Description |
|---------|-------------|
| `:AWStart` | Connect/reconnect to ActivityWatch server |
| `:AWStatus` | Show connection status |
| `:AWHeartbeat` | Send manual heartbeat |

## Health Check

Run `:checkhealth activity_watch` to verify setup.

## License

0BSD
