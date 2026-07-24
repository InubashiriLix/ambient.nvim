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
- Pause and resume the current track.
- Random or sequential track selection.
- Single directory, multiple directories, or explicit playlists.
- A short-lived corner popup with title, artist, album, and cover art.
- Optional `lualine.nvim` progress component.
- User commands and `:checkhealth ambient`.

## Requirements

- Neovim
- `mpv`
- `ffprobe`, optional, for accurate track duration and progress
- `image.nvim` or `img2txt`, optional, for cover rendering in the track popup
- `lualine.nvim`, optional, for the statusline progress component

## Installation

With lazy.nvim, add a plugin spec such as
`~/.config/nvim/lua/plugins/ambient.lua`:

```lua
---@type AmbientProgressConfig
local progress = {
    enabled = true,
    layout = {
        width = 24, -- fixed width of ambient's statusline text
    },
    track = {
        enabled = true, -- show the current track title
        width = 18, -- max display width for the current track name
        scroll = true,
        scroll_separator = " ",
    },
    bar = {
        enabled = true, -- show the progress bar and percentage
        style = "block",
        width = 6, -- progress body width, excluding bar.left/right
    },
    time = {
        enabled = true,
    },
    refresh = {
        interval_ms = 500,
    },
    component = {
        -- Text frame rendered inside layout.width. This is separate from
        -- bar.left/bar.right, which wrap only the progress bar itself.
        frame = {
            enabled = false,
            left = "",
            right = "",
            padding = " ",
        },
        -- Leave these unset to inherit your lualine global style.
        -- separator = { left = "", right = "" },
        -- padding = { left = 0, right = 0 },
    },
    highlight = {
        default = {
            fg = "#7CA0F1",
            bg = "#1e2032",
            gui = "bold",
        },
        states = {
            playing = {
                fg = "#C2E78D",
                bg = "#1e2032",
                gui = "italic",
            },
            interval = {
                fg = "#7CA0F1",
                bg = "#1e2032",
                gui = "none",
            },
            stopped = {
                fg = "#7CA0F1",
                bg = "#1e2032",
                gui = "none",
            },
            error = {
                fg = "#000000",
                bg = "#f38ba8",
                gui = "bold",
            },
        },
    },
}

---@type AmbientConfig
local opts = {
    music_dirs = {
        "~/Music/ambient", -- change this to your music directory
    },
    mode = "interval_random",
    volume = 80,
    progress = progress,
}

return {
    {
        "InubashiriLix/ambient.nvim",
        name = "ambient.nvim",
        main = "ambient",
        event = "VeryLazy",
        cmd = "Ambient",
        opts = opts,
        config = function(_, opts)
            require("ambient").setup(opts)
        end,
    },
}
```

Set `music_dirs` to real directory paths. Avoid angle-bracket placeholder text
in your config because Neovim treats it as a special filename expansion pattern.

Then start playback:

