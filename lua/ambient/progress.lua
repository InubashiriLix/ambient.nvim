local M = {}

local result   = require("ambient.result")
local schedule = require("ambient.schedule")

local uv = vim.uv or vim.loop

local default_config = {
    enabled            = false,
    update_interval_ms = 500,
    color              = {
        fg  = "#ffffff",
        bg  = "#5b7ee5",
        gui = "bold",
    },
}

M.config                     = vim.deepcopy(default_config)
M.visible                    = false
M.timer                      = nil
M.lualine_registered         = false
M.lualine_autocmd_registered = false

---@param ms integer?
---@return string
local function formatTime(ms)
    ms                  = ms or 0
    local total_seconds = math.floor(ms / 1000)
    local minutes       = math.floor(total_seconds / 60)
    local seconds       = total_seconds % 60
    return string.format("%d:%02d", minutes, seconds)
end

---@param value string
---@param max_chars integer
---@return string
local function truncate(value, max_chars)
    if vim.fn.strdisplaywidth(value) <= max_chars then
        return value
    end

    return vim.fn.strcharpart(value, 0, max_chars - 1) .. "~"
end

local function refreshStatus()
    local ok, lualine = pcall(require, "lualine")
    if ok and type(lualine.refresh) == "function" then
        pcall(lualine.refresh, {
            place = { "statusline" },
        })
    end

    pcall(vim.cmd, "redrawstatus")
end

---@return table
local function componentColor()
    return vim.deepcopy(M.config.color or default_config.color)
end

---@param component table
---@return boolean
local function applyLualineComponentOptions(component)
    local color     = componentColor()
    local separator = { left = "", right = "" }
    local padding   = { left = 1, right = 1 }
    local changed   = not vim.deep_equal(component.color, color)
        or not vim.deep_equal(component.separator, separator)
        or not vim.deep_equal(component.padding, padding)

    component.color            = color
    component.separator        = separator
    component.padding          = padding
    component.ambient_progress = true

    return changed
end

local function lualineComponent()
    local component = {
        function()
            local ok, ambient = pcall(require, "ambient")
            if not ok then
                return ""
            end
            return ambient.statusline()
        end,
        cond = function()
            local ok, ambient = pcall(require, "ambient")
            return ok and ambient.statusline() ~= ""
        end,
    }
    applyLualineComponentOptions(component)
    return component
end

local function registerLualine()
    local ok, lualine = pcall(require, "lualine")
    if not ok or type(lualine.get_config) ~= "function" or type(lualine.setup) ~= "function" then
        return
    end

    local cfg              = lualine.get_config()
    cfg.sections           = cfg.sections or {}
    cfg.sections.lualine_x = cfg.sections.lualine_x or {}

    for _, component in ipairs(cfg.sections.lualine_x) do
        if type(component) == "table" and component.ambient_progress == true then
            local changed = applyLualineComponentOptions(component)
            if changed then
                lualine.setup(cfg)
            end
            M.lualine_registered = true
            refreshStatus()
            return
        end
    end

    table.insert(cfg.sections.lualine_x, 1, lualineComponent())
    lualine.setup(cfg)
    M.lualine_registered = true
    refreshStatus()
end

local function ensureLualineRegistration()
    registerLualine()
    vim.schedule(registerLualine)
    vim.defer_fn(registerLualine, 1000)

    if M.lualine_autocmd_registered then
        return
    end

    M.lualine_autocmd_registered = true
    local group                  = vim.api.nvim_create_augroup("ambient_lualine_progress",
        { clear = true })
    vim.api.nvim_create_autocmd("User", {
        group    = group,
        pattern  = { "VeryLazy", "LazyVimStarted" },
        callback = function()
            vim.schedule(registerLualine)
        end,
    })
end

local function startTimer()
    if M.timer ~= nil then
        return
    end

    M.timer = uv.new_timer()
    M.timer:start(0, M.config.update_interval_ms, vim.schedule_wrap(refreshStatus))
    if M.timer.unref ~= nil then
        M.timer:unref()
    end
end

local function stopTimer()
    if M.timer == nil then
        return
    end

    pcall(function()
        M.timer:stop()
        if not M.timer:is_closing() then
            M.timer:close()
        end
    end)

    M.timer = nil
end

---@param status AmbientScheduleStatus
---@return string
local function renderStatusline(status)
    if status.state == schedule.State.PLAYING then
        local percentage = status.progress_percentage or 0
        local name       = truncate(status.current_music_name or "ambient", 18)
        return string.format(
            "%s/%s (%s) (%d%%)",
            formatTime(status.current_time_ms),
            formatTime(status.duration_ms),
            name,
            percentage
        )
    end

    if status.state == schedule.State.INTERVAL and status.next_due_in_ms ~= nil then
        return string.format("wait %ds (ambient)", math.ceil(status.next_due_in_ms / 1000))
    end

    if status.state == schedule.State.READY then
        return string.format("ready (%d tracks)", status.total_music_count or 0)
    end

    if status.last_error ~= nil then
        return "ambient error"
    end

    return "ambient " .. status.state
end

---@param config AmbientConfig
---@return AmbientResult<nil, nil>
function M:setup(config)
    self.config  = vim.tbl_deep_extend("force", vim.deepcopy(default_config), config.progress or {})
    self.visible = self.config.enabled == true
    ensureLualineRegistration()

    if self.visible then
        startTimer()
    else
        stopTimer()
    end

    refreshStatus()
    return result.ok(nil)
end

---@return AmbientResult<nil, nil>
function M:show()
    self.visible = true
    ensureLualineRegistration()
    startTimer()
    refreshStatus()
    return result.ok(nil)
end

---@return AmbientResult<nil, nil>
function M:hide()
    self.visible = false
    stopTimer()
    refreshStatus()
    return result.ok(nil)
end

---@return AmbientResult<boolean, nil>
function M:toggle()
    if self.visible then
        self:hide()
        return result.ok(false)
    end

    self:show()
    return result.ok(true)
end

---@return boolean
function M:is_visible()
    return self.visible
end

---@return string
function M:statusline()
    if not self.visible then
        return ""
    end

    local status = schedule:get()
    if not status.ok then
        return "ambient error"
    end

    return renderStatusline(status.value)
end

return M
