---A bunny egg module. just printout the animation of Sysiphus and play the music of Sysiphus.
---@author [InubashiriLix](https://github.com/InubashiriLix)
---@license [DBAD](https://github.com/philsturgeon/dbad)

local result = require("ambient.common.result")
local music  = require("ambient.models.music")
local player = require("ambient.player")

local script_path = debug.getinfo(1, "S").source:sub(2)

local function bonus_music_path()
    local plugin_root = vim.fn.fnamemodify(script_path, ":p:h:h:h:h")
    return plugin_root .. "/bonus/Me and the Birds.mp3"
end

---@class AmbientSysiphus
---@field private frames string[]
---@field private token integer
---@field private buf? integer
---@field private win? integer
---@field public display fun(self: AmbientSysiphus): AmbientResult<nil, AmbientSysiphusError>
local M = {
    token = 0,
    buf   = nil,
    win   = nil,
}

---@enum AmbientSysiphusError
M.Error = {
    NOT_READY       = "NOT_READY",
    BONUS_MUSIC_ERR = "BONUS_MUSIC_ERR",
    FAILED_TO_PLAY  = "FAILED_TO_PLAY",
}

M.frames = {
    [[
                                    ╱
                                 ╱
                              ╱
                           ╱
                        ╱
                     ╱
                  ╱
  ᕦ(ò_óˇ)ᕤ(●)  ╱
____________╱]],
    [[
                                    ╱
                                 ╱
                              ╱
                           ╱
                        ╱
                     ╱
     ᕦ(ò_óˇ)ᕤ(●)  ╱
               ╱
____________╱]],
    [[
                                    ╱
                                 ╱
                              ╱
                           ╱
                        ╱
        ᕦ(ò_óˇ)ᕤ(●)  ╱
                  ╱
               ╱
____________╱]],
    [[
                                    ╱
                                 ╱
                              ╱
                           ╱
           ᕦ(ò_óˇ)ᕤ(●)  ╱
                     ╱
                  ╱
               ╱
____________╱]],
    [[
                                    ╱
                                 ╱
                              ╱
              ᕦ(ò_óˇ)ᕤ(●)  ╱
                        ╱
                     ╱
                  ╱
               ╱
____________╱]],
    [[
                                    ╱
                                 ╱
                 ᕦ(ò_óˇ)ᕤ(●)  ╱
                           ╱
                        ╱
                     ╱
                  ╱
               ╱
____________╱]],
    [[
                                    ╱
                    ᕦ(ò_óˇ)ᕤ(●)  ╱
                              ╱
                           ╱
                        ╱
                     ╱
                  ╱
               ╱
____________╱]],
    [[
                       ᕦ(ò_óˇ)ᕤ(●)  ╱
                                 ╱
                              ╱
                           ╱
                        ╱
                     ╱
                  ╱
               ╱
____________╱]],
    [[
                       ᕦ(ò_óˇ)ᕤ(●)  ╱
                                 ╱
                              ╱
                           ╱
                        ╱
                     ╱
                  ╱
               ╱
____________╱]],
    [[
                       ╲(°ロ°)╱     ╱
                              (●)╱
                              ╱
                           ╱
                        ╱
                     ╱
                  ╱
               ╱
____________╱]],
    [[
                       ╲(°ロ°)╱     ╱
                              (●)╱
                              ╱
                           ╱
                        ╱
                     ╱
                  ╱
               ╱
____________╱]],
    [[
                       ╲(°ロ°)╱     ╱
                                 ╱
                           (●)╱
                           ╱
                        ╱
                     ╱
                  ╱
               ╱
____________╱]],
    [[
                       ╲(°ロ°)╱     ╱
                                 ╱
                              ╱
                        (●)╱
                        ╱
                     ╱
                  ╱
               ╱
____________╱]],
    [[
                       ╲(°ロ°)╱     ╱
                                 ╱
                              ╱
                           ╱
                     (●)╱
                     ╱
                  ╱
               ╱
____________╱]],
    [[
                       ╲(°ロ°)╱     ╱
                                 ╱
                              ╱
                           ╱
                        ╱
                  (●)╱
                  ╱
               ╱
____________╱]],
    [[
                       ╲(°ロ°)╱     ╱
                                 ╱
                              ╱
                           ╱
                        ╱
                     ╱
               (●)╱
               ╱
____________╱]],
    [[
                            ＿|￣|○ ╱
                                 ╱
                              ╱
                           ╱
                        ╱
                     ╱
                  ╱
            (●)╱
____________╱]],
    [[
                            ＿|￣|○ ╱
                                 ╱
                              ╱
                           ╱
                        ╱
                     ╱
                  ╱
            (●)╱
____________╱]],
    [[
                                   ╱
                         ○|￣|＿ ╱
                              ╱
                           ╱
                        ╱
                     ╱
                  ╱
            (●)╱
____________╱]],
    [[
                                    ╱
                                 ╱
                      ○|￣|＿ ╱
                           ╱
                        ╱
                     ╱
                  ╱
            (●)╱
____________╱]],
    [[
                                    ╱
                                 ╱
                              ╱
                   ○|￣|＿ ╱
                        ╱
                     ╱
                  ╱
            (●)╱
____________╱]],
    [[
                                    ╱
                                 ╱
                              ╱
                           ╱
                ○|￣|＿ ╱
                     ╱
                  ╱
            (●)╱
____________╱]],
    [[
                                    ╱
                                 ╱
                              ╱
                           ╱
                        ╱
             ○|￣|＿ ╱
                  ╱
            (●)╱
____________╱]],
    [[
                                    ╱
                                 ╱
                              ╱
                           ╱
                        ╱
                     ╱
     ＿|￣|○     ╱
            (●)╱
____________╱]],
    [[
                                    ╱
                                 ╱
                              ╱
                           ╱
                        ╱
                     ╱
                  ╱
            (●)╱
___＿|￣|○__╱]],
}

local function split_frame(frame)
    return vim.split(frame, "\n", {
        plain     = true,
        trimempty = true,
    })
end

local function stop_ui()
    M.token = M.token + 1

    if M.win and vim.api.nvim_win_is_valid(M.win) then
        vim.api.nvim_win_close(M.win, true)
    end

    if M.buf and vim.api.nvim_buf_is_valid(M.buf) then
        vim.api.nvim_buf_delete(M.buf, { force = true })
    end

    M.win = nil
    M.buf = nil
end

function M.stop()
    stop_ui()
    player:stop()
end

function M.display()
    if #M.frames == 0 then
        return result.err(M.Error.NOT_READY)
    end

    -- clean up any previous animation window (don't stop the player)
    stop_ui()

    -- ensure the player is set up (may not be if run before :Ambient start)
    if player.state.state == player.STATE.NOT_READY then
        player:setup({})
    end

    local music_result = music:new(bonus_music_path())
    if not music_result.ok then
        return result.err(M.Error.BONUS_MUSIC_ERR .. ": " .. music_result.err)
    end

    local play_err = player:play(music_result.value)
    if play_err then
        return result.err(M.Error.FAILED_TO_PLAY .. ": " .. play_err)
    end

    local width, height = 1, 1
    for _, frame in ipairs(M.frames) do
        local lines = split_frame(frame)
        height      = math.max(height, #lines)
        for _, line in ipairs(lines) do
            width = math.max(width, vim.fn.strdisplaywidth(line))
        end
    end

    M.buf = vim.api.nvim_create_buf(false, true)
    M.win = vim.api.nvim_open_win(M.buf, true, {
        relative = "editor",
        style    = "minimal",
        border   = "double",
        width    = width,
        height   = height,
        col      = math.floor(vim.o.columns - width),
        row      = 0,
    })

    vim.bo[M.buf].bufhidden = "wipe"

    local token       = M.token
    local frame_index = 1

    local function render()
        if token ~= M.token then
            return
        end

        if not M.buf or not vim.api.nvim_buf_is_valid(M.buf) then
            return
        end

        vim.api.nvim_buf_set_lines(
            M.buf,
            0,
            -1,
            false,
            split_frame(M.frames[frame_index])
        )

        frame_index = frame_index % #M.frames + 1
        vim.defer_fn(render, 500)
    end

    vim.keymap.set("n", "q", M.stop, {
        buffer = M.buf,
        silent = true,
    })

    vim.keymap.set("n", "<Esc>", M.stop, {
        buffer = M.buf,
        silent = true,
    })

    render()
    return result.ok(nil)
end

return M