```vim
:Ambient start
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

| Command                                          | Action                                                                |
| ------------------------------------------------ | --------------------------------------------------------------------- |
| `:Ambient start`                                 | Start scheduling and playback.                                        |
| `:Ambient stop`                                  | Stop scheduling and the current track.                                |
| `:Ambient pause`                                 | Pause the current track.                                              |
| `:Ambient next`                                  | Play the next track now.                                              |
| `:Ambient previous`                              | Play the previous track from playback history.                        |
| `:Ambient status`                                | Show the current scheduler status.                                    |
| `:Ambient display`                               | Show the current-track popup again.                                   |
| `:Ambient toggle pause`                          | Pause, resume, or start playback immediately.                         |
| `:Ambient toggle stop`                           | Toggle between active playback/scheduling and stopped.                |
| `:Ambient select playlist`                       | Select the active playlist.                                           |
| `:Ambient select music`                          | Choose a display sort, then select and play a track.                  |
| `:Ambient select current-playlist-music`         | Select and play from the active playlist's current playback position. |
| `:Ambient progress toggle`                       | Show or hide the statusline progress component.                       |

Subcommands support completion at each level. For example, completing after
`:Ambient select ` offers all selection commands.

### Command Migration

Legacy flat commands such as `:AmbientStart` and `:AmbientSelectMusic` are no
longer registered. Use the corresponding `:Ambient ...` command tree entries
shown above.

The `:AmbientToggle` command and `require("ambient").toggle()` API have been
removed. Replace them with `:Ambient toggle stop` and
`require("ambient").toggle_start_stop()` to preserve the previous start/stop
behavior. Use `:Ambient toggle pause` or
`require("ambient").toggle_pause_resume()` when you want pause/resume behavior.

When multiple playlists are configured, the first non-empty one is active after
setup. `:Ambient select playlist` uses `vim.ui.select()` to choose another playlist. The
current playback or interval is stopped, and the scheduler returns to `READY`
with the selected playlist.

`:Ambient select music` first prompts for a display sort order, then prompts for
a track from the active playlist and plays it immediately.

`:Ambient select current-playlist-music` keeps the active playlist in playback
order and moves the selector cursor to the playing track, or to the playlist
cursor when no track is playing. The selected track is played immediately.

## Current-track popup

By default, a non-focusable popup appears in the bottom-right corner for three
seconds whenever the track changes. It shows the title immediately, then
refreshes in place when mpv finishes loading the artist, album, and cover.

```lua
track_popup = {
    enabled = true,
    duration_ms = 3000, -- zero keeps it open until explicitly closed
    position = "bottom_right", -- top_left, top_right, bottom_left, bottom_right
    width = 46,
    height = 9,
    margin = { row = 1, col = 1 },
    border = "rounded",
    title = " 󰎈 Now Playing ",
    cover = {
        enabled = true,
        width = 14,
        backend = "auto", -- auto, image.nvim, ascii, none
    },
}
```

`auto` uses `image.nvim` when available, otherwise tries `img2txt`, then falls
back to a built-in record placeholder. Call
`require("ambient").show_current_track(duration_ms)` or `:Ambient display` to
show it manually.

The plugin emits `User AmbientTrackChanged` when a new track starts and
`User AmbientTrackInfoUpdated` when its metadata or cover becomes available.

## Statusline Progress

When `lualine.nvim` is available, `ambient.nvim` registers a component in
`lualine_x`.

To make the component match the rest of your lualine, leave
`progress.component.separator` and `progress.component.padding` unset. Set them
only when ambient should override lualine's global component separators or
padding.

`progress.component.separator` uses lualine's transition separator mechanism.
It may be invisible when both sides have the same background. For a separator
that should always be visible, use `progress.component.frame.left/right`.

```lua
progress = {
    enabled = true,
    layout = {
        width = 42,
    },
    track = {
        enabled = true,
        width = 18,
        scroll = false,
        scroll_separator = "  ",
    },
    bar = {
        enabled = true,
        style = "braille",
        width = 10,
    },
    time = {
        enabled = true,
    },
    refresh = {
        interval_ms = 500,
    },
    component = {
        frame = {
            enabled = false,
            left = "",
            right = "",
            padding = " ",
        },
        -- Stable visible text frame:
        -- frame = { enabled = true, left = "", right = "", padding = " " },
        -- separator = { left = "", right = "" },
        -- padding = { left = 0, right = 0 },
    },
    highlight = {
        default = {
            fg = "#ffffff",
            bg = "#5c7fe5",
            gui = "bold",
        },
        states = {
            playing = { bg = "#5c7fe5" },
            interval = { bg = "#7c6f64" },
            stopped = { bg = "#6c7086" },
            error = { bg = "#f38ba8" },
        },
    },
}
```

Built-in progress styles:

| Style        | Shape                        |
| ------------ | ---------------------------- |
| `braille`    | Sparse, borderless `⠶⠶⠶⠄⠄⠄`  |
| `block`      | Dense, borderless `███░░░`   |
| `line`       | Thin, borderless `━━━───`    |
| `dots`       | Dot-based `●●●○○○`           |
| `squares`    | Square-based `■■■□□□`        |
| `diamonds`   | Diamond-based `◆◆◆◇◇◇`       |
| `pipes`      | Vertical bar `▮▮▮▯▯▯`        |
| `ascii`      | Plain ASCII `[===---]`       |
| `brackets`   | Classic bracketed `[███░░░]` |
| `angle`      | Angle-wrapped `〈━━━───〉`   |
| `powerline`  | Bar wrapper with ``         |
| `separators` | Bar wrapper with ``         |
| `rounded`    | Bar wrapper with `` and `` |
| `slanted`    | Bar wrapper with `` and `` |

Aliases include `default`/`sparse` for `braille`, `blocks`/`dense` for
`block`, `classic`/`old`/`bracket` for `brackets`, `separator`/`segment` for
`separators`, and `bubble`/`round` for `rounded`. Styles only change the
progress bar characters and its own wrapper; `progress.component.frame`
remains an explicit text-frame setting.

If you do not use lualine, you can wire `require("ambient").statusline()` into
your own statusline.

## Configuration Reference

Top-level options:

| Option                                          | Meaning                                                                  |
| ----------------------------------------------- | ------------------------------------------------------------------------ |
| `enable`                                        | Disable the plugin when `false`.                                         |
| `music_dir`                                     | Single music directory used when `music_dirs` and `playlists` are unset. |
| `music_dirs`                                    | List of music directories. Overrides `music_dir`.                        |
| `playlists`                                     | Explicit playlist definitions. Overrides `music_dir` and `music_dirs`.   |
| `extensions`                                    | File extensions scanned in directory playlists.                          |
| `recursive_depth`                               | Directory scan depth.                                                    |
| `mode`                                          | Playback mode. See [Playback Modes](#playback-modes).                    |
| `volume`                                        | `mpv --volume` value, `0` to `100`.                                      |
| `interval.min_ms`                               | Minimum silent interval after a track.                                   |
| `interval.max_ms`                               | Maximum silent interval after a track.                                   |
| `show_notifications`                            | Boolean shorthand for enabling/disabling all notifications.              |
| `show_notification.disable_all`                 | Disable every notification.                                              |
| `show_notification.when_finish_setup`           | Notify after setup finishes.                                             |
| `show_notification.when_show_total_music_count` | Notify with the number of discovered tracks.                             |
| `show_notification.when_start_playing`          | Notify when playback starts.                                             |
| `show_notification.when_toggle_playing_state`   | Notify when playback is toggled.                                         |
| `track_popup.enabled`                           | Show the current-track popup on track changes.                            |
| `track_popup.duration_ms`                       | Popup lifetime in milliseconds; `0` disables auto-close.                 |
| `track_popup.position`                          | Popup corner: `top_left`, `top_right`, `bottom_left`, or `bottom_right`.  |
| `track_popup.width` / `height`                  | Preferred popup size in terminal cells.                                  |
| `track_popup.margin.row` / `.col`               | Distance from the selected corner.                                       |
| `track_popup.cover.backend`                     | `auto`, `image.nvim`, `ascii`, or `none`.                                |

Playlist options:

| Option            | Meaning                                            |
| ----------------- | -------------------------------------------------- |
| `abs_path`        | Playlist root directory.                           |
| `ext`             | Extensions for this playlist.                      |
| `recursive_depth` | Scan depth for this playlist.                      |
| `sort_field`      | `name`, `modify_time`, `create_time`, or `random`. |
| `sort_direction`  | `asc` or `desc`.                                   |

Unavailable playlist directories are skipped with a warning when at least one
configured playlist can be loaded. Setup fails when none of them are usable.

Progress options:

| Option                               | Meaning                                                                                          |
| ------------------------------------ | ------------------------------------------------------------------------------------------------ |
| `progress.enabled`                   | Show the statusline component after setup.                                                       |
| `progress.layout.width`              | Fixed display width of the ambient component text.                                               |
| `progress.track.enabled`             | Show the current track title.                                                                    |
| `progress.track.width`               | Maximum width reserved for the current track name.                                               |
| `progress.track.scroll`              | Scroll long track names instead of truncating them.                                              |
| `progress.track.scroll_separator`    | Text between repeated track names while scrolling.                                               |
| `progress.bar.enabled`               | Show the progress bar and percentage.                                                            |
| `progress.bar.style`                 | Built-in progress bar preset or alias.                                                           |
| `progress.bar.width`                 | Width of the progress bar body.                                                                  |
| `progress.bar.filled`                | Filled progress character, one display cell.                                                     |
| `progress.bar.empty`                 | Empty progress character, one display cell.                                                      |
| `progress.bar.left`                  | Left wrapper around the progress bar only.                                                       |
| `progress.bar.right`                 | Right wrapper around the progress bar only.                                                      |
| `progress.time.enabled`              | Show elapsed/total time.                                                                         |
| `progress.refresh.interval_ms`       | Statusline refresh interval in milliseconds.                                                     |
| `progress.component.frame.enabled`   | Enable the text frame rendered inside `layout.width`.                                            |
| `progress.component.frame.left`      | Left text frame string.                                                                          |
| `progress.component.frame.right`     | Right text frame string.                                                                         |
| `progress.component.frame.padding`   | Text inserted between the frame and the content.                                                 |
| `progress.component.separator.left`  | Optional lualine left separator override. Omit `separator` to inherit lualine.                   |
| `progress.component.separator.right` | Optional lualine right separator override. Omit `separator` to inherit lualine.                  |
| `progress.component.padding`         | Optional lualine padding override, as a number or `{ left = N, right = N }`.                     |
| `progress.highlight.default.fg`      | Default foreground color.                                                                        |
| `progress.highlight.default.bg`      | Default background color.                                                                        |
| `progress.highlight.default.gui`     | Default font style: `none`, `bold`, `italic`, `underline`, `undercurl`, or `strikethrough`.      |
| `progress.highlight.states`          | Per-state color overrides: `ready`, `playing`, `interval`, `stopped`, `paused`, `next`, `error`. |

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
