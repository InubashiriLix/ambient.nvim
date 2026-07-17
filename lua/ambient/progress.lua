local M = {}

local result   = require("ambient.result")
local schedule = require("ambient.schedule")

local uv = vim.uv or vim.loop

local default_config = {
    enabled            = false,
    width              = 42,
    name_width         = 18,
    bar_width          = 10,
    show_time          = true,
    scroll             = false,
    scroll_separator   = "  ",
    update_interval_ms = 500,
    border             = {
        enabled = false,
        left    = "",
        right   = "",
        padding = " ",
    },
    lualine_separator  = {
        left  = "",
        right = "",
    },
    color              = {
        fg  = "#ffffff",
        bg  = "#5b7ee5",
        gui = "bold",
    },
    colors             = {},
}

M.config                     = vim.deepcopy(default_config)
M.visible                    = false
M.timer                      = nil
M.lualine_registered         = false
M.lualine_autocmd_registered = false
M.refresh_autocmd_registered = false

---@param value string
---@return string
local function sanitize(value)
    return tostring(value or ""):gsub("[\r\n]", " ")
end

---@param value string
---@return string
local function escapeStatusline(value)
    return sanitize(value):gsub("%%", "%%%%")
end

---@param value integer
---@param min integer
---@param max integer
---@return integer
local function clamp(value, min, max)
    return math.max(min, math.min(max, value))
end

---@return integer
local function statusWidth()
    return M.config.width or default_config.width
end

---@return string, string
local function borderParts()
    local border = M.config.border or default_config.border
    if not border.enabled then
        return "", ""
    end

    local padding = border.padding or " "
    local left = border.left or ""
    local right = border.right or ""
    local left_part = left ~= "" and left .. padding or ""
    local right_part = right ~= "" and padding .. right or ""
    return left_part, right_part
end

---@return integer
local function contentWidth()
    local left, right = borderParts()
    return math.max(0, statusWidth() - vim.fn.strdisplaywidth(left) - vim.fn.strdisplaywidth(right))
end

---@param value string
---@param max_chars integer
---@return string
local function trimToWidth(value, max_chars)
    if max_chars <= 0 then
        return ""
    end

    local text = sanitize(value)
    while vim.fn.strdisplaywidth(text) > max_chars do
        local chars = vim.fn.strchars(text)
        if chars <= 1 then
            return ""
        end
        text = vim.fn.strcharpart(text, 0, chars - 1)
    end
    return text
end

---@param value string
---@param max_chars integer
---@return string
local function truncate(value, max_chars)
    value = sanitize(value)
    if vim.fn.strdisplaywidth(value) <= max_chars then
        return value
    end

    return trimToWidth(value, max_chars - 1) .. "~"
end

---@param value string
---@param width integer
---@return string
local function centerToWidth(value, width)
    if width <= 0 then
        return ""
    end

    local text = trimToWidth(value, width)
    local padding = width - vim.fn.strdisplaywidth(text)
    local left = math.floor(padding / 2)
    local right = padding - left
    return string.rep(" ", left) .. text .. string.rep(" ", right)
end

---@param value string
---@return string
local function frameContent(value)
    local left, right = borderParts()
    local inner_width = contentWidth()
    local content = centerToWidth(value, inner_width)
    return trimToWidth(left .. content .. right, statusWidth())
end

---@param value string
---@param width integer
---@return string
local function scroll(value, width)
    value = sanitize(value)
    if vim.fn.strdisplaywidth(value) <= width then
        return value
    end

    local separator = M.config.scroll_separator or "  "
    local source = value .. separator
    local chars = vim.fn.strchars(source)
    if chars == 0 then
        return ""
    end

    local step = math.floor((uv.now() or 0) / M.config.update_interval_ms) % chars
    local doubled = source .. source
    return trimToWidth(vim.fn.strcharpart(doubled, step, width + 2), width)
end

---@param value string
---@param width integer
---@return string
local function renderName(value, width)
    if width <= 0 then
        return ""
    end

    if M.config.scroll then
        return centerToWidth(scroll(value, width), width)
    end

    return centerToWidth(truncate(value, width), width)
end

---@return integer
local function effectiveBarWidth()
    local width = contentWidth()
    local fixed_without_bar = 2 + 1 + 4
    if M.config.show_time then
        fixed_without_bar = fixed_without_bar + 11 + 1
    end

    local max_bar_width = math.max(1, width - fixed_without_bar)
    return clamp(M.config.bar_width or default_config.bar_width, 1, max_bar_width)
