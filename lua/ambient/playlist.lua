--- thius module should do these:
---     - sacn the provided path provided by the user
---     - provide sorted result using api
---       - supporting: name / by duration / by size / by last modify time / by create time / random
---     - provide reload / refresh api to scan again and update the result

local M = {}

local result = require("ambient.result")
local music  = require("ambient.music")

---@enum AmbientPlayListError
M.Error = {
    PATH_NOT_EXIST = "PATH_NOT_EXIST",
    PATH_NOT_DIR   = "PATH_NOT_DIR",
    SCAN_FAILED    = "SCAN_FAILED",

    INVALID_ARGUMENT = "INVALID_ARGUMENT",
}

---@alias SortDirection "asc" | "desc"
---@alias SortField
---| "name"
---| "duration"
---| "modify_time"
---| "create_time"
---| "random"


---use iterator methods here. Noted that I prefer cursor mode than iterator one, cause' the future dev
---might need enough detail about the playlist. while the iterator mode is not enough for that...
---to be honest, I think I'm writing lua in java's style, but somehow it feels better...
---fuck me

---@class AmbientPlayList
---@field abs_path string
---@field name string
---@field musics AmbientMusic[]
---@field sorted_indices integer[]
---@field cursor integer
---@field sort_field SortField
---@field sort_direction SortDirection
---
---@field isEmpty fun(self: AmbientPlayList): boolean
---@field reload fun(self: AmbientPlayList): AmbientResult<nil, AmbientPlayListError>
---@field getSortMethod fun(self: AmbientPlayList): SortField, SortDirection
---@field setSortMethod fun(self: AmbientPlayList, field: SortField, direction: SortDirection)
---@field sort fun(self: AmbientPlayList): nil it must success!
---
---@field hasNext fun(self: AmbientPlayList): boolean
---@field next fun(self: AmbientPlayList): AmbientMusic | nil
---@field peekNext fun(self: AmbientPlayList): AmbientMusic | nil
---@field hasPrev fun(self: AmbientPlayList): boolean
---@field prev fun(self: AmbientPlayList): AmbientMusic | nil
---@field peekPrev fun(self: AmbientPlayList): AmbientMusic | nil
---@field getCurrent fun(self: AmbientPlayList): AmbientMusic | nil
---@field reset fun(self: AmbientPlayList): nil

---@param abs_path string
---@param ext string[]
---@param recursive_depth integer
---@return AmbientResult<AmbientPlayList, AmbientPlayListError>
local function scanDir(abs_path, ext, recursive_depth)
    ---@type string[]
    local abs_path_list = {}
    -- scan it with depth
    local ext_set       = {}
    for _, e in ipairs(ext) do
        ext_set[tostring(e):lower():gsub("^%.", "")] = true
    end

    local function scan(dir, depth)
        if depth <= 0 then return result.ok(nil) end

        local req = vim.uv.fs_scandir(dir)
        if not req then return result.err(M.Error.SCAN_FAILED) end

        while true do
            local name, type = vim.uv.fs_scandir_next(req)
            if not name then break end
            local full_path = dir .. "/" .. name
            if type == "file" then
                local file_ext = name:match("%.([^%.]+)$")
                file_ext       = file_ext and file_ext:lower()
                if file_ext and ext_set[file_ext] then
                    table.insert(abs_path_list, full_path)
                end
            elseif type == "directory" then
                local child_result = scan(full_path, depth - 1)
                if not child_result.ok then
                    return child_result
                end
            end
        end

        return result.ok(nil)
    end

    local scan_result = scan(abs_path, recursive_depth)
    if not scan_result.ok then
        return scan_result
    end

    return result.ok(abs_path_list)
end



