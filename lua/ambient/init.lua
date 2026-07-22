local M = {}

require("ambient.typedef")

local result   = require("ambient.result")
local config   = require("ambient.config")
local progress = require("ambient.progress")
local schedule = require("ambient.schedule")

local commands_registered = false

local function stopPlaybackOnExit()
    pcall(schedule.stop, schedule)
end

---@param message string
---@param level? integer
---@param key? string
local function notify(message, level, key)
    local cfg = config.get()
    if cfg.ok then
        local notification = cfg.value.show_notification
        if notification.disable_all or (key ~= nil and notification[key] == false) then
            return
        end
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

---@generic T
---@param action fun(config: AmbientConfig): AmbientResult<T, any>
---@return AmbientResult<T, any>
local function withReady(action)
    if not config.is_ready() then
        local configured = M.setup()
        if not configured.ok then
            return configured
        end
        return action(configured.value)
    end

    local cfg = config.get()
    if not cfg.ok then
        return cfg
    end

    if not schedule:is_ready() then
        local scheduled = schedule:setup(cfg.value)
        if not scheduled.ok then
            return scheduled
        end
    end

    return action(cfg.value)
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

function M.register_commands()
    if commands_registered then
        return
    end

    commands_registered = true
    local group         = vim.api.nvim_create_augroup("ambient_lifecycle", { clear = true })
    vim.api.nvim_create_autocmd("VimLeavePre", {
        group    = group,
        desc     = "Stop ambient.nvim playback before Neovim exits",
        callback = stopPlaybackOnExit,
    })
    vim.api.nvim_create_autocmd("UILeave", {
        group    = group,
        desc     = "Stop ambient.nvim playback when the last UI disconnects",
        callback = function()
            if #vim.api.nvim_list_uis() == 0 then
                stopPlaybackOnExit()
            end
        end,
    })

    vim.api.nvim_create_user_command("AmbientStart", function()
        reportResult(M.start())
    end, { desc = "Start ambient.nvim playback", force = true })

    vim.api.nvim_create_user_command("AmbientStop", function()
        reportResult(M.stop(), "Ambient stopped")
    end, { desc = "Stop ambient.nvim playback", force = true })

    vim.api.nvim_create_user_command("AmbientPause", function()
        reportResult(M.pause(), "Ambient paused")
    end, { desc = "Pause ambient.nvim playback", force = true })

    vim.api.nvim_create_user_command("AmbientTogglePause", function()
        reportResult(M.toggle_pause_resume())
    end, { desc = "Toggle ambient.nvim pause/resume or start playback now", force = true })

    vim.api.nvim_create_user_command("AmbientToggleStop", function()
        reportResult(M.toggle_start_stop())
    end, { desc = "Toggle ambient.nvim start/stop", force = true })

    vim.api.nvim_create_user_command("AmbientNext", function()
        reportResult(M.next())
    end, { desc = "Play the next ambient.nvim track now", force = true })

    vim.api.nvim_create_user_command("AmbientPrevious", function()
        reportResult(M.previous())
    end, { desc = "Play the previous ambient.nvim track now", force = true })

    vim.api.nvim_create_user_command("AmbientPlaylist", function()
        reportResult(M.select_playlist_ui())
    end, { desc = "Select the active ambient.nvim playlist", force = true })

    vim.api.nvim_create_user_command("AmbientSelectMusic", function()
        reportResult(M.select_music_item())
    end, { desc = "Sort, select, and play an ambient.nvim track", force = true })

    vim.api.nvim_create_user_command("AmbientSelectCurrentPlaylistMusic", function()
        reportResult(M.select_current_playlist_music_item())
    end, { desc = "Select and play from the current ambient.nvim playlist position", force = true })

    vim.api.nvim_create_user_command("AmbientStatus", function()
        notify(formatStatus(schedule:getStatus()))
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
        return scheduled
    end

    local progress_ready = progress:setup(cfg.value)
    if not progress_ready.ok then
        notify("Progress setup failed: " .. tostring(progress_ready.err), vim.log.levels.ERROR)
        return progress_ready
    end

    if cfg.value.show_notification.when_finish_setup then
        notify("Ambient setup finished", vim.log.levels.INFO, "when_finish_setup")
    end

    if cfg.value.show_notification.when_show_total_music_count then
        local status = schedule:getStatus()
        notify(
            string.format("Ambient found %d tracks", status.total_music_count),
            vim.log.levels.INFO,
            "when_show_total_music_count"
        )
    end

    return cfg
end

---@return AmbientResult<AmbientConfig, AmbientConfigError>
function M.get_config()
    return config.get()
end

---@return AmbientResult<nil, any>
function M.start()
    local started = withReady(function(cfg)
        if cfg.enable == false then
            return result.err("disabled")
        end
        return schedule:start()
    end)
    progress:refresh()
    if started.ok then
        local status = schedule:getStatus()
        if status.current_music_name ~= nil then
            notify(
                "Ambient playing: " .. status.current_music_name,
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
    progress:refresh()
    return stopped
end

---@return AmbientResult<nil, any>
function M.pause()
    local paused = schedule:pause()
    progress:refresh()
    return paused
end

---@return AmbientResult<nil, any>
function M.toggle_pause_resume()
    local toggled = withReady(function()
        return schedule:togglePauseResumeOrStartNow()
    end)
    progress:refresh()
    if toggled.ok then
        notify(formatStatus(schedule:getStatus()), vim.log.levels.INFO, "when_toggle_playing_state")
    end
    return toggled
end

---@return AmbientResult<nil, any>
function M.toggle_start_stop()
    local toggled = withReady(function()
        return schedule:toggleStartStop()
    end)
    progress:refresh()
    if toggled.ok then
        notify(formatStatus(schedule:getStatus()), vim.log.levels.INFO, "when_toggle_playing_state")
    end
    return toggled
end

---@return AmbientResult<nil, any>
function M.next()
    local nexted = withReady(function()
        return schedule:next()
    end)
    progress:refresh()
    return nexted
end

---@return AmbientResult<nil, any>
function M.previous()
    local previous = withReady(function()
        return schedule:previous()
    end)
    progress:refresh()
    return previous
end

---@param index integer
---@return AmbientResult<nil, any>
function M.select_playlist(index)
    local selected = withReady(function()
        return schedule:selectPlaylist(index)
    end)
    progress:refresh()

    return selected
end

---@return AmbientResult<nil, any>
function M.select_playlist_ui()
    return withReady(function()
        return schedule:displayPlaylistSelectorUi(function(selected)
            if not selected.ok then
                reportResult(selected)
                return
            end

            progress:refresh()
            notify("Ambient playlist: " .. selected.value.name)
        end)
    end)
end

---@return AmbientResult<nil, any>
function M.select_music_item()
    return withReady(function()
        return schedule:displayMusicSelectorUi(function(selected)
            if not selected.ok then
                reportResult(selected)
                return
            end

            progress:refresh()
            notify("Ambient music: " .. selected.value.name)
        end)
    end)
end

---@return AmbientResult<nil, any>
function M.select_current_playlist_music_item()
    return withReady(function()
        return schedule:displayCurrentPlaylistMusicSelectorUi(function(selected)
            if not selected.ok then
                reportResult(selected)
                return
            end

            progress:refresh()
            notify("Ambient music: " .. selected.value.name)
        end)
    end)
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
