# ambient.nvim

[English](./README.en.md)

`ambient.nvim` 是一个给 Neovim 用的环境音乐调度器。

它的播放方式更接近游戏里的背景音乐：音乐不会一直播放，而是在编辑时偶尔响起一首，结束后留出一段安静时间，再进入下一次播放。也可以切到连续播放模式，把它当成一个轻量的 Neovim 播放器使用。

## 功能

- 调用本机 `mpv` 播放本地音乐。
- 支持单个音乐目录、多个音乐目录、多个播放列表。
- 支持随机播放、顺序播放、间隔播放、连续播放。
- 支持 `mp3`、`ogg`、`flac`、`wav`、`m4a`、`aac`、`opus` 等常见格式。
- 支持音量设置、递归扫描目录、按名称/时间/时长排序。
- 支持 `lualine.nvim` 状态栏进度组件。
- 提供 `:AmbientStart`、`:AmbientStop`、`:AmbientToggle`、`:AmbientNext` 等命令。
- 提供 `:checkhealth ambient` 健康检查。

## 依赖

- Neovim。
- `mpv`：必须安装，用于实际播放音频。
- `ffprobe`：可选，用于读取音频时长；没有它也能播放，但进度百分比可能不准确。
- `lualine.nvim`：可选，用于自动显示右下角状态栏进度组件。

可以先执行：

```vim
:checkhealth ambient
```

## 安装

lazy.nvim 本地开发配置示例：

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

如果要使用仓库安装，把 `dir` 换成你的仓库地址即可：

```lua
{
  "your-name/ambient.nvim",
  opts = {
    music_dirs = { "~/Music/ambient" },
  },
}
```

## 快速开始

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

启动播放：

```vim
:AmbientStart
```

停止播放：

```vim
:AmbientStop
```

## 播放模式

- `interval_random`：随机播放；每首结束后等待随机间隔。
- `interval_sequential`：顺序播放；每首结束后等待随机间隔。
- `without_interval_random`：随机连续播放。
- `without_interval_sequential`：顺序连续播放。
- `intermittently`：`interval_random` 的别名。
- `continuous`：`without_interval_random` 的别名。

`interval.min_ms` 和 `interval.max_ms` 只影响带间隔的模式。

## 播放列表

使用多个目录：

```lua
require("ambient").setup({
  music_dirs = {
    "~/Music/ambient",
    "~/Music/piano",
  },
})
```

使用完整播放列表配置：

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

`sort_field` 支持：

- `random`
- `name`
- `duration`
- `modify_time`
- `create_time`

## 状态栏进度

如果安装了 `lualine.nvim`，`ambient.nvim` 会把播放进度注册到 `lualine_x` 的开头。可以通过配置调整颜色：

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

显示或隐藏进度组件：

```vim
:AmbientProgressToggle
```

没有使用 lualine 时，也可以把 `require("ambient").statusline()` 接入自己的 statusline。

## 命令

```vim
:AmbientStart
:AmbientStop
:AmbientToggle
:AmbientNext
:AmbientStatus
:AmbientProgressToggle
```

- `:AmbientStart`：开始调度并播放。
- `:AmbientStop`：停止调度，并停止当前歌曲。
- `:AmbientToggle`：在播放/等待和停止之间切换。
- `:AmbientNext`：立刻播放下一首。
- `:AmbientStatus`：显示当前状态。
- `:AmbientProgressToggle`：显示或隐藏状态栏进度组件。

## 配置参考

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

说明：

- `music_dir`：单个音乐目录。
- `music_dirs`：多个音乐目录；设置后会替代 `music_dir`。
- `playlists`：完整播放列表配置；设置后会替代 `music_dir` 和 `music_dirs`。
- `extensions`：扫描的文件扩展名。
- `recursive_depth`：目录递归深度。
- `volume`：传给 `mpv --volume` 的音量，范围 `0` 到 `100`。
- `show_notifications = false`：关闭所有通知的快捷写法。

## 测试音频

仓库内带有一个测试音频：

```text
test-music/ambient-test.wav
```

可以用它验证插件、`mpv` 和状态栏进度是否正常：

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

## 帮助文档

安装后可以在 Neovim 里查看：

```vim
:help ambient.nvim
:help ambient-commands
:help ambient-config
:help ambient-progress
```
