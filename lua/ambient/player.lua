local M = {}

local mpv    = require("ambient.mpv_ipc")
local result = require("ambient.result")
local uv     = vim.uv or vim.loop

---@enum AmbientPlayerError
M.Error = {
    NOT_READY          = "NOT_READY",
    MPV_NOT_FOUND      = "MPV_NOT_FOUND",
    MPV_START_FAILED   = "MPV_START_FAILED",
    MPV_COMMAND_FAILED = "MPV_COMMAND_FAILED",
    NO_CURRENT         = "NO_CURRENT",
    PAUSE_FAILED       = "PAUSE_FAILED",
    RESUME_FAILED      = "RESUME_FAILED",
}

---@enum AmbientPlayerState
M.STATE = {
    NOT_READY = "NOT_READY",
    READY     = "READY",
    PLAYING   = "PLAYING",
    STOPPED   = "STOPPED",
    PAUSED    = "PAUSED",
    ERROR     = "ERROR",
}

---@class AmbientPlayerStateInfo
---@field state AmbientPlayerState
---@field current? AmbientMusic
---@field volume integer
---@field job_id? integer
---@field started_at_ms? integer
---@field paused_at_ms? integer
---@field paused_total_ms integer
---@field last_error? string

---@class AmbientPlaybackProgress
---@field time_ms integer
---@field duration_ms integer
---@field percentage integer

---@alias AmbientPlayerConfig { volume?: integer, volumn_percentage?: integer }

---@type AmbientPlayerStateInfo
M.state = {
    state           = M.STATE.NOT_READY,
    current         = nil,
    volume          = 50,
    job_id          = nil,
    started_at_ms   = nil,
    paused_at_ms    = nil,
    paused_total_ms = 0,
    last_error      = nil,
}

M.events              = {}
M.load_generation     = 0
M.pending_cover_paths = {}

---@param err AmbientPlayerError
---@return AmbientPlayerError
local function fail(err)
    M.state.state      = M.STATE.ERROR
    M.state.last_error = err
    return err
end

---@param path string
local function deleteFile(path)
    if path == "" then
        return
    end

    if vim.fn ~= nil and vim.fn.delete ~= nil then
        pcall(vim.fn.delete, path)
    elseif uv.fs_unlink ~= nil then
        pcall(uv.fs_unlink, path)
    end
end

local function cleanupPendingCoverPaths()
    for path in pairs(M.pending_cover_paths) do
        deleteFile(path)
    end
    M.pending_cover_paths = {}
end

local function releaseCurrentCover()
    if M.state.current ~= nil and M.state.current.releaseCoverPic ~= nil then
        M.state.current:releaseCoverPic()
    end
end

local function emitTrackInfoUpdated()
    if vim.api == nil or type(vim.api.nvim_exec_autocmds) ~= "function" then
        return
    end

    pcall(vim.api.nvim_exec_autocmds, "User", {
        pattern  = "AmbientTrackInfoUpdated",
        modeline = false,
    })
end

---@param metadata table
---@param wanted string[]
---@return string|string[]|nil
local function getMetadataValue(metadata, wanted)
    local wanted_set = {}
    for _, key in ipairs(wanted) do
        wanted_set[key:lower()] = true
    end

    for key, value in pairs(metadata) do
        if type(key) == "string"
            and wanted_set[key:lower()]
            and (type(value) == "string" or type(value) == "table")
        then
            return value
        end
    end

    return nil
end

---@param generation integer
---@param music AmbientMusic
---@return boolean
local function isCurrentLoad(generation, music)
    return M.load_generation == generation and M.state.current == music
end

---@param generation integer
---@param music AmbientMusic
---@param track table
local function requestCover(generation, music, track)
    local cover_path                  = vim.fn.tempname() .. ".png"
    M.pending_cover_paths[cover_path] = true

    local requested = mpv.requestAsync({
        "screenshot-to-file",
        cover_path,
        "video",
    }, function(reply)
        M.pending_cover_paths[cover_path] = nil

        if not reply.ok or not isCurrentLoad(generation, music) then
            deleteFile(cover_path)
            return
        end

        music:releaseCoverPic()
        music.cover_pic = {
            path      = cover_path,
            mime      = "image/png",
            width     = track["demux-w"] or track["w"],
            height    = track["demux-h"] or track["h"],
            source    = track.external and "external" or "embedded",
            temporary = true,
        }
        emitTrackInfoUpdated()
    end)

    if not requested.ok then
        M.pending_cover_paths[cover_path] = nil
        deleteFile(cover_path)
    end
