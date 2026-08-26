local M = {}

local result   = require("ambient.common.result")
local player   = require("ambient.player")
local schedule = require("ambient.schedule")
local uv       = vim.uv or vim.loop

M.window     = nil
M.buffer     = nil
M.timer      = nil
M.group      = nil
M.navigating = false

local preferred_width, height = 80, 5
local width                   = preferred_width

local function validWindow()
    return M.window ~= nil and vim.api.nvim_win_is_valid(M.window)
end

local function closeTimer()
    if M.timer ~= nil then
        pcall(M.timer.stop, M.timer)
        if not M.timer:is_closing() then pcall(M.timer.close, M.timer) end
    end
    M.timer = nil
end

local function formatTime(ms)
    local seconds = math.floor((ms or 0) / 1000)
    return string.format("%02d:%02d", math.floor(seconds / 60), seconds % 60)
end

local function trim(text, max_width)
    text = tostring(text or "")
    while vim.fn.strdisplaywidth(text) > max_width do
        text = vim.fn.strcharpart(text, 0, vim.fn.strchars(text) - 1)
    end
    return text
end

local function centered(text)
    text          = trim(text, width)
    local padding = width - vim.fn.strdisplaywidth(text)
    return string.rep(" ", math.floor(padding / 2)) .. text
        .. string.rep(" ", math.ceil(padding / 2))
end

function M:refresh()
    if not validWindow() or self.buffer == nil or not vim.api.nvim_buf_is_valid(self.buffer) then
        return result.err("WINDOW_CLOSED")
    end
    local current  = player.state.current
    local progress = player:getProgress()
    if current == nil or progress == nil then
        self:close("playback-ended")
        return result.err("NO_CURRENT_MUSIC")
    end
    local bar_width = width - 2
    local filled    = math.floor(bar_width * progress.percentage / 100)
    local bar       = "[" .. string.rep("=", filled) .. string.rep("-", bar_width - filled) .. "]"
    vim.api.nvim_buf_set_lines(self.buffer, 0, -1, false, {
        centered(current.name or current.abs_path or "Ambient"),
        centered(string.format("%s / %s   %3d%%", formatTime(progress.time_ms),
            formatTime(progress.duration_ms), progress.percentage)),
        centered(bar),
        centered("h/l: seek 5s    j: next    k: previous    q/Esc: close"),
        "",
    })
    return result.ok(nil)
end

function M:close(_)
    closeTimer()
    if validWindow() then pcall(vim.api.nvim_win_close, self.window, true) end
    if self.buffer ~= nil and vim.api.nvim_buf_is_valid(self.buffer) then
        pcall(vim.api.nvim_buf_delete, self.buffer, { force = true })
    end
    self.window, self.buffer = nil, nil
    return result.ok(nil)
end

function M:is_open()
    return validWindow()
end

local function map(buffer, lhs, callback)
    vim.keymap.set("n", lhs, callback, { buffer = buffer, nowait = true, silent = true })
end

function M:show()
    if self:is_open() then
        vim.api.nvim_set_current_win(self.window)
        self:refresh()
        return result.ok(true)
    end
    if player.state.current == nil or player:getProgress() == nil then
        return result.err("NO_CURRENT_MUSIC")
    end
    self.buffer                   = vim.api.nvim_create_buf(false, true)
    vim.bo[self.buffer].bufhidden = "wipe"
    width                         = math.max(24, math.min(preferred_width, vim.o.columns - 4))
    local row                     = math.max(0, vim.o.lines - vim.o.cmdheight - height - 2)
    local col                     = math.max(0, math.floor((vim.o.columns - width) / 2))
    self.window                   = vim.api.nvim_open_win(self.buffer, true, {
        relative = "editor",
        row = row,
        col = col,
        width = width,
        height = height,
        style = "minimal",
        border = "rounded",
        title = " Ambient progress ",
        title_pos = "center",
    })
    map(self.buffer, "q", function() self:close("key") end)
    map(self.buffer, "<Esc>", function() self:close("key") end)
    map(self.buffer, "h", function() if player:seekRelative(-5) == nil then self:refresh() end end)
    map(self.buffer, "l", function() if player:seekRelative(5) == nil then self:refresh() end end)
    map(self.buffer, "j", function()
        self.navigating = true; local r = schedule:next(); self.navigating = false
        if r.ok then self:refresh() end
    end)
    map(self.buffer, "k", function()
        self.navigating = true; local r = schedule:previous(); self.navigating = false
        if r.ok then self:refresh() end
    end)
    self:refresh()
    self.timer = uv.new_timer()
    self.timer:start(500, 500, vim.schedule_wrap(function() self:refresh() end))
    self.timer:unref()
    return result.ok(true)
end

function M:toggle()
    local ready = self:setup()
    if not ready.ok then return ready end
    if self:is_open() then
        self:close("toggle"); return result.ok(false)
    end
    return self:show()
end

function M:setup()
    if self.group == nil then
        self.group = vim.api.nvim_create_augroup("ambient_progress_window", { clear = true })
        vim.api.nvim_create_autocmd("WinLeave", {
            group = self.group,
            callback = function()
                -- WinLeave's match value differs between Neovim versions. Check the
                -- actual focused window after the transition instead of relying on it.
                vim.schedule(function()
                    if M:is_open() and vim.api.nvim_get_current_win() ~= M.window then
                        M:close("focus-lost")
                    end
                end)
            end
        })
    end
    return result.ok(nil)
end

return M
