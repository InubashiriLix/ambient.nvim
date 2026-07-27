--- single instance mode
--- Actually this is an tomato clock

local result   = require("ambient.common.result")
local timer    = require("ambient.common.timer")
local player   = require("ambient.player")
local playlist = require("ambient.models.playlist")

local script_path = debug.getinfo(1, "S").source:sub(2)
---@param focus boolean
local function bonus_music_path(focus)
    local plugin_root = vim.fn.fnamemodify(script_path, ":p:h:h:h:h")
    return plugin_root ..
        "/default_assets/default_focus/" .. (focus and "focus" or "stirb")
end


---@enum AmbientFocusStates
local State = {
    IDLE  = "IDLE",
    FOCUS = "FOCUS",
    RELAX = "RELAX",
}

---@enum AmbientFocusInitError
local InitError = {
    TIMER_CREATE_FAILED = "TIMER_CREATE_FAILED",
    ALREADY_INITIALIZED = "ALREADY_INITIALIZED",
    INVALID_ARGUMENTS   = "INVALID_ARGUMENTS",
}

---@enum AmbientFocusStartError
local StartError = {
    NOT_INITIALIZED = "NOT_INITIALIZED",
    ALREADY_RUNNING = "ALREADY_RUNNING",
    EMPTY_PLAYLIST  = "EMPTY_PLAYLIST",
}

---@class AmbientFocus
---@field focus_duration_ms integer
---@field relax_duration_ms integer
---@field focus_playlist_path string?
---@field relax_playlist_path string?
---@field focus_playlist AmbientPlayList
---@field relax_playlist AmbientPlayList
---@field initialized boolean
---@field state AmbientFocusStates
---@field focus_timer Timer|nil
---@field relax_timer Timer|nil
local M = {
    initialized       = false,
    state             = State.IDLE,
    focus_timer       = nil,
    relax_timer       = nil,
    focus_duration_ms = 0,
    relax_duration_ms = 0,
}


M.State      = State
M.InitError  = InitError
M.StartError = StartError

local track_poll_generation = 0

local function emitTrackChanged()
    if vim.api == nil or type(vim.api.nvim_exec_autocmds) ~= "function" then
        return
    end

    pcall(vim.api.nvim_exec_autocmds, "User", {
        pattern  = "AmbientTrackChanged",
        modeline = false,
    })
end

local function pollTrackInfo()
    if type(player.drainEvents) ~= "function" or type(vim.defer_fn) ~= "function" then
        return
    end

    track_poll_generation    = track_poll_generation + 1
    local generation         = track_poll_generation
    local remaining_attempts = 20

    local function poll()
        if generation ~= track_poll_generation then
            return
        end

        player:drainEvents()
        remaining_attempts = remaining_attempts - 1
        if remaining_attempts > 0 and player.state.current ~= nil then
            vim.defer_fn(poll, 100)
        end
    end

    vim.defer_fn(poll, 0)
end

local function trackStarted()
    emitTrackChanged()
    pollTrackInfo()
end

function M.focus_callback()
    -- when the focus is ended, then transform the state
    M.state = State.RELAX
    vim.notify("Focus Session Complete")
    vim.notify("Both of us die today. One, just a little later than the other.")

    -- randomly select a song from the relax playlist
    local next_music = nil
    if not M.relax_playlist:hasNext() then
        M.relax_playlist:reset()
        next_music = M.relax_playlist:getCurrent()
    else
        next_music = M.relax_playlist:next()
    end
    -- fucking impossible true nil check, waste my time
    if next_music == nil then return end
    -- start playing
    local play_err = player:play(next_music)
    if play_err ~= nil then
        M.state = State.IDLE
        vim.notify("Failed to start relax music: " .. tostring(play_err), vim.log.levels.ERROR)
        return
    end
    trackStarted()

    local timer_result = M.relax_timer:start()
    if not timer_result.ok then
        M.state = State.IDLE
        player:stop()
        vim.notify("Failed to start relax timer: " .. tostring(timer_result.err),
            vim.log.levels.ERROR)
    end
end

