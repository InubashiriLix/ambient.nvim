local M = {}


local result = require("ambient.result")

---@class AmbientMusic
---@field name string
---@field abs_path string
---@field modify_time_sec integer
---@field change_time_sec integer
---@field create_time_sec integer
---@field duration_ms integer
---@field cursor_time_ms integer
---@field proc_percentage integer
---@field cached_buf string|nil
---
---@field preload fun(self: AmbientMusic): AmbientResult<nil, AmbientMusicError>
---@field releasePreload fun(self: AmbientMusic): AmbientResult<nil, AmbientMusicError>
---
---note: these setgetters must success.
---@field getName fun(self: AmbientMusic): string
---@field getModifyTime fun(self: AmbientMusic): integer
---@field getChangeTime fun(self: AmbientMusic): integer
---@field getCreateTime fun(self: AmbientMusic): integer
---@field getDuration fun(self: AmbientMusic): integer
---@field getCursorTime fun(self: AmbientMusic): integer
---@field setCursorTime fun(self: AmbientMusic, time_ms: integer): nil
---@field getProcPercentage fun(self: AmbientMusic): integer

---@enum AmbientMusicError
M.Error = {
    FILE_NOT_REACHABLE    = "FILE_NOT_REACHABLE",
    DURATION_PARSE_FAILED = "DURATION_PARSE_FAILED",
}

local function getDuration(abs_path)
    -- TODO: remember to check the ffprobe command is available in the system
    local cmd = string.format(
        'ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 "%s"',
        abs_path)

    local handle = io.popen(cmd)
    if not handle then
        return nil
    end

    local output = handle:read("*a")
    handle:close()

    local seconds = tonumber(output)
    if not seconds then
        return nil
    end
    return math.floor(seconds * 1000)
end

---@param abs_path string
---@return AmbientResult<AmbientMusic, AmbientMusicError>
function M.new(abs_path)
    -- check existence of file
    local file = io.open(abs_path, "r")
    if not file then
        return result.err(self.Error.FILE_NOT_REACHABLE)
    end
    -- get name
    local name        = abs_path:match("([^/]+)%.[^%.]+$")
    -- get duration_ms
    local duration_ms = getDuration(abs_path)
    if duration_ms == nil then
        return result.err(self.Error.DURATION_PARSE_FAILED)
    end

    local modify_time, create_time, change_time
    local stat = vim.uv.fs_stat(abs_path)
    if stat then
        modify_time = stat.mtime.sec
        change_time = stat.ctime.sec
        create_time = stat.birthtime.sec
    end

    ---@type AmbientMusic
    local obj = {
        name            = name,
        abs_path        = abs_path,
        modify_time_sec = modify_time,
        change_time_sec = change_time,
        create_time_sec = create_time,
        duration_ms     = duration_ms,
        cursor_time_ms  = 0,
        proc_percentage = 0,
        cached_buf      = nil,

        -- prelaod and release cache mem
        preload        = function(self)
            ---@type AmbientMusic
            local music = self
            vim.uv.fs_open(music.abs_path, "r", 438, function(open_err, fd)
                if open_err then
                    return
                end
                vim.uv.fs_fstat(fd, function(stat_err, stat)
                    if stat_err then
                        return
                    end
                    vim.uv.fs_read(fd, stat.size, 0, function(read_err, data)
                        if read_err or not data then
                            return
                        end
                        music.cached_buf = data
                        vim.uv.fs_close(fd, function() end)
                    end)
                end)
            end)
            return result.ok(nil)
        end,
        releasePreload = function(self)
            -- for empty cache, it also works, so no check needed
            self.cached_buf = nil
            return result.ok(nil)
        end,

        getName = function(self)
            return self.name
        end,

        getModifyTime = function(self)
            return self.modify_time_sec
        end,

        getChangeTime = function(self)
            return self.change_time_sec
        end,

        getCreateTime = function(self)
            return self.create_time_sec
        end,

        getDuration = function(self)
            return self.duration_ms
        end,

        getCursorTime = function(self)
            return self.cursor_time_ms
        end,

        setCursorTime = function(self, time_ms)
            self.cursor_time_ms  = time_ms
            self.proc_percentage = math.floor((self.cursor_time_ms / self.duration_ms) * 100)
        end,

        getProcPercentage = function(self)
            return self.proc_percentage
        end,
    }

    setmetatable(obj, M)

    return result.ok(obj)
end

M.__index = M

return M
