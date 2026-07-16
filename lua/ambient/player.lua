local M = {}

local result = require("ambient.result")

local uv = vim.uv or vim.loop

---@enum AmbientPlayerError
M.Error = {
    NOT_READY        = "NOT_READY",
    MPV_NOT_FOUND    = "MPV_NOT_FOUND",
    MPV_START_FAILED = "MPV_START_FAILED",
    NO_CURRENT       = "NO_CURRENT",
    PAUSE_FAILED     = "PAUSE_FAILED",
    RESUME_FAILED    = "RESUME_FAILED",
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
---@field pid? integer
---@field started_at_ms? integer
---@field paused_at_ms? integer
---@field paused_total_ms integer
---@field stopping boolean
---@field last_error? string

---@class AmbientPlaybackProgress
---@field time_ms integer
---@field duration_ms integer
---@field percentage integer

---@type AmbientPlayerStateInfo
M.state = {
    state           = M.STATE.NOT_READY,
    current         = nil,
    volume          = 50,
    job_id          = nil,
    pid             = nil,
    started_at_ms   = nil,
    paused_at_ms    = nil,
    paused_total_ms = 0,
    stopping        = false,
    last_error      = nil,
}

M.events = {}
M.stopping_jobs = {}

---@param err AmbientPlayerError
---@return AmbientErr<AmbientPlayerError>
local function fail(err)
    M.state.state      = M.STATE.ERROR
    M.state.last_error = err
    return result.err(err)
end

---@return integer
local function nowMs()
    return uv.now()
end

---@param job_id integer?
---@return integer?
local function getJobPid(job_id)
    if job_id == nil or vim.fn.exists("*jobpid") == 0 then
        return nil
    end

    local ok, pid = pcall(vim.fn.jobpid, job_id)
    if not ok or pid == 0 then
        return nil
    end

    return pid
end

---@param signal string
---@return boolean
local function signalCurrentJob(signal)
    if M.state.pid == nil then
        return false
    end

    local signal_map = {
        sigstop = uv.constants and uv.constants.SIGSTOP or 19,
        sigcont = uv.constants and uv.constants.SIGCONT or 18,
    }

    local ok = pcall(uv.kill, M.state.pid, signal_map[signal])
    return ok
end

---@param config AmbientConfig
---@return AmbientResult<nil, AmbientPlayerError>
function M:setup(config)
    self.state.volume          = config.volume or config.volumn_percentage or self.state.volume
    self.state.current         = nil
    self.state.job_id          = nil
    self.state.pid             = nil
    self.state.started_at_ms   = nil
    self.state.paused_at_ms    = nil
    self.state.paused_total_ms = 0
    self.state.stopping        = false
    self.state.last_error      = nil
    self.state.state           = self.STATE.READY
    self.events                = {}
    self.stopping_jobs         = {}
    return result.ok(nil)
end

---@param music AmbientMusic
---@return AmbientResult<nil, AmbientPlayerError>
function M:play(music)
    if self.state.state == self.STATE.NOT_READY then
        return result.err(self.Error.NOT_READY)
    end

    if vim.fn.executable("mpv") == 0 then
        return fail(self.Error.MPV_NOT_FOUND)
    end

    if self.state.job_id ~= nil then
        self:stop()
    end

    self.state.stopping = false

    local args = {
        "mpv",
        "--no-video",
        "--force-window=no",
        "--input-terminal=no",
        "--terminal=no",
        "--volume=" .. tostring(self.state.volume),
        music.abs_path,
    }

    local job_id
    job_id = vim.fn.jobstart(args, {
        detach = false,
        on_exit = function(_, code)
            local reason = "eof"
            if M.stopping_jobs[job_id] then
                reason = "stop"
            elseif code ~= 0 then
                reason = "error"
            end

            M.stopping_jobs[job_id] = nil

            if M.state.job_id == job_id then
                M.state.job_id          = nil
                M.state.pid             = nil
                M.state.started_at_ms   = nil
                M.state.paused_at_ms    = nil
                M.state.paused_total_ms = 0
                M.state.stopping        = false
                M.state.current         = nil
                if M.state.state ~= M.STATE.ERROR then
                    M.state.state = M.STATE.STOPPED
                end
            end

            table.insert(M.events, {
                event  = "end-file",
                reason = reason,
            })
        end,
    })

    if job_id <= 0 then
        return fail(self.Error.MPV_START_FAILED)
    end

    self.state.current         = music
    self.state.job_id          = job_id
    self.state.pid             = getJobPid(job_id)
    self.state.started_at_ms   = nowMs()
    self.state.paused_at_ms    = nil
    self.state.paused_total_ms = 0
    self.state.last_error      = nil
    self.state.state           = self.STATE.PLAYING

    return result.ok(nil)
end

---@return AmbientResult<nil, AmbientPlayerError>
function M:pause()
    if self.state.state ~= self.STATE.PLAYING then
        return result.err(self.Error.NOT_READY)
    end

    if not signalCurrentJob("sigstop") then
        return fail(self.Error.PAUSE_FAILED)
    end

    self.state.paused_at_ms = nowMs()
    self.state.state        = self.STATE.PAUSED
    return result.ok(nil)
end

---@return AmbientResult<nil, AmbientPlayerError>
function M:resume()
    if self.state.state ~= self.STATE.PAUSED then
        return result.err(self.Error.NOT_READY)
    end

    if not signalCurrentJob("sigcont") then
        return fail(self.Error.RESUME_FAILED)
    end

    if self.state.paused_at_ms ~= nil then
        self.state.paused_total_ms = self.state.paused_total_ms + (nowMs() - self.state.paused_at_ms)
    end

    self.state.paused_at_ms = nil
    self.state.state        = self.STATE.PLAYING
    return result.ok(nil)
end

---@return AmbientResult<nil, AmbientPlayerError>
function M:stop()
    if self.state.job_id ~= nil then
        self.state.stopping = true
        self.stopping_jobs[self.state.job_id] = true
        pcall(vim.fn.jobstop, self.state.job_id)
    end

    self.state.current         = nil
    self.state.job_id          = nil
    self.state.pid             = nil
    self.state.started_at_ms   = nil
    self.state.paused_at_ms    = nil
    self.state.paused_total_ms = 0
    self.state.state           = self.STATE.STOPPED
    return result.ok(nil)
end

---@return AmbientResult<nil, AmbientPlayerError>
function M:shutdown()
    return self:stop()
end

---@param volume integer
---@return AmbientResult<nil, AmbientPlayerError>
function M:setVolume(volume)
    self.state.volume = volume
    return result.ok(nil)
end

---@return AmbientResult<AmbientPlaybackProgress, AmbientPlayerError>
function M:getProgress()
    if self.state.current == nil or self.state.started_at_ms == nil then
        return result.err(self.Error.NO_CURRENT)
    end

    local elapsed_ms
    if self.state.state == self.STATE.PAUSED and self.state.paused_at_ms ~= nil then
        elapsed_ms = self.state.paused_at_ms - self.state.started_at_ms - self.state.paused_total_ms
    else
        elapsed_ms = nowMs() - self.state.started_at_ms - self.state.paused_total_ms
    end

    elapsed_ms = math.max(0, elapsed_ms)

    local duration_ms = self.state.current.duration_ms or 0
    local percentage = 0
    if duration_ms > 0 then
        elapsed_ms = math.min(elapsed_ms, duration_ms)
        percentage = math.max(0, math.min(100, math.floor((elapsed_ms / duration_ms) * 100)))
    end

    self.state.current:setCursorTime(elapsed_ms)

    return result.ok({
        time_ms     = elapsed_ms,
        duration_ms = duration_ms,
        percentage  = percentage,
    })
end

---@return table[]
function M:drainEvents()
    local events = self.events
    self.events = {}
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
