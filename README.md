# ambient.nvim

一个给 Neovim 用的“游戏式背景音乐”插件。

它不是普通音乐播放器。它的目标更像 Minecraft 里的背景音乐：音乐不是一直响，而是偶尔出现，播放一小段，然后留下安静的间隔。

## 这个插件想解决什么

很多人写代码时会放 BGM，但普通播放器有几个问题：

- 音乐一直播放，时间久了容易累。
- 歌曲存在感太强，会抢注意力。
- 播放逻辑和当前写代码状态没有关系。

`ambient.nvim` 想做的是一种更轻的体验：

- 大部分时间是安静的。
- 偶尔播放平淡、低存在感的音乐。
- 每首之间有随机静默时间。
- 以后可以根据 Neovim 状态调整音乐氛围。

## 第一版目标

第一版不要做复杂。

只做这几件事：

1. 用户配置一些本地音乐文件或音乐目录。
2. 插件随机选择一首。
3. 调用外部播放器播放，比如 `mpv`。
4. 播放结束后等待一段随机时间。
5. 然后再随机播放下一首。

也就是说，第一版核心逻辑是：

```text
随机选歌 -> 播放 -> 随机静默 -> 再随机选歌
```

## 暂时不做什么

为了让项目容易开始，第一版暂时不做：

- 在线音乐服务。
- AI 生成音乐。
- 复杂 UI。
- 根据代码语言自动切换音乐。
- 根据 LSP 错误自动切换音乐。
- 音乐包系统。

这些以后都可以做，但不应该放进第一版。

## 未来使用方式

最终希望用户可以这样配置：

```lua
require("ambient").setup({
  backend = "mpv",
  volume = 20,
  music_dirs = {
    "~/Music/ambient",
  },
  silence = {
    min_ms = 2 * 60 * 1000,
    max_ms = 8 * 60 * 1000,
  },
})
```

也可以手动指定音乐：

```lua
require("ambient").setup({
  tracks = {
    "~/Music/ambient/piano-1.mp3",
    "~/Music/ambient/pad-1.ogg",
  },
})
```

## 未来命令

计划提供这些命令：

```vim
:AmbientStart
:AmbientStop
:AmbientToggle
:AmbientNext
:AmbientStatus
```

每个命令的作用：

- `:AmbientStart`：开始调度背景音乐。
- `:AmbientStop`：停止调度，并停止当前播放。
- `:AmbientToggle`：开关切换。
- `:AmbientNext`：立刻切到下一首。
- `:AmbientStatus`：查看当前状态。

## 推荐开发顺序

建议按这个顺序做：

1. 搭建最小插件结构。
2. 实现 `setup()` 配置入口。
3. 实现调用 `mpv` 播放一个文件。
4. 实现停止播放。
5. 实现随机选歌。
6. 实现随机静默时间。
7. 加入用户命令。
8. 加入简单文档和健康检查。
9. 再考虑测试、CI、发布。

更详细的功能计划见 [plan.txt](./plan.txt)。

## 目录模板

这个项目可以分三步搭目录。不要一开始就把所有东西都写满。

### 第一步：只有文档

现在先保持这样：

```text
ambient.nvim/
  README.md
  DESIGN.md
  lua/
    ambient/
  plugin/
  doc/
  spec/
    ambient/
  scripts/
  .github/
    workflows/
```

这一步的目的：

- 想清楚插件要做什么。
- 想清楚第一版不做什么。
- 先把范围控制住。
- 先放好空目录，后面写代码时不需要重新想结构。

现在这些目录可以是空的。空目录只是提醒我们以后文件应该放在哪里。

### 第二步：最小可运行插件

等准备开始写代码时，再加这些目录：

```text
ambient.nvim/
  README.md
  DESIGN.md
  lua/
    ambient/
      init.lua
      config.lua
      player.lua
      scheduler.lua
  plugin/
    ambient.lua
```

这些文件的作用：

- `lua/ambient/init.lua`：插件主入口，用户会调用 `require("ambient").setup()`。
- `lua/ambient/config.lua`：默认配置，比如音量、音乐目录、静默时间。
- `lua/ambient/player.lua`：只负责播放和停止音乐。
- `lua/ambient/scheduler.lua`：只负责随机选歌和等待。
- `plugin/ambient.lua`：Neovim 加载插件时自动执行，通常用来注册命令。

第二步完成后，插件应该能做到：

```text
打开 Neovim -> 执行 :AmbientStart -> 播放一首本地音乐
```

### 第三步：工程化模板

等最小版本能跑了，再补工程文件：

```text
ambient.nvim/
  README.md
  DESIGN.md
  LICENSE
  Makefile
  stylua.toml
  .luacheckrc
  lua/
    ambient/
      init.lua
      config.lua
      player.lua
      scheduler.lua
      commands.lua
      health.lua
  plugin/
    ambient.lua
  doc/
    ambient.txt
  spec/
    ambient/
      config_spec.lua
      scheduler_spec.lua
  .github/
    workflows/
      ci.yml
```

这些新增文件的作用：

- `LICENSE`：开源协议。
- `Makefile`：把常用开发命令放在一起，比如测试、格式化。
- `stylua.toml`：Lua 代码格式化配置。
- `.luacheckrc`：Lua 静态检查配置。
- `commands.lua`：把用户命令集中放在一个文件里。
- `health.lua`：支持 `:checkhealth ambient`。
- `doc/ambient.txt`：Neovim 帮助文档。
- `spec/`：测试目录。
- `.github/workflows/ci.yml`：GitHub Actions 自动检查。

第三步不是第一天必须做。它适合在插件已经能跑之后再加。

## 项目定位

一句话：

```text
ambient.nvim 是 Neovim 里的游戏式环境音乐调度器。
```

它的重点不是“播放很多歌”，而是“在合适的时候播放一点点音乐”。
