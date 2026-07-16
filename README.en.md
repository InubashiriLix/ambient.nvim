# ambient.nvim

[中文](./README.md)

`ambient.nvim` is an ambient music scheduler for Neovim.

It is designed for game-like background music: a track appears occasionally, ends, leaves some silence, and then another track is scheduled later. It can also run in continuous playback mode if you want a lightweight Neovim-local music player.

## Features

- Plays local music through `mpv`.
- Supports one music directory, multiple directories, or explicit playlists.
- Supports random, sequential, interval, and continuous playback modes.
- Scans common audio formats: `mp3`, `ogg`, `flac`, `wav`, `m4a`, `aac`, `opus`.
- Supports volume, recursive directory scanning, and playlist sorting.
- Adds an optional `lualine.nvim` statusline progress component.
- Provides user commands such as `:AmbientStart`, `:AmbientStop`, `:AmbientToggle`, and `:AmbientNext`.
- Provides `:checkhealth ambient`.

## Requirements

- Neovim.
- `mpv`: required for playback.
- `ffprobe`: optional, used to read track duration for better progress reporting.
- `lualine.nvim`: optional, used for the automatic statusline progress component.

Run:

```vim
:checkhealth ambient
```

## Installation

lazy.nvim local development example:

```lua
return {
  {
    dir = "/path/to/ambient.nvim",
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
    opts = {
      music_dirs = {
        "~/Music/ambient",
      },
      mode = "interval_random",
      volume = 20,
    },
    config = function(_, opts)
      require("ambient").setup(opts)
    end,
  },
}
```

For a normal repository install, replace `dir` with your repository:

```lua
{
  "your-name/ambient.nvim",
  opts = {
    music_dirs = { "~/Music/ambient" },
  },
}
```

## Quick Start

```lua
require("ambient").setup({
  music_dirs = {
    "~/Music/ambient",
  },
  mode = "interval_random",
  volume = 20,
  interval = {
    min_ms = 2 * 60 * 1000,
    max_ms = 8 * 60 * 1000,
  },
  progress = {
    enabled = true,
    update_interval_ms = 500,
    color = {
      fg = "#ffffff",
      bg = "#5b7ee5",
      gui = "bold",
    },
  },
})
```

Start playback:

```vim
:AmbientStart
```

Stop playback:

```vim
:AmbientStop
```

## Playback Modes

- `interval_random`: random playback with a random silent interval after each track.
- `interval_sequential`: sequential playback with a random silent interval after each track.
- `without_interval_random`: random continuous playback.
- `without_interval_sequential`: sequential continuous playback.
- `intermittently`: alias for `interval_random`.
- `continuous`: alias for `without_interval_random`.

`interval.min_ms` and `interval.max_ms` only affect interval modes.

## Playlists

Multiple directories:

```lua
require("ambient").setup({
  music_dirs = {
    "~/Music/ambient",
    "~/Music/piano",
  },
})
```

Full playlist configuration:

```lua
require("ambient").setup({
  playlists = {
    {
      abs_path = "~/Music/ambient",
      ext = { "mp3", "ogg", "flac", "wav" },
      recursive_depth = 4,
      sort_field = "random",
      sort_direction = "asc",
    },
    {
      abs_path = "~/Music/piano",
      ext = { "mp3", "flac" },
      recursive_depth = 2,
      sort_field = "name",
      sort_direction = "asc",
    },
  },
})
```

Supported `sort_field` values:

- `random`
- `name`
- `duration`
- `modify_time`
- `create_time`

## Statusline Progress

When `lualine.nvim` is installed, `ambient.nvim` registers a progress component at the front of `lualine_x`. The component color can be configured:

```lua
require("ambient").setup({
  progress = {
    enabled = true,
    update_interval_ms = 500,
    color = {
      fg = "#ffffff",
      bg = "#5b7ee5",
      gui = "bold",
    },
  },
})
```

Toggle the progress component:

```vim
:AmbientProgressToggle
```

If you do not use lualine, you can integrate `require("ambient").statusline()` into your own statusline.

## Commands

```vim
:AmbientStart
:AmbientStop
:AmbientToggle
:AmbientNext
:AmbientStatus
:AmbientProgressToggle
```

- `:AmbientStart`: start scheduling and playback.
- `:AmbientStop`: stop scheduling and the current track.
- `:AmbientToggle`: toggle between active and stopped.
- `:AmbientNext`: play the next track immediately.
- `:AmbientStatus`: show the current scheduler status.
- `:AmbientProgressToggle`: show or hide the statusline progress component.

## Configuration Reference

```lua
require("ambient").setup({
  enable = true,
  music_dir = "~/.config/nvim/ambient.music",
  music_dirs = nil,
  playlists = nil,
  extensions = { "mp3", "ogg", "flac", "wav", "m4a", "aac", "opus" },
  recursive_depth = 4,
  mode = "interval_random",
  volume = 50,
  interval = {
    min_ms = 2 * 60 * 1000,
    max_ms = 5 * 60 * 1000,
  },
  progress = {
    enabled = false,
    update_interval_ms = 500,
    color = {
      fg = "#ffffff",
      bg = "#5b7ee5",
      gui = "bold",
    },
  },
  show_notifications = true,
  show_notification = {
    disable_all = false,
    when_finish_setup = true,
    when_show_total_music_count = true,
    when_start_playing = true,
    when_toggle_playing_state = true,
  },
})
```

Notes:

- `music_dir`: one music directory.
- `music_dirs`: multiple directories; replaces `music_dir` when set.
- `playlists`: full playlist definitions; replaces `music_dir` and `music_dirs` when set.
- `extensions`: scanned file extensions.
- `recursive_depth`: directory recursion depth.
- `volume`: value passed to `mpv --volume`, from `0` to `100`.
- `show_notifications = false`: shorthand for disabling all notifications.

## Test Audio

The repository includes a small test track:

```text
test-music/ambient-test.wav
```

Use it to verify the plugin, `mpv`, and the statusline progress component:

```lua
require("ambient").setup({
  music_dirs = {
    "/path/to/ambient.nvim/test-music",
  },
  mode = "continuous",
  volume = 80,
  progress = {
    enabled = true,
  },
})
```

## Help

After installation:

```vim
:help ambient.nvim
:help ambient-commands
:help ambient-config
:help ambient-progress
```
