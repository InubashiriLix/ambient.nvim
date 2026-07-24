local M = {}


local result = require("ambient.result")

---@class AmbientCoverPicture
---@field path string
---@field mime string
---@field width integer|nil
---@field height integer|nil
---@field source "embedded"|"external"
---@field temporary boolean

---@class AmbientMusic
---@field name string
---@field abs_path string
---@field modify_time_sec integer
---@field change_time_sec integer
---@field create_time_sec integer
---@field duration_ms integer
---@field cursor_time_ms integer
---@field proc_percentage integer
---@field album_name string|nil
---@field cover_pic AmbientCoverPicture|nil
---@field artist_name string[]|string|nil
---@field cached_buf string|nil
---@field state AmbientMusicState
---
---@field releaseCoverPic fun(self: AmbientMusic): AmbientResult<nil, AmbientMusicError>
---@field preload fun(self: AmbientMusic): AmbientResult<nil, AmbientMusicError>
---@field releasePreload fun(self: AmbientMusic): AmbientResult<nil, AmbientMusicError>
---
---note: these setgetters must success.
---@field loadDurationAsync fun(self: AmbientMusic): nil
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

---@enum AmbientMusicState
M.State = {
    NOT_READY    = "NOT_READY",
    INITIALIZING = "INITIALIZING",
    DONE         = "DONE",
    ERROR        = "ERROR",
}

---@param abs_path string
---@return AmbientResult<AmbientMusic, AmbientMusicError>
function M:new(abs_path)
    -- check existence of file
    local file = io.open(abs_path, "r")
    if not file then
        return result.err(self.Error.FILE_NOT_REACHABLE)
    end
    file:close()

    -- get name
    local name                                  = abs_path:match("([^/]+)%.[^%.]+$") or
        abs_path:match("([^/]+)$")
    local modify_time, create_time, change_time = 0, 0, 0
    local stat                                  = vim.uv.fs_stat(abs_path)
    if stat then
        modify_time = stat.mtime and stat.mtime.sec or 0
        change_time = stat.ctime and stat.ctime.sec or 0
        create_time = stat.birthtime and stat.birthtime.sec or 0
    end

    ---@type AmbientMusic
    local obj = {
        name            = name,
        abs_path        = abs_path,
        modify_time_sec = modify_time,
        change_time_sec = change_time,
        create_time_sec = create_time,
        duration_ms     = 0,
        cursor_time_ms  = 0,
        proc_percentage = 0,
        album_name      = nil,
        cover_pic       = nil,
        artist_name     = nil,
        cached_buf      = nil,
        state           = self.State.NOT_READY,

        releaseCoverPic = function(self)
            local cover    = self.cover_pic
            self.cover_pic = nil

            if cover ~= nil
                and cover.temporary
                and type(cover.path) == "string"
                and cover.path ~= ""
            then
                if vim.fn ~= nil and vim.fn.delete ~= nil then
                    pcall(vim.fn.delete, cover.path)
                elseif vim.uv ~= nil and vim.uv.fs_unlink ~= nil then
                    pcall(vim.uv.fs_unlink, cover.path)
                end
            end

            return result.ok(nil)
        end,

        -- prelaod and release cache mem
        ---@deprecated this function is never used. and it may provide better load performace with cost of brain cells (lots of status to deal)
        preload = function(self)
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
            self.cursor_time_ms = time_ms
            if self.duration_ms <= 0 then
                self.proc_percentage = 0
                return
            end
            self.proc_percentage = math.floor((self.cursor_time_ms / self.duration_ms) * 100)
        end,

        getProcPercentage = function(self)
            return self.proc_percentage
        end,

        loadDurationAsync = function(self)
            if self.state == M.State.INITIALIZING or self.state == M.State.DONE then
                return
            end

            if vim.fn.executable("ffprobe") == 0 or vim.system == nil then
                self.duration_ms = 0
                self.state       = M.State.ERROR
                return
            end

            local cmd  = {
                "ffprobe",
                "-v",
                "error",
                "-show_entries",
                "format=duration",
                "-of",
                "default=noprint_wrappers=1:nokey=1",
                self.abs_path,
            }
            self.state = M.State.INITIALIZING

            local started = pcall(
                vim.system,
                cmd,
                { text = true },
                vim.schedule_wrap(function(completed)
                    local output  = completed.stdout
                    local seconds = output and tonumber(vim.trim(output))

                    if completed.code ~= 0 or seconds == nil then
                        self.duration_ms = 0
                        self.state       = M.State.ERROR
                        return
                    end

                    self.duration_ms = math.floor(seconds * 1000)
                    self.state       = M.State.DONE
                end)
            )

            if not started then
                self.duration_ms = 0
                self.state       = M.State.ERROR
            end
        end,
    }

    setmetatable(obj, M)

    return result.ok(obj)
end

M.__index = M

return M
