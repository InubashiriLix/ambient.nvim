local result = require("ambient.result")

---@alias AmbientPlayListIdMap table<string, AmbientPlayList>

---@alias AmbientPlayListSelectorState
---| "NOT_READY"
---| "READY"
---| "ERROR"
---| "END"

---@alias AmbientPlayListSelectorError
---| "INVALID_STATE"
---| "INVALID_INDEX"
---| "INVALID_PATH"
---| "DUPLICATE_PLAYLIST"
---| "EMPTY_PLAYLIST"
---| "NO_PLAYLISTS"
---| "NO_CURRENT_PLAYLIST"


---@class AmbientPlayListSelectorUiItem
---@field index integer
---@field playlist AmbientPlayList

---@alias AmbientPlayListSelectedCallback fun(result: AmbientResult<AmbientPlayList, AmbientPlayListSelectorError>): nil

---@class AmbientPlayListSelector
---@field private m_state AmbientPlayListSelectorState
---@field private m_playlists AmbientPlayList[]
---@field private m_playlists_id_map AmbientPlayListIdMap
---@field private m_current_index? integer
---
---@field reset fun(self: AmbientPlayListSelector): nil
---@field setup fun(self: AmbientPlayListSelector): AmbientResult<nil, AmbientPlayListSelectorError>
---@field addPlayList fun(self: AmbientPlayListSelector, playlist: AmbientPlayList): AmbientResult<nil, AmbientPlayListSelectorError>
---@field setCurrentPlaylist fun(self: AmbientPlayListSelector, index: integer): AmbientResult<nil, AmbientPlayListSelectorError>
---@field getCurrentPlayList fun(self: AmbientPlayListSelector): AmbientResult<AmbientPlayList, AmbientPlayListSelectorError>
---@field getAllPlayListsIdMap fun(self: AmbientPlayListSelector): AmbientResult<AmbientPlayListIdMap, AmbientPlayListSelectorError>
---@field displaySelectorUi fun(self: AmbientPlayListSelector, on_select?: AmbientPlayListSelectedCallback): AmbientResult<nil, AmbientPlayListSelectorError>
local M = {
    m_state            = "NOT_READY",
    m_current_index    = nil,
    m_playlists        = {},
    m_playlists_id_map = {},
}

function M:reset()
    self.m_state            = "NOT_READY"
    self.m_current_index    = nil
    self.m_playlists        = {}
    self.m_playlists_id_map = {}
end

---@param path string
---@return AmbientResult<string, AmbientPlayListSelectorError>
local function parsePlayListName(path)
    local name = path:match("([^/\\]+)$")
    if name == nil or name == "" then
        return result.err("INVALID_PATH")
    end

    return result.ok(name)
end

---Declare that all playlists have been loaded and make the selector ready.
---@return AmbientResult<nil, AmbientPlayListSelectorError>
function M:setup()
    if self.m_state ~= "NOT_READY" then
        return result.err("INVALID_STATE")
    end

    if #self.m_playlists == 0 then
        return result.err("NO_PLAYLISTS")
    end

    for index, playlist in ipairs(self.m_playlists) do
        if not playlist:isEmpty() then
            self.m_current_index = index
            break
        end
    end

    if self.m_current_index == nil then
        return result.err("NO_PLAYLISTS")
    end

    self.m_state = "READY"

    return result.ok(nil)
end

---@param playlist AmbientPlayList
---@return AmbientResult<nil, AmbientPlayListSelectorError>
function M:addPlayList(playlist)
    if self.m_state ~= "NOT_READY" then
        return result.err("INVALID_STATE")
    end

    local parsed_name = parsePlayListName(playlist.abs_path)
    if not parsed_name.ok then
        return result.err(parsed_name.err)
    end

    if self.m_playlists_id_map[parsed_name.value] ~= nil then
        return result.err("DUPLICATE_PLAYLIST")
    end

    table.insert(self.m_playlists, playlist)
    self.m_playlists_id_map[parsed_name.value] = playlist

    return result.ok(nil)
end

---@param index integer
---@return AmbientResult<nil, AmbientPlayListSelectorError>
function M:setCurrentPlaylist(index)
    if self.m_state ~= "READY" then
        return result.err("INVALID_STATE")
    end

    if #self.m_playlists == 0 then
        return result.err("NO_PLAYLISTS")
    end

    if type(index) ~= "number"
        or index % 1 ~= 0
        or index < 1
        or index > #self.m_playlists then
        return result.err("INVALID_INDEX")
    end

    if self.m_playlists[index]:isEmpty() then
        return result.err("EMPTY_PLAYLIST")
    end

    self.m_current_index = index

    return result.ok(nil)
end

---@return AmbientResult<AmbientPlayList, AmbientPlayListSelectorError>
function M:getCurrentPlayList()
    if self.m_state ~= "READY" then
        return result.err("INVALID_STATE")
    end

    if self.m_current_index == nil then
        return result.err("NO_CURRENT_PLAYLIST")
    end

    local playlist = self.m_playlists[self.m_current_index]
    if playlist == nil then
        return result.err("INVALID_INDEX")
    end

    return result.ok(playlist)
end

---@return AmbientResult<AmbientPlayListIdMap, AmbientPlayListSelectorError>
function M:getAllPlayListsIdMap()
    if self.m_state ~= "READY" then
        return result.err("INVALID_STATE")
    end

    ---@type AmbientPlayListIdMap
    local id_map = {}
    for id, playlist in pairs(self.m_playlists_id_map) do
        id_map[id] = playlist
    end

    return result.ok(id_map)
end

---@param on_select? AmbientPlayListSelectedCallback
---@return AmbientResult<nil, AmbientPlayListSelectorError>
function M:displaySelectorUi(on_select)
    if self.m_state ~= "READY" then
        return result.err("INVALID_STATE")
    end

    if #self.m_playlists == 0 then
        return result.err("NO_PLAYLISTS")
    end

    ---@type AmbientPlayListSelectorUiItem[]
    local items = {}
    for index, playlist in ipairs(self.m_playlists) do
        items[index] = {
            index    = index,
            playlist = playlist,
        }
    end

    local current_index = self.m_current_index
    vim.ui.select(items, {
        prompt = "Select a playlist",
        kind   = "ambient_playlist_selector",

        ---@param item AmbientPlayListSelectorUiItem
        format_item = function(item)
            local marker   = item.index == current_index and ">" or " "
            local playlist = item.playlist
            return string.format("%s %s (%d tracks)", marker, playlist.name, #playlist.musics)
        end,
    }, function(choice)
        if choice == nil then
            return
        end

        local selected = self:setCurrentPlaylist(choice.index)

        if not selected.ok then
            if on_select ~= nil then
                on_select(result.err(selected.err))
            end
            return
        end

        if on_select ~= nil then
            on_select(result.ok(choice.playlist))
        end
    end)

    return result.ok(nil)
end

return M
