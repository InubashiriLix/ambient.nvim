local M = {}

local result = require("ambient.result")

---@enum AmbientScheduleError
M.Error = {}

---@enum ScheduleState
M.State = {
    -- paused
    PAUSED   = "PAUSED",
    -- playing
    PLAYING  = "PLAYING",
    -- stopped
    STOPPED  = "STOPPED",
    -- waiting interval
    INTERVAL = "INTERVAL",
    -- next music
    NEXT     = "NEXT",
}

function M:setup() end
function M:get() end
function M:is_ready() end
function M:get_error_message() end

return M
