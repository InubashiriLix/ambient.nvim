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
        ---@type AmbientConfig -- it is recommanded to add type annotation for better completion
        opts = {
            music_dirs = {
                "<your music dir>", -- 替换为你的音乐目录
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

| 命令                     | 作用                        |
| ------------------------ | --------------------------- |
| `:AmbientStart`          | 开始调度并播放。            |
| `:AmbientStop`           | 停止调度，并停止当前歌曲。  |
| `:AmbientToggle`         | 在播放/等待和停止之间切换。 |
| `:AmbientNext`           | 立刻播放下一首。            |
| `:AmbientStatus`         | 显示当前状态。              |
| `:AmbientProgressToggle` | 显示或隐藏状态栏进度组件。  |

## 状态栏进度

如果安装了 `lualine.nvim`，`ambient.nvim` 会把播放进度注册到 `lualine_x`。

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

没有使用 lualine 时，也可以把 `require("ambient").statusline()` 接入自己的 statusline。

## 健康检查

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
