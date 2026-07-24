local M = {}

require("ambient.typedef")

local result      = require("ambient.result")
local config      = require("ambient.config")
local progress    = require("ambient.progress")
local schedule    = require("ambient.schedule")
local track_popup = require("ambient.track_popup")

local commands_registered = false
local popup_events_registered = false

local function stopPlaybackOnExit()
    track_popup:close("exit")
    pcall(schedule.stop, schedule)
end

local function registerPopupEvents()
    if popup_events_registered then
        return
    end

    popup_events_registered = true
    local group             = vim.api.nvim_create_augroup("ambient_track_popup", { clear = true })

    vim.api.nvim_create_autocmd("User", {
        group    = group,
        pattern  = "AmbientTrackChanged",
        desc     = "Show the ambient.nvim track popup",
        callback = function()
            if schedule.current_music ~= nil then
                track_popup:show(schedule.current_music)
            end
        end,
    })

    vim.api.nvim_create_autocmd("User", {
        group    = group,
        pattern  = "AmbientTrackInfoUpdated",
        desc     = "Refresh ambient.nvim track metadata and cover art",
        callback = function()
            local item = schedule.current_music
            if item == nil
                or not track_popup:is_open()
                or track_popup.current_key ~= (item.abs_path or item.name)
            then
                return
            end

            local updated = track_popup:update(item)
            if updated.ok then
                track_popup:refresh()
            end
        end,
    })

    vim.api.nvim_create_autocmd("User", {
        group    = group,
        pattern  = "AmbientStateChanged",
        desc     = "Close the ambient.nvim track popup when playback ends",
        callback = function()
            if schedule.current_music == nil then
                track_popup:close("playback-ended")
            end
        end,
    })
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

    ---@class AmbientCommandNode
    ---@field run? fun()
    ---@field children? table<string, AmbientCommandNode>

    ---@type AmbientCommandNode
    local command_root = {
        children = {
            start = {
                run = function()
                    reportResult(M.start())
                end,
            },
            stop = {
                run = function()
                    reportResult(M.stop(), "Ambient stopped")
                end,
            },
            pause = {
                run = function()
                    reportResult(M.pause(), "Ambient paused")
                end,
            },
            next = {
                run = function()
                    reportResult(M.next())
                end,
            },
            previous = {
                run = function()
                    reportResult(M.previous())
                end,
            },
            status = {
                run = function()
                    notify(formatStatus(schedule:getStatus()))
                end,
            },
            display = {
                run = function()
                    reportResult(M.show_current_track())
                end,
            },
            toggle = {
                children = {
                    pause = {
                        run = function()
                            reportResult(M.toggle_pause_resume())
                        end,
                    },
                    stop = {
                        run = function()
                            reportResult(M.toggle_start_stop())
                        end,
                    },
                },
            },
            select = {
                children = {
                    playlist = {
                        run = function()
                            reportResult(M.select_playlist_ui())
                        end,
                    },
                    music = {
                        run = function()
                            reportResult(M.select_music_item())
                        end,
                    },
                    ["current-playlist-music"] = {
                        run = function()
                            reportResult(M.select_current_playlist_music_item())
                        end,
                    },
                },
            },
            progress = {
                children = {
                    toggle = {
                        run = function()
                            local toggled = M.toggle_progress()
                            if toggled.ok then
                                notify("Ambient progress " .. (toggled.value and "shown" or "hidden"))
                            else
                                reportResult(toggled)
                            end
                        end,
                    },
                },
            },
        },
    }

    vim.api.nvim_create_user_command("Ambient", function(opts)
        local node = command_root
        for token in opts.args:gmatch("%S+") do
            if node.children == nil or node.children[token] == nil then
                notify("Unknown Ambient command: " .. opts.args, vim.log.levels.ERROR)
                return
            end
            node = node.children[token]
        end

        if node.run == nil then
            local available = {}
            for name in pairs(node.children or {}) do
                table.insert(available, name)
            end
            table.sort(available)
            notify("Ambient subcommand required: " .. table.concat(available, ", "), vim.log.levels.ERROR)
            return
        end

        node.run()
    end, {
        nargs = "*",
        desc = "Control ambient.nvim",
        force = true,
        complete = function(arg_lead, cmd_line, cursor_pos)
            local before_cursor = cmd_line:sub(1, cursor_pos)
            local args          = before_cursor:match("^%s*:?[Aa]mbient%s?(.*)$") or ""
            local tokens        = {}
            for token in args:gmatch("%S+") do
                table.insert(tokens, token)
            end

            -- The last token is the partial argument represented by arg_lead.
            if args:match("%S$") then
                table.remove(tokens)
            end

            local node = command_root
            for _, token in ipairs(tokens) do
                if node.children == nil or node.children[token] == nil then
                    return {}
                end
                node = node.children[token]
            end

            local matches = {}
            for name in pairs(node.children or {}) do
                if name:sub(1, #arg_lead) == arg_lead then
                    table.insert(matches, name)
                end
            end
            table.sort(matches)
            return matches
        end,
    })
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
        local detail  = schedule:get_error_message()
        local message = "Schedule setup failed: " .. tostring(scheduled.err)
        if detail ~= nil and detail ~= tostring(scheduled.err) then
            message = message .. " (" .. detail .. ")"
        end
        notify(message, vim.log.levels.ERROR)
        return scheduled
    end

    for _, warning in ipairs(schedule:getStatus().playlist_warnings or {}) do
        notify(
            string.format("Skipped playlist %s: %s", warning.path, warning.error),
            vim.log.levels.WARN
        )
    end

    local progress_ready = progress:setup(cfg.value)
    if not progress_ready.ok then
        notify("Progress setup failed: " .. tostring(progress_ready.err), vim.log.levels.ERROR)
        return progress_ready
    end

    local popup_ready = track_popup:setup(cfg.value.track_popup)
    if not popup_ready.ok then
        notify("Track popup setup failed: " .. tostring(popup_ready.err), vim.log.levels.ERROR)
        return popup_ready
    end
    registerPopupEvents()

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

---@param duration_ms? integer
---@return AmbientResult<nil, any>
function M.show_current_track(duration_ms)
    if schedule.current_music == nil then
        return result.err("NO_CURRENT_MUSIC")
    end

    return track_popup:show(schedule.current_music, duration_ms)
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