end

---@param generation integer
---@param music AmbientMusic
local function requestTrackList(generation, music)
    mpv.requestAsync({ "get_property", "track-list" }, function(reply)
        if not reply.ok or not isCurrentLoad(generation, music) then
            return
        end

        local selected_cover
        local fallback_cover
        for _, track in ipairs(reply.value.data or {}) do
            if track.type == "video" and track.albumart == true then
                fallback_cover = fallback_cover or track
                if track.selected == true then
                    selected_cover = track
                    break
                end
            end
        end

        local cover_track = selected_cover or fallback_cover
        if selected_cover ~= nil then
            requestCover(generation, music, selected_cover)
        elseif cover_track ~= nil then
            mpv.requestAsync({
                "set_property",
                "vid",
                cover_track.id,
            }, function(selected)
                if selected.ok and isCurrentLoad(generation, music) then
                    requestCover(generation, music, cover_track)
                end
            end)
        end
    end)
end

---@param generation integer
---@param music AmbientMusic
local function requestMetadata(generation, music)
    mpv.requestAsync({ "get_property", "metadata" }, function(reply)
        if not reply.ok or not isCurrentLoad(generation, music) then
            return
        end

        local metadata    = reply.value.data or {}
        music.artist_name = getMetadataValue(metadata, {
            "artist",
            "album_artist",
            "albumartist",
        })
        music.album_name  = getMetadataValue(metadata, { "album" })
        emitTrackInfoUpdated()
    end)
end

local function requestCurrentMusicInfo()
    local generation = M.load_generation
    local music      = M.state.current
    if music == nil then
        return
    end

    mpv.requestAsync({ "get_property", "path" }, function(reply)
        if not reply.ok
            or not isCurrentLoad(generation, music)
            or reply.value.data ~= music.abs_path
        then
            return
        end

        requestMetadata(generation, music)
        requestTrackList(generation, music)
    end)
end

---@return AmbientPlayerError?
local function ensureMpvStarted()
    if mpv.isStarted() then
        return nil
    end

    local started = mpv.start()
    if not started.ok then
        if started.err == mpv.Error.mpv_not_found then
            return M.Error.MPV_NOT_FOUND
        end
        return M.Error.MPV_START_FAILED
    end

    M.state.job_id   = mpv.client.job_id
    local volume_set = mpv.request({
        "set_property",
        "volume",
        M.state.volume,
    })
    if not volume_set.ok then
        mpv.stop()
        M.state.job_id = nil
        return M.Error.MPV_COMMAND_FAILED
    end

    return nil
end

---@param config AmbientPlayerConfig
function M:setup(config)
    self:shutdown()
    self.state.volume          = config.volume or config.volumn_percentage or self.state.volume
    self.state.current         = nil
    self.state.job_id          = nil
    self.state.started_at_ms   = nil
    self.state.paused_at_ms    = nil
    self.state.paused_total_ms = 0
    self.state.last_error      = nil
    self.state.state           = self.STATE.READY
    self.events                = {}
end

---@param music AmbientMusic
---@return AmbientPlayerError?
function M:play(music)
    if self.state.state == self.STATE.NOT_READY then
        return self.Error.NOT_READY
    end

    local start_error = ensureMpvStarted()
    if start_error ~= nil then
        return fail(start_error)
    end

    self.load_generation = self.load_generation + 1
    releaseCurrentCover()
    cleanupPendingCoverPaths()

    local loaded = mpv.request({
        "loadfile",
        music.abs_path,
        "replace",
    })
    if not loaded.ok then
        self.state.current = nil
        return fail(self.Error.MPV_COMMAND_FAILED)
    end

    music:loadDurationAsync()

    self.state.current         = music
    self.state.job_id          = mpv.client.job_id
    self.state.started_at_ms   = uv.now()
    self.state.paused_at_ms    = nil
    self.state.paused_total_ms = 0
    self.state.last_error      = nil
    self.state.state           = self.STATE.PLAYING

    return nil