end

---@param percentage integer?
---@return string
local function renderBar(percentage)
    percentage = clamp(percentage or 0, 0, 100)
    local width = effectiveBarWidth()
    local filled = math.floor((percentage / 100) * width)
    local empty = width - filled
    return string.rep("█", filled) .. string.rep("░", empty)
end

---@param ms integer?
---@return string
local function formatFixedTime(ms)
    ms = ms or 0
    local total_seconds = math.floor(ms / 1000)
    local minutes = math.floor(total_seconds / 60)
    local seconds = total_seconds % 60
    if minutes > 99 then
        minutes = 99
        seconds = 59
    end
    return string.format("%02d:%02d", minutes, seconds)
end

---@param current_ms integer?
---@param duration_ms integer?
---@return string
local function renderTime(current_ms, duration_ms)
    return formatFixedTime(current_ms) .. "/" .. formatFixedTime(duration_ms)
end

---@param percentage integer?
---@return string
local function renderPercentage(percentage)
    return string.format("%3d%%", clamp(percentage or 0, 0, 100))
end

---@return string
local function currentStateKey()
    local status = schedule:get()
    if not status.ok or status.value.last_error ~= nil then
        return "error"
    end

    return tostring(status.value.state or "default"):lower()
end

local function refreshStatus()
    local ok, lualine = pcall(require, "lualine")
    if ok and type(lualine.refresh) == "function" then
        pcall(lualine.refresh, {
            place = { "statusline" },
        })
    end

    pcall(vim.cmd, "redrawstatus!")
end

---@return table
local function componentColor()
    local base = vim.deepcopy(M.config.color or default_config.color)
    local colors = M.config.colors or {}
    local override = colors[currentStateKey()] or colors.default
    if type(override) == "table" then
        return vim.tbl_deep_extend("force", base, override)
    end

    return base
end

local function lualineColor()
    return componentColor()
end

---@param component table
---@return boolean
local function applyLualineComponentOptions(component)
    local separator = M.config.lualine_separator or default_config.lualine_separator
    local padding   = { left = 0, right = 0 }
    local changed   = component.color ~= lualineColor
        or not vim.deep_equal(component.separator, separator)
        or not vim.deep_equal(component.padding, padding)

    component.color            = lualineColor
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

local function ensureRefreshAutocmd()
    if M.refresh_autocmd_registered then
        return
    end

    M.refresh_autocmd_registered = true
    local group = vim.api.nvim_create_augroup("ambient_progress_refresh", { clear = true })
    vim.api.nvim_create_autocmd("User", {
        group = group,
        pattern = "AmbientStateChanged",
        callback = function()
            refreshStatus()
            vim.defer_fn(refreshStatus, 20)
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
    local width = contentWidth()

    if status.state == schedule.State.PLAYING then
        local percentage = status.progress_percentage or 0
        local bar        = renderBar(percentage)
        local suffix
        if M.config.show_time then
            suffix = string.format(
                "%s [%s] %s",
                renderTime(status.current_time_ms, status.duration_ms),
                bar,
                renderPercentage(percentage)
            )
        else
            suffix = string.format("[%s] %s", bar, renderPercentage(percentage))
        end

        local suffix_width = vim.fn.strdisplaywidth(suffix)
        local name_width = math.min(M.config.name_width or default_config.name_width, math.max(0, width - suffix_width - 1))
        local name = renderName(status.current_music_name or "ambient", name_width)
        local content = suffix
        if name_width > 0 then
            content = name .. " " .. suffix
        end

        return escapeStatusline(frameContent(content))
    end

    if status.state == schedule.State.INTERVAL and status.next_due_in_ms ~= nil then
        return frameContent(string.format("wait %ds", math.ceil(status.next_due_in_ms / 1000)))
    end

    if status.state == schedule.State.READY then
        return frameContent(string.format("ready (%d tracks)", status.total_music_count or 0))
    end

    if status.last_error ~= nil then
        return frameContent("ambient error")
    end

    return frameContent("ambient " .. status.state)
end

---@param config AmbientConfig
---@return AmbientResult<nil, nil>
function M:setup(config)
    self.config  = vim.tbl_deep_extend("force", vim.deepcopy(default_config), config.progress or {})
    self.visible = self.config.enabled == true
    ensureLualineRegistration()
    ensureRefreshAutocmd()

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
    ensureRefreshAutocmd()
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

---@return AmbientResult<nil, nil>
function M:refresh()
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
