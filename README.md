# ambient.nvim

[中文](./README.zh-CN.md) | [vimdoc](./doc/ambient.txt)

Game-style ambient music for Neovim.

`ambient.nvim` plays local music through `mpv`. It can act like quiet game
background music: play one track, stay silent for a while, then schedule the
next one. It can also run as a lightweight continuous music player inside
Neovim.

## Features

- Local playback through `mpv`.
- Interval or continuous playback.
- Random or sequential track selection.
- Single directory, multiple directories, or explicit playlists.
- Optional `lualine.nvim` progress component.
- User commands and `:checkhealth ambient`.

## Requirements

- Neovim
- `mpv`
- `ffprobe`, optional, for accurate track duration and progress
- `lualine.nvim`, optional, for the statusline progress component

## Installation

With lazy.nvim, add a plugin spec such as
`~/.config/nvim/lua/plugins/ambient.lua`:

```lua
return {
    {
        "InubashiriLix/ambient.nvim",
        name = "ambient.nvim",
        main = "ambient",
        event = "VeryLazy",
        cmd = {
            "AmbientStart",
            "AmbientStop",
            "AmbientToggle",
            "AmbientNext",
            "AmbientStatus",
            "AmbientProgressToggle",
        },

        ---@type AmbientConfig -- it is recommended to add type annotation for better completion
        opts = {
            music_dirs = {
                "<your music dir>",
            },
            mode = "interval_random",
            volume = 80,
            progress = {
                enabled = true,
                update_interval_ms = 500,
                color = {
                    fg = "#ffffff",
                    bg = "#5c7fe5",
                    gui = "bold",
                },
            },
        },
        config = function(_, opts)
            require("ambient").setup(opts)
        end,
    },
}
```

Then start playback:

```vim
:AmbientStart
```

## Playback Modes

| Mode                          | Behavior                                                         |
| ----------------------------- | ---------------------------------------------------------------- |
| `interval_random`             | Random tracks with a random quiet interval after each track.     |
| `interval_sequential`         | Sequential tracks with a random quiet interval after each track. |
| `without_interval_random`     | Random continuous playback.                                      |
| `without_interval_sequential` | Sequential continuous playback.                                  |
| `intermittently`              | Alias for `interval_random`.                                     |
| `continuous`                  | Alias for `without_interval_random`.                             |

Interval modes use:

```lua
interval = {
    min_ms = 2 * 60 * 1000,
    max_ms = 8 * 60 * 1000,
}
```

## Commands

| Command                  | Action                                          |
| ------------------------ | ----------------------------------------------- |
| `:AmbientStart`          | Start scheduling and playback.                  |
| `:AmbientStop`           | Stop scheduling and the current track.          |
| `:AmbientToggle`         | Toggle between active and stopped.              |
| `:AmbientNext`           | Play the next track now.                        |
| `:AmbientStatus`         | Show the current scheduler status.              |
| `:AmbientProgressToggle` | Show or hide the statusline progress component. |

## Statusline Progress

When `lualine.nvim` is available, `ambient.nvim` registers a component in
`lualine_x`.

```lua
progress = {
    enabled = true,
    update_interval_ms = 500,
    color = {
        fg = "#ffffff",
        bg = "#5c7fe5",
        gui = "bold",
    },
}
```

If you do not use lualine, you can wire `require("ambient").statusline()` into
your own statusline.

## Health Check

```vim
:checkhealth ambient
```

This checks `mpv`, optional `ffprobe`, and configured music directories.

## Documentation

```vim
:help ambient.nvim
:help ambient-commands
:help ambient-config
:help ambient-progress
```

The repository also includes `test-music/ambient-test.wav` for a quick playback
test.

## Future Plans

- [ ] add more tests (none for now)
- [ ] refactor the proj, perf type declaration and add more tests. (next step)
- [ ] add keymap binding support in config (next step)
- [ ] add tui interface for music selection, history (next stop) (might be hard)
- [ ] add support for oneline music playing. (hard)
