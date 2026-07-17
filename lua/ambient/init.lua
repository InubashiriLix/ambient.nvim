local M = {}

local result   = require("ambient.result")
local config   = require("ambient.config")
local progress = require("ambient.progress")
local schedule = require("ambient.schedule")

local commands_registered = false

---@param key? string
---@return boolean
local function shouldNotify(key)
    local cfg = config.get()
    if not cfg.ok then
        return true
    end

    local notification = cfg.value.show_notification
    if notification.disable_all then
        return false
    end

    if key ~= nil and notification[key] == false then
        return false
    end

    return true
end

---@param message string
---@param level? integer
---@param key? string
local function notify(message, level, key)
    if not shouldNotify(key) then
        return
    end

    vim.notify(message, level or vim.log.levels.INFO, { title = "ambient.nvim" })
end

---@param status AmbientScheduleStatus
---@return string
local function formatStatus(status)
    if status.state == schedule.State.PLAYING and status.current_music_name ~= nil then
        return string.format("Ambient: %s (%s)", status.state, status.current_music_name)
    end

    if status.state == schedule.State.INTERVAL and status.next_due_in_ms ~= nil then
        return string.format("Ambient: %s, next in %ds", status.state,
            math.ceil(status.next_due_in_ms / 1000))
    end

    if status.last_error ~= nil then
        return string.format("Ambient: %s (%s)", status.state, status.last_error)
    end

    return string.format(
        "Ambient: %s, %d tracks in %d playlist(s)",
        status.state,
        status.total_music_count,
        status.playlist_count
    )
end

---@return AmbientResult<AmbientConfig, any>
local function ensureReady()
    if not config.is_ready() then
        return M.setup({})
    end

    local cfg = config.get()
    if not cfg.ok then
        return cfg
    end

    if not schedule:is_ready() then
        local scheduled = schedule:setup(cfg.value)
        if not scheduled.ok then
            return result.err(scheduled.err)
        end
    end

    return cfg
end

---@param r AmbientResult<any, any>
---@param ok_message? string
local function reportResult(r, ok_message)
    if r.ok then
        if ok_message ~= nil then
            notify(ok_message)
        end
        return
    end

    notify("Ambient error: " .. tostring(r.err), vim.log.levels.ERROR)
end

local function refreshProgress()
    progress:refresh()
end

function M.register_commands()
    if commands_registered then
        return
    end

    commands_registered = true

    vim.api.nvim_create_user_command("AmbientStart", function()
        reportResult(M.start())
    end, { desc = "Start ambient.nvim playback", force = true })

    vim.api.nvim_create_user_command("AmbientStop", function()
        reportResult(M.stop(), "Ambient stopped")
    end, { desc = "Stop ambient.nvim playback", force = true })

    vim.api.nvim_create_user_command("AmbientToggle", function()
        reportResult(M.toggle())
    end, { desc = "Toggle ambient.nvim playback", force = true })

    vim.api.nvim_create_user_command("AmbientNext", function()
        reportResult(M.next())
    end, { desc = "Play the next ambient.nvim track now", force = true })

    vim.api.nvim_create_user_command("AmbientStatus", function()
        local status = M.status()
        if status.ok then
            notify(formatStatus(status.value))
        else
            reportResult(status)
        end
    end, { desc = "Show ambient.nvim status", force = true })

    vim.api.nvim_create_user_command("AmbientProgressToggle", function()
        local toggled = M.toggle_progress()
        if toggled.ok then
            notify("Ambient progress " .. (toggled.value and "shown" or "hidden"))
        else
            reportResult(toggled)
        end
    end, { desc = "Toggle ambient.nvim statusline progress", force = true })
end

---@param opts? AmbientConfig
---@return AmbientResult<AmbientConfig, any>
function M.setup(opts)
    M.register_commands()

    local cfg = config.setup(opts)
    if not cfg.ok then
        notify("Invalid config: " .. tostring(config.get_error_message()), vim.log.levels.ERROR)
        return cfg
    end

    local scheduled = schedule:setup(cfg.value)
    if not scheduled.ok then
        notify("Schedule setup failed: " .. tostring(scheduled.err), vim.log.levels.ERROR)
        return result.err(scheduled.err)
    end

    local progress_ready = progress:setup(cfg.value)
    if not progress_ready.ok then
        notify("Progress setup failed: " .. tostring(progress_ready.err), vim.log.levels.ERROR)
        return result.err(progress_ready.err)
    end

    if cfg.value.show_notification.when_finish_setup then
        notify("Ambient setup finished", vim.log.levels.INFO, "when_finish_setup")
    end

    if cfg.value.show_notification.when_show_total_music_count then
        local status = schedule:get()
        if status.ok then
            notify(
                string.format("Ambient found %d tracks", status.value.total_music_count),
                vim.log.levels.INFO,
                "when_show_total_music_count"
            )
        end
    end

    return cfg
end

---@return AmbientResult<AmbientConfig, AmbientConfigError>
function M.get_config()
    return config.get()
end

---@return AmbientResult<nil, any>
function M.start()
    local ready = ensureReady()
    if not ready.ok then
        return result.err(ready.err)
    end

    if ready.value.enable == false then
        return result.err("disabled")
    end

    local started = schedule:start()
    refreshProgress()
    if started.ok then
        local status = schedule:get()
        if status.ok and status.value.current_music_name ~= nil then
            notify(
                "Ambient playing: " .. status.value.current_music_name,
                vim.log.levels.INFO,
                "when_start_playing"
            )
        end
    end

    return started
end

---@return AmbientResult<nil, any>
function M.stop()
    local stopped = schedule:stop()
    refreshProgress()
    return stopped
end

---@return AmbientResult<nil, any>
function M.pause()
    local paused = schedule:pause()
    refreshProgress()
    return paused
end

---@return AmbientResult<nil, any>
function M.toggle()
    local ready = ensureReady()
    if not ready.ok then
        return result.err(ready.err)
    end

    local toggled = schedule:toggle()
    refreshProgress()
    if toggled.ok then
        local status = schedule:get()
        if status.ok then
            notify(formatStatus(status.value), vim.log.levels.INFO, "when_toogle_playing_state")
        end
    end
    return toggled
end

---@return AmbientResult<nil, any>
function M.next()
    local ready = ensureReady()
    if not ready.ok then
        return result.err(ready.err)
    end

    local nexted = schedule:next()
    refreshProgress()
    return nexted
end

---@return AmbientResult<boolean, any>
function M.toggle_progress()
    return progress:toggle()
end

---@return AmbientResult<nil, any>
function M.show_progress()
    return progress:show()
end

---@return AmbientResult<nil, any>
function M.hide_progress()
    return progress:hide()
end

---@return string
function M.statusline()
    return progress:statusline()
end

---@return AmbientResult<AmbientScheduleStatus, any>
function M.status()
    return schedule:get()
end

return M
