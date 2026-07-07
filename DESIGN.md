# 设计指导

这个文档用来记录 `ambient.nvim` 的设计方向。

它不是正式论文，也不是复杂架构文档。它的目标是让刚开始写 Neovim 插件的人也能看懂这个项目应该怎么做。

## 核心想法

`ambient.nvim` 的核心想法是：

```text
音乐应该像游戏背景音乐一样，偶尔出现，而不是一直播放。
```

普通播放器的逻辑是：

```text
播放 -> 下一首 -> 下一首 -> 下一首
```

这个插件的逻辑应该是：

```text
安静 -> 播放一小段 -> 安静 -> 可能再播放
```

所以，“静默时间”不是空白，而是插件体验的一部分。

## 第一版只保留三个模块概念

先不要想太复杂。第一版可以理解成三个部分：

```text
配置 config
播放器 player
调度器 scheduler
```

它们分别负责：

### config

负责用户配置。

比如：

- 用哪个播放器。
- 音量是多少。
- 音乐文件在哪里。
- 静默时间范围是多少。

### player

负责播放一首歌。

它不需要自己解码音频，只需要调用外部程序。

推荐第一版只支持：

```text
mpv
```

原因是 `mpv` 稳定、简单、跨平台支持也不错。

### scheduler

负责什么时候播放。

它要做的事情：

- 随机选一首歌。
- 播放它。
- 等它结束。
- 随机等待一段时间。
- 再播放下一首。

## 第一版目录结构

建议第一版目录长这样：

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

每个文件负责一件事：

- `README.md`：给用户看的说明。
- `DESIGN.md`：给开发者看的设计说明。
- `lua/ambient/init.lua`：插件入口，对外暴露 `setup()`。
- `lua/ambient/config.lua`：默认配置和配置检查。
- `lua/ambient/player.lua`：调用 `mpv` 播放和停止音乐。
- `lua/ambient/scheduler.lua`：随机播放和随机静默。
- `plugin/ambient.lua`：Neovim 启动时注册命令。

## 目录什么时候创建

新手开发插件时，很容易一开始就创建很多文件，然后不知道从哪里写。

这个项目建议这样来：

### 现在就要有的文件

```text
README.md
DESIGN.md
```

这两个文件不需要代码能力，先写它们是为了防止项目跑偏。

### 开始写第一行 Lua 时再创建

```text
lua/ambient/init.lua
lua/ambient/config.lua
lua/ambient/player.lua
lua/ambient/scheduler.lua
plugin/ambient.lua
```

这几个文件是第一版的核心。

如果不知道先写哪个，顺序可以是：

1. `init.lua`
2. `config.lua`
3. `player.lua`
4. `scheduler.lua`
5. `plugin/ambient.lua`

原因很简单：

- 先有入口。
- 再有配置。
- 再能播放一首歌。
- 再考虑自动播放下一首。
- 最后注册用户命令。

### 插件能跑之后再创建

```text
doc/ambient.txt
lua/ambient/health.lua
spec/ambient/
Makefile
stylua.toml
.luacheckrc
.github/workflows/ci.yml
```

这些是维护项目用的，不是 MVP 必须品。

它们的作用是：

- `doc/ambient.txt`：让用户可以用 `:help ambient` 看文档。
- `health.lua`：让用户可以用 `:checkhealth ambient` 检查问题。
- `spec/ambient/`：放测试。
- `Makefile`：简化常用命令。
- `stylua.toml`：统一代码格式。
- `.luacheckrc`：检查明显的 Lua 问题。
- `.github/workflows/ci.yml`：以后上传 GitHub 后自动跑检查。

## 最终目录参考

完整一点的工程模板可以长这样：

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
      state.lua
  plugin/
    ambient.lua
  doc/
    ambient.txt
  spec/
    ambient/
      config_spec.lua
      player_spec.lua
      scheduler_spec.lua
  .github/
    workflows/
      ci.yml
```

但是注意：这是最终参考，不是第一天就要全部实现。

## 不要一开始就做复杂功能

这些功能先不要做：

- mood 系统。
- 根据文件类型切换音乐。
- 根据 LSP 错误切换音乐。
- 根据 Git 状态切换音乐。
- 音乐包系统。
- 漂亮 UI。
- 在线曲库。

不是说这些不好，而是它们会让第一版变难。

第一版应该先证明一件事：

```text
这个插件可以稳定地随机播放音乐，并且不会打扰用户。
```

## 好的默认体验

默认体验应该保守。

建议：

- 默认音量低一点，比如 20。
- 每首之间至少静默 2 分钟。
- 最大静默时间可以到 8 或 10 分钟。
- 不要一打开 Neovim 就突然大声播放。
- 用户应该可以随时停止。

## 后续功能路线

等第一版稳定后，再按这个顺序加功能。

### 第二阶段：状态和命令

加入：

- `:AmbientStatus`
- 当前是否正在播放。
- 下一次播放大概是什么时候。
- 上一次错误是什么。

### 第三阶段：健康检查

加入：

```vim
:checkhealth ambient
```

它可以检查：

- 有没有安装 `mpv`。
- 用户有没有配置音乐。
- 配置格式是否正确。

### 第四阶段：mood

给音乐加氛围标签：

```lua
{ path = "soft-piano.mp3", mood = "calm" }
{ path = "deep-pad.ogg", mood = "night" }
```

以后可以根据不同状态选择不同 mood。

### 第五阶段：Neovim 状态感知

可以监听：

- 用户是否正在输入。
- 用户是否停顿很久。
- diagnostics 是否很多。
- 当前时间是否是晚上。

但是要记住：

```text
事件只影响下一次选择，不要每次事件发生都立刻播放音乐。
```

否则会很吵。

## 判断一个功能该不该加

可以问三个问题：

1. 它会不会让插件更安静、更自然？
2. 它会不会打断用户写代码？
3. 它会不会让第一版复杂很多？

如果一个功能很酷，但会让项目难很多，可以先写进 TODO，不要马上实现。

## 最重要的原则

```text
宁可少做，也不要吵。
```

这个插件的价值不是功能很多，而是体验克制。
