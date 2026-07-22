local result   = require("ambient.result")
local playlist = require("ambient.playlist")
local selector = require("ambient.playlist_selector")
local player   = require("ambient.player")

local uv = vim.uv or vim.loop

---@alias AmbientPlayerScheduleMode "interval_random" | "interval_sequential" | "without_interval_random" | "without_interval_sequential" | "intermittently" | "continuous" | "continously"

---@enum AmbientScheduleError
local Error = {
    CONFIG_NOT_READY        = "CONFIG_NOT_READY",
    PLAYLIST_CONFIG_ERROR   = "PLAYLIST_CONFIG_ERROR",
    PLAYLIST_SELECTOR_ERROR = "PLAYLIST_SELECTOR_ERROR",
    EMPTY_PLAYLIST          = "EMPTY_PLAYLIST",
    PLAYER_ERROR            = "PLAYER_ERROR",
    TIMER_CREATE_FAILED     = "TIMER_CREATE_FAILED",
    NO_PREVIOUS_MUSIC       = "NO_PREVIOUS_MUSIC",
}

---@enum ScheduleState
local State = {
    INIT     = "INIT",
    LOADING  = "LOADING",
    READY    = "READY",
    STOPPED  = "STOPPED",
    PAUSED   = "PAUSED",
    PLAYING  = "PLAYING",
    INTERVAL = "INTERVAL",
    NEXT     = "NEXT",
    ERROR    = "ERROR",
    FINISH   = "FINISH",
}

---@class AmbientScheduleStatus
---@field state ScheduleState
---@field mode? AmbientPlayerScheduleMode
---@field playlist_count integer
---@field total_music_count integer
---@field current_playlist_name? string
---@field current_playlist_path? string
---@field current_playlist_music_count? integer
---@field current_music_name? string
---@field current_music_path? string
---@field current_time_ms? integer
---@field duration_ms? integer
---@field progress_percentage? integer
---@field next_due_in_ms? integer
---@field last_error? string

---@class AmbientTimer
---@field start fun(self: AmbientTimer, timeout: integer, repeat_ms: integer, callback: fun())
---@field stop fun(self: AmbientTimer)
---@field is_closing fun(self: AmbientTimer): boolean
---@field close fun(self: AmbientTimer)

---@class AmbientSchedule
---@field Error table<string, AmbientScheduleError>
---@field State table<string, ScheduleState>
---@field state ScheduleState
---@field config? AmbientConfig
---@field playlists AmbientPlayList[]
---@field current_music? AmbientMusic
---@field current_entry? AmbientPlaybackEntry
---@field history AmbientPlaybackEntry[] Tracks before current_entry, oldest first.
---@field future AmbientPlaybackEntry[] Tracks undone by previous(), nearest next track last.
---@field total_music_count integer
---@field interval_timer? AmbientTimer
---@field event_timer? AmbientTimer
---@field next_due_time_ms? integer
---@field last_error? string
---@field random_seed_initialized boolean
local M = {
    Error                   = Error,
    State                   = State,
    state                   = State.INIT,
    playlists               = {},
    history                 = {},
    future                  = {},
    total_music_count       = 0,
    random_seed_initialized = false,
}

local playNow
local scheduleNext

---@param state ScheduleState
local function setState(state)
    M.state = state
    vim.schedule(function()
        pcall(vim.api.nvim_exec_autocmds, "User", {
            pattern  = "AmbientStateChanged",
            modeline = false,
        })
    end)
end

---@param timer_name "interval_timer" | "event_timer"
local function closeTimer(timer_name)
    ---@type AmbientTimer?
    local timer
    if timer_name == "interval_timer" then
        timer = M.interval_timer
    else
        timer = M.event_timer
    end
    if timer ~= nil then
        pcall(function()
            timer:stop()
            if not timer:is_closing() then
                timer:close()
            end
        end)
    end
    if timer_name == "interval_timer" then
        M.interval_timer = nil
    else
        M.event_timer = nil
    end
end

local function closeAllTimers()
    closeTimer("interval_timer")
    closeTimer("event_timer")
    M.next_due_time_ms = nil
end

local function resetToReadyAfterPlaylistSelection()
    closeAllTimers()
    player:shutdown()
    M.current_music    = nil
    M.current_entry    = nil
    M.history          = {}
    M.future           = {}
    M.next_due_time_ms = nil
    M.last_error       = nil
    setState(M.State.READY)