end

---@return AmbientPlayerError?
function M:pause()
    if self.state.state ~= self.STATE.PLAYING then
        return self.Error.NOT_READY
    end

    local paused = mpv.request({ "set_property", "pause", true })
    if not paused.ok then
        return fail(self.Error.PAUSE_FAILED)
    end

    self.state.paused_at_ms = uv.now()
    self.state.state        = self.STATE.PAUSED
    return nil
end

---@return AmbientPlayerError?
function M:resume()
    if self.state.state ~= self.STATE.PAUSED then
        return self.Error.NOT_READY
    end

    local resumed = mpv.request({ "set_property", "pause", false })
    if not resumed.ok then
        return fail(self.Error.RESUME_FAILED)
    end

    if self.state.paused_at_ms ~= nil then
        self.state.paused_total_ms = self.state.paused_total_ms
            + (uv.now() - self.state.paused_at_ms)
    end

    self.state.paused_at_ms = nil
    self.state.state        = self.STATE.PLAYING
    return nil
end

function M:stop()
    self.load_generation = self.load_generation + 1
    releaseCurrentCover()
    cleanupPendingCoverPaths()

    if mpv.isStarted() then
        mpv.request({ "stop" })
    end

    self.state.current         = nil
    self.state.started_at_ms   = nil
    self.state.paused_at_ms    = nil
    self.state.paused_total_ms = 0
    self.state.state           = self.STATE.STOPPED
end

function M:shutdown()
    self:stop()
    if mpv.isStarted() then
        mpv.stop()
    end
    cleanupPendingCoverPaths()
    self.state.job_id = nil
end

---@param volume integer
function M:setVolume(volume)
    self.state.volume = volume
    if mpv.isStarted() then
        mpv.request({ "set_property", "volume", volume })
    end
end

---@return AmbientPlaybackProgress?
function M:getProgress()
    if self.state.current == nil or self.state.started_at_ms == nil then
        return nil
    end

    local elapsed_ms
    if self.state.state == self.STATE.PAUSED and self.state.paused_at_ms ~= nil then
        elapsed_ms = self.state.paused_at_ms - self.state.started_at_ms - self.state.paused_total_ms
    else
        elapsed_ms = uv.now() - self.state.started_at_ms - self.state.paused_total_ms
    end

    elapsed_ms = math.max(0, elapsed_ms)

    local duration_ms = self.state.current.duration_ms or 0
    local percentage  = 0
    if duration_ms > 0 then
        elapsed_ms = math.min(elapsed_ms, duration_ms)
        percentage = math.max(0, math.min(100, math.floor((elapsed_ms / duration_ms) * 100)))
    end

    self.state.current:setCursorTime(elapsed_ms)

    return {
        time_ms     = elapsed_ms,
        duration_ms = duration_ms,
        percentage  = percentage,
    }
end

---@return table[]
function M:drainEvents()
    for _, event in ipairs(mpv.drainEvent()) do
        if event.event == "file-loaded" then
            requestCurrentMusicInfo()
        elseif event.event == "end-file" then
            if event.reason ~= "stop" and event.reason ~= "replaced" then
                self.load_generation = self.load_generation + 1
                releaseCurrentCover()
                cleanupPendingCoverPaths()
                self.state.current         = nil
                self.state.started_at_ms   = nil
                self.state.paused_at_ms    = nil
                self.state.paused_total_ms = 0
                if self.state.state ~= self.STATE.ERROR then
                    self.state.state = self.STATE.STOPPED
                end
            end
            table.insert(self.events, event)
        elseif event.event == "shutdown" then
            self.load_generation = self.load_generation + 1
            releaseCurrentCover()
            cleanupPendingCoverPaths()
            self.state.current = nil
            self.state.job_id  = nil
            self.state.state   = self.STATE.STOPPED
            table.insert(self.events, event)
        end
    end

    local events = self.events
    self.events  = {}
    return events
end

---@return AmbientPlayerStateInfo
function M:get()
    return vim.deepcopy(self.state)
end

---@return string?
function M:get_error_message()
    return self.state.last_error
end

return M