---@param abs_path string
---@param ext string[]
---@param recursive_depth integer | nil
---@param sort_field SortField | nil
---@param sort_direction SortDirection | nil
---@return AmbientResult<AmbientPlayList, AmbientPlayListError>
function M:new(abs_path, ext, recursive_depth, sort_field, sort_direction)
    recursive_depth = recursive_depth or 1
    ext             = ext or { "mp3", "ogg", "flac", "wav" }
    sort_field      = sort_field or "random"
    sort_direction  = sort_direction or "asc"

    -- check path existence
    local stat = vim.uv.fs_stat(abs_path)
    if stat == nil then
        return result.err(M.Error.PATH_NOT_EXIST)
    elseif stat.type ~= "directory" then
        return result.err(M.Error.PATH_NOT_DIR)
    end

    -- parse other args
    if recursive_depth <= 0 then return result.err(M.Error.INVALID_ARGUMENT) end
    if sort_field ~= "name"
        and sort_field ~= "duration"
        and sort_field ~= "modify_time"
        and sort_field ~= "create_time"
        and sort_field ~= "random" then
        return result.err(M.Error.INVALID_ARGUMENT)
    end
    if sort_direction ~= "asc" and sort_direction ~= "desc" then
        return result.err(M.Error.INVALID_ARGUMENT)
    end

    -- scan the diretory first
    local scan_result = scanDir(abs_path, ext, recursive_depth)
    if not scan_result.ok then
        return result.err(M.Error.SCAN_FAILED)
    end
    -- load all music items
    ---@type AmbientMusic[]
    local musics = {}
    for _, music_path in ipairs(scan_result.value) do
        local r = music:new(music_path)
        if not r.ok then
            return result.err(M.Error.SCAN_FAILED)
        else
            table.insert(musics, r.value)
        end
    end

    ---@type AmbientPlayList
    local obj = {
        abs_path       = abs_path,
        name           = abs_path:match("([^/]+)$"),
        musics         = musics,
        sorted_indices = {},
        cursor         = 1,
        sort_field     = sort_field,
        sort_direction = sort_direction,

        -- NOTE: these methods are diagnosed with self shadowing, not good. next refactor aim.
        isEmpty = function(self)
            return #self.musics == 0
        end,

        reload = function(self)
            -- we shall scan the directory again, and update the music list
            local scan_result = scanDir(self.abs_path, ext, recursive_depth)
            if not scan_result.ok then
                return result.err(M.Error.SCAN_FAILED)
            end
            ---@type AmbientMusic[]
            local musics = {}
            for _, music_path in ipairs(scan_result.value) do
                local r = music:new(music_path)
                if not r.ok then
                    return result.err(M.Error.SCAN_FAILED)
                else
                    table.insert(musics, r.value)
                end
            end
            self.musics = musics
            -- sort again
            self:sort()

            return result.ok(nil)
        end,

        getSortMethod = function(self)
            return self.sort_field, self.sort_direction
        end,

        setSortMethod = function(self, field, direction)
            self.sort_field     = field;
            self.sort_direction = direction;
            self:sort()
        end,

        sort = function(self)
            local field_map = {
                name        = "name",
                duration    = "duration_ms",
                modify_time = "modify_time_sec",
                create_time = "create_time_sec",
            }

            local indices = {}
            for i = 1, #self.musics do
                table.insert(indices, i)
            end

            if self.sort_field == "random" then
                for i = #indices, 2, -1 do
                    local j                = math.random(i)
                    indices[i], indices[j] = indices[j], indices[i]
                end
            else
                local field = field_map[self.sort_field]
                local dir   = self.sort_direction
                table.sort(indices, function(a, b)
                    local va = self.musics[a][field]
                    local vb = self.musics[b][field]
                    if dir == "asc" then
                        return va < vb
                    else
                        return va > vb
                    end
                end)
            end

            self.sorted_indices = indices;
            self.cursor         = 1;
        end,

        hasNext = function(self)
            return self.cursor < #self.sorted_indices
        end,

        hasPrev = function(self)
            return self.cursor > 1
        end,

        next = function(self)
            if not self:hasNext() then return nil end
            self.cursor = self.cursor + 1
            return self:getCurrent()
        end,

        prev = function(self)
            if not self:hasPrev() then return nil end
            self.cursor = self.cursor - 1
            return self:getCurrent()
        end,

        peekNext = function(self)
            if not self:hasNext() then return nil end
            return self.musics[self.sorted_indices[self.cursor + 1]]
        end,

        peekPrev = function(self)
            if not self:hasPrev() then return nil end
            return self.musics[self.sorted_indices[self.cursor - 1]]
        end,

        getCurrent = function(self)
            return self.musics[self.sorted_indices[self.cursor]] or nil
        end,

        reset = function(self)
            self.cursor = 1
        end,
    }

    setmetatable(obj, M)

    obj:sort()

    return result.ok(obj);
end

M.__index = M

return M