end

---@param err AmbientScheduleError
---@param message? string
---@return AmbientErr<AmbientScheduleError>
local function fail(err, message)
    closeAllTimers()
    M.last_error = message or err
    setState(M.State.ERROR)
    return result.err(err)
end

---@class AmbientPlaybackEntry
---@field music AmbientMusic
---@field playlist AmbientPlayList
---@field sorted_indices integer[] Immutable playlist order used when this track was taken.
---@field cursor integer Playlist cursor immediately after this track was taken.

---@param item AmbientPlayList
---@return AmbientPlaybackEntry?
local function takeMusicFromPlaylist(item)
    if item:isEmpty() then
        return nil
    end

    local current = item:getCurrent()
    if current == nil then
        item:reset()
        current = item:getCurrent()
    end

    if current == nil then
        return nil
    end

    if item:hasNext() then
        item:next()
    elseif item.sort_field == playlist.SortField.random then
        item:sort()
    else
        item:reset()
    end

    return {
        music          = current,
        playlist       = item,
        sorted_indices = item.sorted_indices,
        cursor         = item.cursor,
    }
end

---@return AmbientResult<nil, AmbientScheduleError>
local function startEventTimer()
    closeTimer("event_timer")

    local timer = uv.new_timer()
    if timer == nil then
        return fail(M.Error.TIMER_CREATE_FAILED)
    end

    M.event_timer = timer
    timer:start(500, 500, vim.schedule_wrap(function()
        if M.state ~= M.State.PLAYING then
            return
        end

        local events = player:drainEvents()
        for _, event in ipairs(events) do
            if event.event == "end-file" then
                if event.reason ~= "stop" and event.reason ~= "replaced" then
                    M.current_music = nil

                    if event.reason == "error" then
                        M.last_error = "mpv failed to play current file"
                        scheduleNext(0)
                        return
                    end

                    local mode = M.config.mode
                    if mode == "without_interval_random"
                        or mode == "without_interval_sequential"
                        or mode == "continuous"
                        or mode == "continously"
                    then
                        scheduleNext(0)
                    else
                        local interval = M.config.interval
                        local delay_ms = interval.min_ms
                        if interval.min_ms ~= interval.max_ms then
                            delay_ms = math.random(interval.min_ms, interval.max_ms)
                        end
                        scheduleNext(delay_ms)
                    end
                    return
                end
            elseif event.event == "shutdown" then
                fail(M.Error.PLAYER_ERROR, "mpv was closed")
                return
            end
        end
    end))

    return result.ok(nil)
end

---@param delay_ms integer
---@return AmbientResult<nil, AmbientScheduleError>
scheduleNext = function(delay_ms)
    closeTimer("event_timer")
    closeTimer("interval_timer")

    if M.state == M.State.STOPPED then
        return result.ok(nil)
    end

    if delay_ms <= 0 then
        M.next_due_time_ms = nil
        setState(M.State.NEXT)
        vim.schedule(function()
            if M.state ~= M.State.STOPPED then
                playNow()
            end
        end)
        return result.ok(nil)
    end

    local timer = uv.new_timer()
    if timer == nil then
        return fail(M.Error.TIMER_CREATE_FAILED)
    end

    M.interval_timer   = timer
    M.next_due_time_ms = uv.now() + delay_ms
    setState(M.State.INTERVAL)

    timer:start(delay_ms, 0, vim.schedule_wrap(function()
        closeTimer("interval_timer")
        if M.state ~= M.State.STOPPED then
            playNow()
        end
    end))

    return result.ok(nil)
end

