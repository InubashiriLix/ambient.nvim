# ambient.nvim

[English](./README.md) | [vimdoc](./doc/ambient.txt)

`ambient.nvim` 是一个给 Neovim 用的游戏式环境音乐插件。

它通过 `mpv` 播放本地音乐。默认目标不是一直播放 BGM，而是像游戏背景音乐一样：播放一首，安静一段时间，然后再播放下一首。也可以切到连续播放模式，把它当成轻量的 Neovim 播放器。

## 功能

- 通过本机 `mpv` 播放音乐。
- 支持间隔播放和连续播放。
- 支持随机选歌和顺序选歌。
- 支持单目录、多目录、完整播放列表。
- 支持 `lualine.nvim` 状态栏进度组件。
- 提供用户命令和 `:checkhealth ambient`。

## 依赖

- Neovim
- `mpv`
- `ffprobe`，可选，用于读取音频时长和进度
- `lualine.nvim`，可选，用于状态栏进度组件

## 安装

lazy.nvim 示例。可以在 `~/.config/nvim/lua/plugins/ambient.lua` 中加入：

```lua
---@type AmbientProgressConfig
local progress = {
    enabled = true,
    layout = {
        width = 42, -- ambient 状态栏文本的固定宽度
    },
    track = {
        enabled = true, -- 显示当前歌曲标题
        width = 18, -- 当前歌曲名的最大显示宽度
        scroll = false,
        scroll_separator = "  ",
    },
    bar = {
        enabled = true, -- 显示进度条和百分比
        style = "braille",
        width = 10, -- 进度条主体宽度，不包含 bar.left/bar.right
    },
    time = {
        enabled = true,
    },
    refresh = {
        interval_ms = 500,
    },
    component = {
        -- 这里是 layout.width 内部的文本外框；
        -- 进度条自己的外框在 bar.left/bar.right。
        frame = {
            enabled = false,
            left = "",
            right = "",
            padding = " ",
        },
        -- 不设置时会继承 lualine 的全局样式。
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

---@type AmbientConfig
local opts = {
    music_dirs = {
        "~/Music/ambient", -- 改成你的音乐目录
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
        cmd = {
            "AmbientStart",
            "AmbientStop",
            "AmbientToggle",
            "AmbientNext",
            "AmbientPlaylist",
            "AmbientSelectMusic",
            "AmbientStatus",
            "AmbientProgressToggle",
        },
        opts = opts,
        config = function(_, opts)
            require("ambient").setup(opts)
        end,
    },
}
```

`music_dirs` 需要写真实目录。不要在配置里保留尖括号占位文本，
因为 Neovim 会把它当成特殊文件名展开。

启动播放：

```vim
:AmbientStart
```

## 播放模式

| 模式                          | 行为                                   |
| ----------------------------- | -------------------------------------- |
| `interval_random`             | 随机播放；每首结束后等待随机安静间隔。 |
| `interval_sequential`         | 顺序播放；每首结束后等待随机安静间隔。 |
| `without_interval_random`     | 随机连续播放。                         |
| `without_interval_sequential` | 顺序连续播放。                         |
| `intermittently`              | `interval_random` 的别名。             |
| `continuous`                  | `without_interval_random` 的别名。     |

间隔模式使用：

```lua
interval = {
    min_ms = 2 * 60 * 1000,
    max_ms = 8 * 60 * 1000,
}
```

## 命令

| 命令                     | 作用                                |
| ------------------------ | ----------------------------------- |
| `:AmbientStart`          | 开始调度并播放。                    |
| `:AmbientStop`           | 停止调度，并停止当前歌曲。          |
| `:AmbientToggle`         | 在播放/等待和停止之间切换。         |
| `:AmbientNext`           | 立刻播放下一首。                    |
| `:AmbientPlaylist`       | 选择当前播放列表。                  |
| `:AmbientSelectMusic`    | 从当前播放列表选择并立刻播放歌曲。  |
| `:AmbientStatus`         | 显示当前状态。                      |
| `:AmbientProgressToggle` | 显示或隐藏状态栏进度组件。          |

配置多个播放列表时，setup 后默认选择第一个非空列表。`:AmbientPlaylist`
通过 `vim.ui.select()` 切换播放列表；当前播放或等待会停止，调度器使用新列表
回到 `READY` 状态。

`:AmbientSelectMusic` 会先选择列表的显示排序方式，再从当前播放列表选择歌曲并
立刻播放。

## 状态栏进度

如果安装了 `lualine.nvim`，`ambient.nvim` 会把播放进度注册到 `lualine_x`。
如果希望它和其它 lualine 组件保持一致，保留
`progress.component.separator` 和 `progress.component.padding` 为空即可；
只有想给 ambient 单独覆盖分隔符或 padding 时才需要设置它们。

`progress.component.separator` 走的是 lualine 的 transition separator 机制；
两侧背景色相同时可能不可见。需要稳定可见的分隔字符时，用
`progress.component.frame.left/right`。

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
        -- 稳定可见的文本边框：
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

内置进度样式：

