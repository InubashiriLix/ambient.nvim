--- thius module should do these:
---     - sacn the provided path provided by the user
---     - provide sorted result using api
---       - supporting: name / by size / by last modify time / by create time / random
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

---@enum SortDirection
M.SortDirection = {
    asc  = "asc",
    desc = "desc",
}
---@enum SortField
M.SortField     = {
    name        = "name",
    modify_time = "modify_time",
    create_time = "create_time",
    random      = "random",
}

local ordered_sort_fields = {
    M.SortField.name,
    M.SortField.create_time,
    M.SortField.modify_time,
    M.SortField.random,
}

local ordered_sort_directions = {
    M.SortDirection.asc,
    M.SortDirection.desc,
}

local sort_field_map = {
    [M.SortField.name]        = "name",
    [M.SortField.modify_time] = "modify_time_sec",
    [M.SortField.create_time] = "create_time_sec",
}

---@alias AmbientPlayListState
---| "NOT_READY"
---| "LOADING"
---| "DONE"
---| "PARTIAL_ERROR"
---| "FETAL_ERROR"

---@return { field: SortField, direction: SortDirection }[]
function M.getSortMethodTable()
    local ret = {}

    for _, field in ipairs(ordered_sort_fields) do
        if field == M.SortField.random then
            table.insert(ret, {
                field     = field,
                direction = M.SortDirection.asc,
            })
        else
            for _, direction in ipairs(ordered_sort_directions) do
                table.insert(ret, {
                    field     = field,
                    direction = direction,
                })
            end
        end
    end

    return ret
end

---@class AmbientSortedMusicItem
---@field position integer Position in this sorted snapshot.
---@field source_index integer Index in `AmbientPlayList.musics`.
---@field music AmbientMusic

---use iterator methods here. Noted that I prefer cursor mode than iterator one, cause' the future dev
---might need enough detail about the playlist. while the iterator mode is not enough for that...
---to be honest, I think I'm writing lua in java's style, but somehow it feels better...
---fuck me

---@class AmbientPlayList
---@field state AmbientPlayListState
---@field abs_path string
---@field name string
---@field musics AmbientMusic[]
---@field sorted_indices integer[]
---@field cursor integer
---@field sort_field SortField
---@field sort_direction SortDirection
---
---@field public isEmpty fun(self: AmbientPlayList): boolean
---@field public reload fun(self: AmbientPlayList): AmbientResult<nil, AmbientPlayListError>
---@field public getSortMethod fun(self: AmbientPlayList): SortField, SortDirection
---@field public setSortMethod fun(self: AmbientPlayList, field: SortField, direction: SortDirection)
---@field public sort fun(self: AmbientPlayList): nil it must success!
---@field public getSortedSnapshot fun(self: AmbientPlayList, sort_method: SortField, sort_direction: SortDirection): AmbientResult<AmbientSortedMusicItem[], AmbientPlayListError>
---
---@field public setCursor fun(self: AmbientPlayList, index: integer): AmbientResult<nil, AmbientPlayListError>
---@field public hasNext fun(self: AmbientPlayList): boolean
---@field public next fun(self: AmbientPlayList): AmbientMusic | nil
---@field public peekNext fun(self: AmbientPlayList): AmbientMusic | nil
---@field public hasPrev fun(self: AmbientPlayList): boolean
---@field public prev fun(self: AmbientPlayList): AmbientMusic | nil
---@field public peekPrev fun(self: AmbientPlayList): AmbientMusic | nil
---@field public getCurrent fun(self: AmbientPlayList): AmbientMusic | nil
---@field public reset fun(self: AmbientPlayList): nil

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
    sort_field      = sort_field or M.SortField.random
    sort_direction  = sort_direction or M.SortDirection.asc

    -- check path existence
    local stat = vim.uv.fs_stat(abs_path)
    if stat == nil then
        return result.err(M.Error.PATH_NOT_EXIST)
    elseif stat.type ~= "directory" then
        return result.err(M.Error.PATH_NOT_DIR)
    end

    -- parse other args
    if recursive_depth <= 0 then return result.err(M.Error.INVALID_ARGUMENT) end
    if sort_field ~= M.SortField.random and sort_field_map[sort_field] == nil then
        return result.err(M.Error.INVALID_ARGUMENT)
    end
    if sort_direction ~= M.SortDirection.asc
        and sort_direction ~= M.SortDirection.desc then
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
        state          = "NOT_READY",
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
            local indices = {}
            for i = 1, #self.musics do
                table.insert(indices, i)
            end

            if self.sort_field == M.SortField.random then
                for i = #indices, 2, -1 do
                    local j                = math.random(i)
                    indices[i], indices[j] = indices[j], indices[i]
                end
            else
                local field = sort_field_map[self.sort_field]
                local dir   = self.sort_direction
                table.sort(indices, function(a, b)
                    local va = self.musics[a][field]
                    local vb = self.musics[b][field]
                    if dir == M.SortDirection.asc then
                        return va < vb
                    else
                        return va > vb
                    end
                end)
            end

            self.sorted_indices = indices;
            self.cursor         = 1;
        end,

        setCursor = function(self, index)
            if type(index) ~= "number"
                or index % 1 ~= 0
                or index < 1
                or index > #self.sorted_indices then
                return result.err(M.Error.INVALID_ARGUMENT)
            end
            self.cursor = index
            return result.ok(nil)
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

        getSortedSnapshot = function(self, sort_method, sort_direction)
            local field = sort_field_map[sort_method]
            if sort_method ~= M.SortField.random and field == nil then
                return result.err(M.Error.INVALID_ARGUMENT)
            end

            if sort_direction ~= M.SortDirection.asc
                and sort_direction ~= M.SortDirection.desc then
                return result.err(M.Error.INVALID_ARGUMENT)
            end

            local indices = {}
            for i = 1, #self.musics do
                table.insert(indices, i)
            end

            if sort_method == M.SortField.random then
                for i = #indices, 2, -1 do
                    local j                = math.random(i)
                    indices[i], indices[j] = indices[j], indices[i]
                end
            else
                ---@cast field string
                table.sort(indices, function(a, b)
                    local va = self.musics[a][field]
                    local vb = self.musics[b][field]

                    if va == vb then
                        return a < b
                    end

                    if sort_direction == M.SortDirection.asc then
                        return va < vb
                    end

                    return va > vb
                end)
            end

            ---@type AmbientSortedMusicItem[]
            local snapshot = {}
            for position, source_index in ipairs(indices) do
                table.insert(snapshot, {
                    position     = position,
                    source_index = source_index,
                    music        = self.musics[source_index],
                })
            end

            return result.ok(snapshot)
        end,
    }

    setmetatable(obj, M)

    obj:sort()

    return result.ok(obj);
end

M.__index = M

return M
