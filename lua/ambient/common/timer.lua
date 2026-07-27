--- it is just a fucking wrapper for uv.timer
--- fuck me...

local uv     = vim.loop or vim.uv
local result = require("ambient.common.result")

---@class Timer
---@field timer uv.uv_timer_t
---@field time_ms integer
---@field callback fun()?
---@field new fun(time_ms: integer, callback: fun()?): AmbientResult<Timer, TimerError>
---@field start fun(self: Timer): AmbientResult<nil, string>
---@field stop fun(self: Timer): AmbientResult<nil, string>
---@field close fun(self: Timer, callback: fun()?): AmbientResult<nil, string>

local M = {}

M.__index = M

---@enum TimerError
M.Error = {
    INTERNAL_INVALID_ARGUMENT = "The input Arguements are invalid, check time_ms and callback pls",
}

---@param time_ms integer
---@param callback fun()?
---@return AmbientResult<Timer, TimerError>
function M.new(time_ms, callback)
    -- check inputs
    if type(time_ms) ~= "number" then
        return result.err("time_ms must be a number")
    end

    if type(callback) ~= "nil" and type(callback) ~= "function" then
        return result.err("callback must be a function")
    end

    ---@type Timer
    local self = setmetatable({}, M)

    -- try to new an timer
    local val, err, err_type = uv.new_timer()
    if err or val == nil then
        return result.err(err_type .. ": " .. err)
    end

    self.timer    = val
    self.callback = callback
    self.time_ms  = time_ms;

    return result.ok(self)
end

---@param self Timer
---@return AmbientResult<nil, string>
function M:start()
    if not self.timer then
        return result.err("Timer not initailized")
    end

    local callback = self.callback
    if callback ~= nil then
        callback = vim.schedule_wrap(callback)
    end

    local ok, start_err = self.timer:start(self.time_ms, 0, callback)
    if not ok then
        return result.err(start_err)
    end

    return result.ok(nil)
end

---@param self Timer
---@return AmbientResult<nil, string>
function M:stop()
    if not self.timer then
        return result.err("Timer not initialized")
    end

    local ok, stop_err, err_name = self.timer:stop()
    if not ok then
        return result.err(err_name .. ": " .. stop_err)
    end

    return result.ok(nil)
end

---@param self Timer
---@param callback fun()?
---@return AmbientResult<nil, string>
function M:close(callback)
    if not self.timer then
        return result.err("Timer not initialized")
    end

    if callback ~= nil and type(callback) ~= "function" then
        return result.err("callback arg should be an function")
    end

    local ok, close_err = self.timer:close(callback)
    if not ok then
        return result.err(close_err)
    end

    return result.ok(nil)
end

---@enum TimerGetRestTimeError
M.TimerGetRestTimeError = {
    TIMER_NOT_INITIALIZED = 1,
    HAS_EXPIRED           = 2,
}
---@param self Timer
---@return AmbientResult<integer, TimerGetRestTimeError>
function M:getRestTimeMs()
    if not self.timer then
        return result.err(M.TimerGetRestTimeError.TIMER_NOT_INITIALIZED)
    end

    local remaining, err = self.timer:get_due_in()
    if err then
        return result.err(tostring(err))
    end

    if remaining <= 0 then
        return result.err(M.TimerGetRestTimeError.HAS_EXPIRED)
    end

    return result.ok(remaining)
end

return M

-- because they were killed by you
-- you cannot admit it.
-- run for your life