| 样式         | 形态                 |
| ------------ | -------------------- |
| `braille`    | 稀疏、无边框         |
| `block`      | 旧版块状进度条       |
| `line`       | 细线进度条           |
| `dots`       | 圆点进度条           |
| `squares`    | 方块进度条           |
| `diamonds`   | 菱形进度条           |
| `pipes`      | 竖条进度条           |
| `ascii`      | ASCII 方括号进度条   |
| `brackets`   | 经典方括号块状进度条 |
| `angle`      | 尖括号细线进度条     |
| `powerline`  | 使用 `` 的进度条外框 |
| `separators` | 使用 `` 的进度条外框 |
| `rounded`    | 使用 ``/`` 的进度条外框 |
| `slanted`    | 使用 ``/`` 的进度条外框 |

别名包括：`default`/`sparse` -> `braille`，`blocks`/`dense` -> `block`，
`classic`/`old`/`bracket` -> `brackets`，`separator`/`segment` -> `separators`，
`bubble`/`round` -> `rounded`。样式只改变进度条字符和进度条自己的外框；
整个 statusline component 的文本外框由 `progress.component.frame` 显式配置。

没有使用 lualine 时，也可以把 `require("ambient").statusline()` 接入自己的 statusline。

## 配置参考

顶层选项：

| 选项 | 含义 |
| --- | --- |
| `enable` | 为 `false` 时禁用插件。 |
| `music_dir` | 单个音乐目录；未设置 `music_dirs` 和 `playlists` 时使用。 |
| `music_dirs` | 多个音乐目录；会覆盖 `music_dir`。 |
| `playlists` | 显式播放列表；会覆盖 `music_dir` 和 `music_dirs`。 |
| `extensions` | 扫描目录时使用的文件扩展名。 |
| `recursive_depth` | 目录扫描深度。 |
| `mode` | 播放模式，见“播放模式”。 |
| `volume` | `mpv --volume`，范围 `0` 到 `100`。 |
| `interval.min_ms` | 每首歌结束后的最短安静间隔。 |
| `interval.max_ms` | 每首歌结束后的最长安静间隔。 |
| `show_notifications` | 开关所有通知的简写。 |
| `show_notification.disable_all` | 禁用所有通知。 |
| `show_notification.when_finish_setup` | setup 完成后通知。 |
| `show_notification.when_show_total_music_count` | 显示扫描到的曲目数量。 |
| `show_notification.when_start_playing` | 开始播放时通知。 |
| `show_notification.when_toggle_playing_state` | 切换播放状态时通知。 |

播放列表选项：

| 选项 | 含义 |
| --- | --- |
| `abs_path` | 播放列表根目录。 |
| `ext` | 当前播放列表的扩展名。 |
| `recursive_depth` | 当前播放列表的扫描深度。 |
| `sort_field` | `name`、`modify_time`、`create_time` 或 `random`。 |
| `sort_direction` | `asc` 或 `desc`。 |

进度组件选项：

| 选项 | 含义 |
| --- | --- |
| `progress.enabled` | setup 后是否显示状态栏组件。 |
| `progress.layout.width` | ambient 组件文本的固定显示宽度。 |
| `progress.track.enabled` | 是否显示当前歌曲标题。 |
| `progress.track.width` | 当前歌曲名最多占用的宽度。 |
| `progress.track.scroll` | 歌曲名过长时是否滚动显示。 |
| `progress.track.scroll_separator` | 滚动时重复歌曲名之间的分隔文本。 |
| `progress.bar.enabled` | 是否显示进度条和百分比。 |
| `progress.bar.style` | 内置进度条样式或别名。 |
| `progress.bar.width` | 进度条主体宽度。 |
| `progress.bar.filled` | 已播放部分字符，必须占一个显示单元。 |
| `progress.bar.empty` | 未播放部分字符，必须占一个显示单元。 |
| `progress.bar.left` | 只包裹进度条的左侧字符。 |
| `progress.bar.right` | 只包裹进度条的右侧字符。 |
| `progress.time.enabled` | 是否显示已播放/总时长。 |
| `progress.refresh.interval_ms` | 状态栏刷新间隔，单位毫秒。 |
| `progress.component.frame.enabled` | 是否启用渲染在 `layout.width` 内部的文本外框。 |
| `progress.component.frame.left` | 文本外框左侧字符串。 |
| `progress.component.frame.right` | 文本外框右侧字符串。 |
| `progress.component.frame.padding` | 文本外框和内容之间的填充。 |
| `progress.component.separator.left` | 当前 lualine 组件的左侧分隔符覆盖项；不设置 `separator` 则继承 lualine。 |
| `progress.component.separator.right` | 当前 lualine 组件的右侧分隔符覆盖项；不设置 `separator` 则继承 lualine。 |
| `progress.component.padding` | 当前 lualine 组件的 padding 覆盖项，可为数字或 `{ left = N, right = N }`。 |
| `progress.highlight.default.fg` | 默认前景色。 |
| `progress.highlight.default.bg` | 默认背景色。 |
| `progress.highlight.default.gui` | 默认字体样式：`none`、`bold`、`italic`、`underline`、`undercurl` 或 `strikethrough`。 |
| `progress.highlight.states` | 各状态颜色覆盖：`ready`、`playing`、`interval`、`stopped`、`paused`、`next`、`error`。 |

## 检查

```vim
:checkhealth ambient
```

它会检查 `mpv`、可选的 `ffprobe`，以及配置的音乐目录。

## 文档

```vim
:help ambient.nvim
:help ambient-commands
:help ambient-config
:help ambient-progress
```

仓库内也带了 `test-music/ambient-test.wav`，可以用来快速测试播放和状态栏进度。