function M.relax_callback()
    -- finish this epoch by returning to focus music without starting another timer
    M.state = State.IDLE
    vim.notify("Get up")
    vim.notify("Never learning. Never comprehending. Never consistent. If only you could see.")
    vim.notify("Continue or not, it's up to you, coward!")

    local next_music = nil
    if not M.focus_playlist:hasNext() then
        M.focus_playlist:reset()
        next_music = M.focus_playlist:getCurrent()
    else
        next_music = M.focus_playlist:next()
    end

    if next_music == nil then return end
    local play_err = player:play(next_music)
    if play_err ~= nil then
        vim.notify("Failed to start focus music: " .. tostring(play_err), vim.log.levels.ERROR)
        return
    end
    trackStarted()
end

---@param self AmbientFocus
---@param time_ms_focus integer? the time to focus
---@param time_ms_relax integer? the time to relax
---@param focus_playlist_path string?
---@param relax_playlist_path string?
---@return AmbientResult<nil, AmbientFocusInitError>
function M:init(time_ms_focus, time_ms_relax, focus_playlist_path, relax_playlist_path)
    if self.initialized then
        return result.err(M.InitError.ALREADY_INITIALIZED)
    end

    -- verify input time is valid
    time_ms_relax = time_ms_relax or (5 * 60 * 1000)
    time_ms_focus = time_ms_focus or (25 * 60 * 1000)
    if type(time_ms_focus) ~= "number"
        or type(time_ms_relax) ~= "number"
        or time_ms_focus <= 0
        or time_ms_relax <= 0
    then
        return result.err(M.InitError.INVALID_ARGUMENTS)
    end

    -- verify the input playlist path
    local default_focus_playlist_path = bonus_music_path(true)
    local default_relax_playlist_paht = bonus_music_path(false)
    if not focus_playlist_path then
        focus_playlist_path = default_focus_playlist_path
    end
    if not relax_playlist_path then
        relax_playlist_path = default_relax_playlist_paht
    end
    -- playlist constrcutor will check playlist path and return error code probably
    local f_playlist_result = playlist:new(focus_playlist_path, nil, 1, playlist.SortField.random,
        playlist.SortDirection.asc)
    if not f_playlist_result.ok then
        return result.err(f_playlist_result.err)
    end
    local r_playlist_result = playlist:new(relax_playlist_path, nil, 1, playlist.SortField.random,
        playlist.SortDirection.asc)
    if not r_playlist_result.ok then
        return result.err(r_playlist_result.err)
    end
    self.focus_playlist = f_playlist_result.value
    self.relax_playlist = r_playlist_result.value

    self.focus_duration_ms = time_ms_focus
    self.relax_duration_ms = time_ms_relax
    self.state             = M.State.IDLE
    local f_timer_result   = timer.new(self.focus_duration_ms, M.focus_callback)
    if not f_timer_result.ok then return result.err(f_timer_result.err) end
    local r_timer_result = timer.new(self.relax_duration_ms, M.relax_callback)
    if not r_timer_result.ok then return result.err(r_timer_result.err) end

    self.focus_timer = f_timer_result.value
    self.relax_timer = r_timer_result.value
    self.initialized = true

    return result.ok(nil)
end

---@param self AmbientFocus
---@return AmbientResult<nil, AmbientFocusStartError|string>
function M:startOneFocusEpoch()
    if not self.initialized or self.focus_timer == nil then
        return result.err(M.StartError.NOT_INITIALIZED)
    end

    if self.state ~= M.State.IDLE then
        return result.err(M.StartError.ALREADY_RUNNING)
    end

    -- check whether the player state is ready
    if player.state.state == player.STATE.NOT_READY then
        player:setup({})
    end

    local next_music = self.focus_playlist:getCurrent()
    if next_music == nil then
        return result.err(M.StartError.EMPTY_PLAYLIST)
    end

    local play_err = player:play(next_music)
    if play_err ~= nil then
        return result.err(play_err)
    end
    trackStarted()

    self.state         = M.State.FOCUS
    local timer_result = self.focus_timer:start()
    if not timer_result.ok then
        self.state = M.State.IDLE
        player:stop()
        return result.err(timer_result.err)
    end

    return result.ok(nil)
end

return M
