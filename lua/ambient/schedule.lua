local M = {}

local result   = require("ambient.result")
local playlist = require("ambient.playlist")
local selector = require("ambient.playlist_selector")
local player   = require("ambient.player")

local uv = vim.uv or vim.loop

---@class AmbientPlayerListConfig
---@field abs_path string
---@field ext string[]
---@field recursive_depth integer
---@field sort_field SortField
---@field sort_direction SortDirection

---@alias AmbientPlayerScheduleMode "interval_random" | "interval_sequential" | "without_interval_random" | "without_interval_sequential" | "intermittently" | "continuous" | "continously"

---@class AmbientSchedulerConfig
---@field playlists AmbientPlayerListConfig[]
---@field mode AmbientPlayerScheduleMode
---@field interval AmbientIntervalConfig
---@field volume integer
---@field volumn_percentage integer

---@enum AmbientScheduleError
M.Error = {
    CONFIG_NOT_READY        = "CONFIG_NOT_READY",
    PLAYLIST_CONFIG_ERROR   = "PLAYLIST_CONFIG_ERROR",
    PLAYLIST_SELECTOR_ERROR = "PLAYLIST_SELECTOR_ERROR",
    EMPTY_PLAYLIST          = "EMPTY_PLAYLIST",
    PLAYER_ERROR            = "PLAYER_ERROR",
    TIMER_CREATE_FAILED     = "TIMER_CREATE_FAILED",
}

---@enum ScheduleState
M.State = {
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

M.state                   = M.State.INIT
M.config                  = nil
M.playlists               = {}
M.current_music           = nil
M.total_music_count       = 0
M.interval_timer          = nil
M.event_timer             = nil
M.next_due_time_ms        = nil
M.last_error              = nil
M.random_seed_initialized = false

local playNow
local scheduleNext

local function emitStateChanged()
    vim.schedule(function()
        pcall(vim.api.nvim_exec_autocmds, "User", {
            pattern  = "AmbientStateChanged",
            modeline = false,
        })
    end)
end

---@param state ScheduleState
local function setState(state)
    M.state = state
    emitStateChanged()
end

local function seedRandom()
    if M.random_seed_initialized then
        return
    end

    math.randomseed(os.time() + (uv.hrtime() % 1000000))
    math.random()
    M.random_seed_initialized = true
end

---@param timer_name "interval_timer" | "event_timer"
local function closeTimer(timer_name)
    local timer = M[timer_name]
    if timer ~= nil then
        pcall(function()
            timer:stop()
            if not timer:is_closing() then
                timer:close()
            end
        end)
    end
    M[timer_name] = nil
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

---@param mode AmbientPlayerScheduleMode
---@return boolean
local function isContinuousMode(mode)
    return mode == "without_interval_random"
        or mode == "without_interval_sequential"
        or mode == "continuous"
        or mode == "continously"
end

---@return integer
local function nextIntervalMs()
    local interval = M.config.interval
    if interval.min_ms == interval.max_ms then
        return interval.min_ms
    end

    return math.random(interval.min_ms, interval.max_ms)
end

---@param item AmbientPlayList
---@return AmbientMusic?
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
    elseif item.sort_field == "random" then
        item:sort()
    else
        item:reset()
    end

    return current
end

---@return AmbientMusic?
local function takeNextMusic()
    local selected = selector:getCurrentPlayList()
    if not selected.ok then
        return nil
    end

    return takeMusicFromPlaylist(selected.value)
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

                    if isContinuousMode(M.config.mode) then
                        scheduleNext(0)
                    else
                        scheduleNext(nextIntervalMs())
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

---@return AmbientResult<nil, AmbientScheduleError>
playNow = function()
    closeTimer("interval_timer")
    closeTimer("event_timer")
    player:drainEvents()

    local music = takeNextMusic()
    if music == nil then
        return fail(M.Error.EMPTY_PLAYLIST)
    end

    local played = player:play(music)
    if not played.ok then
        return fail(M.Error.PLAYER_ERROR, player:get_error_message())
    end

    M.current_music    = music
    M.next_due_time_ms = nil
    M.last_error       = nil
    setState(M.State.PLAYING)

    return startEventTimer()
end

---@param config AmbientSchedulerConfig
---@return AmbientResult<nil, AmbientScheduleError>
function M:setup(config)
    seedRandom()
    closeAllTimers()
    player:shutdown()

    self.config            = config
    self.playlists         = {}
    self.current_music     = nil
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

    local player_ready = player:setup(config)
    if not player_ready.ok then
        return fail(self.Error.PLAYER_ERROR, player:get_error_message())
    end

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
        local resumed = player:resume()
        if not resumed.ok then
            return fail(self.Error.PLAYER_ERROR, player:get_error_message())
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

    local paused = player:pause()
    if not paused.ok then
        return fail(self.Error.PLAYER_ERROR, player:get_error_message())
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
    return selector:displaySelectorUi(function(selected)
        if selected.ok then
            resetToReadyAfterPlaylistSelection()
        end

        if on_select ~= nil then
            on_select(selected)
        end
    end)
end

---@return AmbientResult<nil, AmbientScheduleError>
function M:toggle()
    if self.state == self.State.PLAYING or self.state == self.State.INTERVAL or self.state == self.State.NEXT then
        return self:stop()
    end

    return self:start()
end

---@return AmbientResult<AmbientScheduleStatus, AmbientScheduleError>
function M:get()
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

    local current_playlist = selector:getCurrentPlayList()
    if current_playlist.ok then
        current_playlist_name        = current_playlist.value.name
        current_playlist_path        = current_playlist.value.abs_path
        current_playlist_music_count = #current_playlist.value.musics
    end

    if self.state == self.State.PLAYING then
        local progress = player:getProgress()
        if progress.ok then
            current_time_ms     = progress.value.time_ms
            duration_ms         = progress.value.duration_ms
            progress_percentage = progress.value.percentage
        end
    end

    return result.ok({
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
    })
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
