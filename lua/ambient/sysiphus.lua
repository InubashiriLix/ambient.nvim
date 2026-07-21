---A bunny egg module. just printout the animation of Sysiphus and play the music of Sysiphus.
---@author [InubashiriLix](https://github.com/InubashiriLix)
---@license [DBAD](https://github.com/philsturgeon/dbad)

local result = require("ambient.result")
local music  = require("ambient.music")

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
    NOT_READY = "NOT_REDAY",
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
                       ＿|￣|○      ╱
                                 ╱
                              ╱
                           ╱
                        ╱
                     ╱
                  ╱
            (●)╱
____________╱]],
    [[
                       ~( -_- )~    ╱
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
                    ~( ._. )~    ╱
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
                 ~( -_- )~    ╱
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
              ~( ._. )~    ╱
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
           ~( -_- )~    ╱
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
        ~( ._. )~    ╱
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
     ~( -_- )~    ╱
            (●)╱
____________╱]],
}

local function split_frame(frame)
    return vim.split(frame, "\n", {
        plain     = true,
        trimempty = true,
    })
end

function M.stop()
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

function M.display()
    if #M.frames == 0 then
        return result.err(M.Error.NOT_READY)
    end

    M.stop()

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
        -- right up corner
        col      = math.floor((vim.o.columns - width)),
        row      = math.floor(0),
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