---@param direction "next" | "previous"
---@param discard_future? boolean
---@return AmbientResult<nil, AmbientScheduleError>
local function playAdjacent(direction, discard_future)
    local entry
    local from_future = false
    if direction == "previous" then
        entry = M.history[#M.history]
        if entry == nil then
            return result.err(M.Error.NO_PREVIOUS_MUSIC)
        end
    else
        if discard_future then
            M.future = {}
        end
        from_future = #M.future > 0
        if from_future then
            entry = M.future[#M.future]
        else
            local selected = selector:getCurrentPlayListValue()
            if selected ~= nil then
                entry = takeMusicFromPlaylist(selected)
            end
        end
        if entry == nil then
            return fail(M.Error.EMPTY_PLAYLIST)
        end
    end

    closeTimer("interval_timer")
    closeTimer("event_timer")
    player:drainEvents()

    -- Each history entry remembers which playlist position follows its track.
    entry.playlist.sorted_indices = entry.sorted_indices
    entry.playlist.cursor         = entry.cursor
    local player_error            = player:play(entry.music)
    if player_error ~= nil then
        return fail(M.Error.PLAYER_ERROR, player_error)
    end

    if direction == "previous" then
        table.remove(M.history)
        if M.current_entry ~= nil then
            table.insert(M.future, M.current_entry)
        end
    else
        if from_future then
            table.remove(M.future)
        end
        if M.current_entry ~= nil then
            table.insert(M.history, M.current_entry)
        end
    end

    M.current_entry    = entry
    M.current_music    = entry.music
    M.next_due_time_ms = nil
    M.last_error       = nil
    setState(M.State.PLAYING)

    return startEventTimer()
end

---@return AmbientResult<nil, AmbientScheduleError>
playNow = function()
    return playAdjacent("next")
end

---@param config AmbientConfig
---@return AmbientResult<nil, AmbientScheduleError>
function M:setup(config)
    if not self.random_seed_initialized then
        math.randomseed(os.time() + (uv.hrtime() % 1000000))
        math.random()
        self.random_seed_initialized = true
    end
    closeAllTimers()
    player:shutdown()

    self.config            = config
    self.playlists         = {}
    self.current_music     = nil
    self.current_entry     = nil
    self.history           = {}
    self.future            = {}
    self.total_music_count = 0
    self.last_error        = nil
    selector:reset()

    for _, playlist_config in ipairs(config.playlists or {}) do
        local created = playlist:new(
            playlist_config.abs_path,
            playlist_config.ext,
            playlist_config.recursive_depth,
            playlist_config.sort_field,
            playlist_config.sort_direction
        )

        if not created.ok then
            return fail(self.Error.PLAYLIST_CONFIG_ERROR, tostring(created.err))
        end

        local added = selector:addPlayList(created.value)
        if not added.ok then
            return fail(self.Error.PLAYLIST_SELECTOR_ERROR, tostring(added.err))
        end

        table.insert(self.playlists, created.value)
        self.total_music_count = self.total_music_count + #created.value.musics
    end

    if #self.playlists == 0 or self.total_music_count == 0 then
        return fail(self.Error.EMPTY_PLAYLIST)
    end

    local selector_ready = selector:setup()
    if not selector_ready.ok then
        return fail(self.Error.PLAYLIST_SELECTOR_ERROR, tostring(selector_ready.err))
    end

    player:setup(config)

    setState(self.State.READY)
    return result.ok(nil)
end

---@return AmbientResult<nil, AmbientScheduleError>
function M:start()
    if self.config == nil or #self.playlists == 0 then
        return fail(self.Error.CONFIG_NOT_READY)
    end

    if self.state == self.State.PLAYING or self.state == self.State.INTERVAL or self.state == self.State.NEXT then
        return result.ok(nil)
    end

    if self.state == self.State.PAUSED then
        local player_error = player:resume()
        if player_error ~= nil then
            return fail(self.Error.PLAYER_ERROR, player_error)
        end
        setState(self.State.PLAYING)
        return startEventTimer()
    end

    return playNow()
end

---@return AmbientResult<nil, AmbientScheduleError>
function M:stop()
    closeAllTimers()
    player:shutdown()
    self.current_music    = nil
    self.next_due_time_ms = nil
    setState(self.State.STOPPED)
    return result.ok(nil)
end

---@return AmbientResult<nil, AmbientScheduleError>
function M:pause()
    if self.state ~= self.State.PLAYING then
        return result.ok(nil)
    end

    local player_error = player:pause()
    if player_error ~= nil then
        return fail(self.Error.PLAYER_ERROR, player_error)
    end

    setState(self.State.PAUSED)
    return result.ok(nil)
end

---@return AmbientResult<nil, AmbientScheduleError>
function M:restart()
    self:stop()
    return self:start()
end

---@return AmbientResult<nil, AmbientScheduleError>
function M:next()
    if self.config == nil or #self.playlists == 0 then
        return fail(self.Error.CONFIG_NOT_READY)
    end

    return playNow()
end

---@return AmbientResult<nil, AmbientScheduleError>
function M:previous()
    if self.config == nil or #self.playlists == 0 then
        return fail(self.Error.CONFIG_NOT_READY)
    end

    return playAdjacent("previous")
end

---@param index integer
---@return AmbientResult<nil, AmbientPlayListSelectorError>
function M:selectPlaylist(index)
    local selected = selector:setCurrentPlaylist(index)
    if not selected.ok then
        return selected
    end

    resetToReadyAfterPlaylistSelection()
    return result.ok(nil)
end

---@param on_select? AmbientPlayListSelectedCallback
---@return AmbientResult<nil, AmbientPlayListSelectorError>
function M:displayPlaylistSelectorUi(on_select)
    return selector:displayPlayListSelectUi(function(selected)
        if selected.ok then
            resetToReadyAfterPlaylistSelection()
        end

        if on_select ~= nil then
            on_select(selected)
        end
    end)
end

---@alias AmbientScheduledMusicSelectedCallback fun(result: AmbientResult<AmbientMusic, AmbientPlayListSelectorError|AmbientScheduleError>): nil

---@param on_select? AmbientScheduledMusicSelectedCallback
---@return AmbientResult<nil, AmbientPlayListSelectorError>
function M:displayMusicSelectorUi(on_select)
    return selector:displayMusicItemSelectUi(function(selected)
        if not selected.ok then
            if on_select ~= nil then
                on_select(result.err(selected.err))
            end
            return
        end

        local played = playAdjacent("next", true)
        if not played.ok then
            if on_select ~= nil then
                on_select(result.err(played.err))
            end
            return
        end

        if on_select ~= nil then
            on_select(result.ok(selected.value))
        end
    end)
end

---@return AmbientResult<nil, AmbientScheduleError>
function M:toggleStartStop()
    if self.state == self.State.PLAYING
        or self.state == self.State.PAUSED
        or self.state == self.State.INTERVAL
        or self.state == self.State.NEXT
    then
        return self:stop()
    end

    return self:start()
end

---@return AmbientResult<nil, AmbientScheduleError>
function M:togglePauseResumeOrStartNow()
    if self.state == self.State.PLAYING then
        return self:pause()
    end

    if self.state == self.State.INTERVAL then
        return playNow()
    end

    return self:start()
end

---@return AmbientScheduleStatus
function M:getStatus()
    local next_due_in_ms = nil
    if self.next_due_time_ms ~= nil then
        next_due_in_ms = math.max(0, self.next_due_time_ms - uv.now())
    end

    local current_time_ms              = nil
    local duration_ms                  = nil
    local progress_percentage          = nil
    local current_playlist_name        = nil
    local current_playlist_path        = nil
    local current_playlist_music_count = nil

    local current_playlist = selector:getCurrentPlayListValue()
    if current_playlist ~= nil then
        current_playlist_name        = current_playlist.name
        current_playlist_path        = current_playlist.abs_path
        current_playlist_music_count = #current_playlist.musics
    end

    if self.state == self.State.PLAYING then
        local playback_progress = player:getProgress()
        if playback_progress ~= nil then
            current_time_ms     = playback_progress.time_ms
            duration_ms         = playback_progress.duration_ms
            progress_percentage = playback_progress.percentage
        end
    end

    return {
        state                        = self.state,
        mode                         = self.config and self.config.mode or nil,
        playlist_count               = #self.playlists,
        total_music_count            = self.total_music_count,
        current_playlist_name        = current_playlist_name,
        current_playlist_path        = current_playlist_path,
        current_playlist_music_count = current_playlist_music_count,
        current_music_name           = self.current_music and self.current_music.name or nil,
        current_music_path           = self.current_music and self.current_music.abs_path or nil,
        current_time_ms              = current_time_ms,
        duration_ms                  = duration_ms,
        progress_percentage          = progress_percentage,
        next_due_in_ms               = next_due_in_ms,
        last_error                   = self.last_error,
    }
end

---@return AmbientResult<AmbientScheduleStatus, AmbientScheduleError>
function M:get()
    return result.ok(self:getStatus())
end

---@return boolean
function M:is_ready()
    return self.config ~= nil and #self.playlists > 0 and self.state ~= self.State.ERROR
end

---@return string?
function M:get_error_message()
    return self.last_error
end

return M
