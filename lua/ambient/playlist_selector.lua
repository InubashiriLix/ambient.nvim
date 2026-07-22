---@author [InubashiriLix](https://github.com/InubashiriLix)
---@license [DBAD](https://github.com/philsturgeon/dbad)

local result          = require("ambient.result")
local playlist_module = require("ambient.playlist")

---@type table<SortField, string>
local sort_field_labels = {
    [playlist_module.SortField.name]        = "Name",
    [playlist_module.SortField.create_time] = "Created",
    [playlist_module.SortField.modify_time] = "Modified",
    [playlist_module.SortField.random]      = "Random",
}

---@type table<SortDirection, string>
local sort_direction_labels = {
    [playlist_module.SortDirection.asc]  = "ascending",
    [playlist_module.SortDirection.desc] = "descending",
}

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
---| "INVALID_SORT"


---@class AmbientPlayListSelectorUiItem
---@field index integer
---@field playlist AmbientPlayList

---@class AmbientMusicSortUiItem
---@field field SortField
---@field direction SortDirection

---@alias AmbientPlayListSelectedCallback fun(result: AmbientResult<AmbientPlayList, AmbientPlayListSelectorError>): nil
---@alias AmbientMusicSelectedCallback fun(result: AmbientResult<AmbientMusic, AmbientPlayListSelectorError>): nil

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
---@field getCurrentPlayListValue fun(self: AmbientPlayListSelector): AmbientPlayList?
---@field getAllPlayListsIdMap fun(self: AmbientPlayListSelector): AmbientResult<AmbientPlayListIdMap, AmbientPlayListSelectorError>
---@field displayPlayListSelectUi fun(self: AmbientPlayListSelector, on_select?: AmbientPlayListSelectedCallback): AmbientResult<nil, AmbientPlayListSelectorError>
---@field displayMusicItemSelectUi fun(self: AmbientPlayListSelector, on_select?: AmbientMusicSelectedCallback): AmbientResult<nil, AmbientPlayListSelectorError>
---@field displayCurrentPlayListMusicItemSelectUi fun(self: AmbientPlayListSelector, current_playlist: AmbientPlayList, on_select?: AmbientMusicSelectedCallback, current_music?: AmbientMusic): AmbientResult<nil, AmbientPlayListSelectorError>
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

---Internal read for callers that already enforce the selector's ready invariant.
---@return AmbientPlayList?
function M:getCurrentPlayListValue()
    if self.m_state ~= "READY" or self.m_current_index == nil then
        return nil
    end

    return self.m_playlists[self.m_current_index]
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
function M:displayPlayListSelectUi(on_select)
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

---@param playlist AmbientPlayList
---@param music_items AmbientSortedMusicItem[]
---@param on_select? AmbientMusicSelectedCallback
---@param kind? string
---@param initial_index? integer
---@return AmbientResult<nil, AmbientPlayListSelectorError>
local function displayMusicChoices(playlist, music_items, on_select, kind, initial_index)
    if #music_items == 0 then
        return result.err("EMPTY_PLAYLIST")
    end

    local select_opts = {
        prompt = "Select music",
        kind   = kind or "ambient_music_selector",

        ---@param item AmbientSortedMusicItem
        format_item = function(item)
            return string.format("%s", item.music.name)
        end,
    }

    if initial_index ~= nil then
        -- `initial_index` is a provider-neutral hint. Snacks currently needs an
        -- adapter to move its list cursor while preserving the item order.
        select_opts.initial_index = initial_index
        select_opts.snacks        = {
            on_show = function(picker)
                picker.list:view(initial_index)
            end,
        }
    end

    vim.ui.select(music_items, select_opts, function(music_choice)
        ---@cast music_choice AmbientSortedMusicItem?
        if music_choice == nil then
            return
        end

        if playlist.musics[music_choice.source_index] ~= music_choice.music then
            if on_select ~= nil then
                on_select(result.err("INVALID_INDEX"))
            end
            return
        end

        ---@type integer?
        local cursor
        for position, source_index in ipairs(playlist.sorted_indices) do
            if source_index == music_choice.source_index then
                cursor = position
                break
            end
        end

        if cursor == nil then
            if on_select ~= nil then
                on_select(result.err("INVALID_INDEX"))
            end
            return
        end

        ---@cast cursor integer
        local selected = playlist:setCursor(cursor)
        if not selected.ok then
            if on_select ~= nil then
                on_select(result.err("INVALID_INDEX"))
            end
            return
        end

        if on_select ~= nil then
            on_select(result.ok(music_choice.music))
        end
    end)

    return result.ok(nil)
end

---Prompt for a temporary display sort, then prompt for a music item.
---@param on_select? AmbientMusicSelectedCallback
---@return AmbientResult<nil, AmbientPlayListSelectorError>
function M:displayMusicItemSelectUi(on_select)
    if self.m_state ~= "READY" then
        return result.err("INVALID_STATE")
    end

    local playlist_result = self:getCurrentPlayList()
    if not playlist_result.ok then
        return result.err(playlist_result.err)
    end

    local playlist = playlist_result.value
    ---@cast playlist AmbientPlayList

    ---@type AmbientMusicSortUiItem[]
    local sort_items                                 = playlist_module.getSortMethodTable()
    local current_sort_field, current_sort_direction = playlist:getSortMethod()

    vim.ui.select(sort_items, {
        prompt = "Sort music",
        kind   = "ambient_music_sort_selector",

        ---@param item AmbientMusicSortUiItem
        format_item = function(item)
            local is_current = item.field == current_sort_field
                and (item.field == playlist_module.SortField.random
                    or item.direction == current_sort_direction)

            local label = sort_field_labels[item.field]
            if item.field ~= playlist_module.SortField.random then
                label = string.format("%s %s", label, sort_direction_labels[item.direction])
            end

            return string.format("%s %s", label, is_current and "(current mode)" or " ")
        end,
    }, function(sort_choice)
        ---@cast sort_choice AmbientMusicSortUiItem?
        if sort_choice == nil then
            return
        end

        local snapshot = playlist:getSortedSnapshot(sort_choice.field, sort_choice.direction)
        if not snapshot.ok then
            if on_select ~= nil then
                on_select(result.err("INVALID_SORT"))
            end
            return
        end

        local music_items = snapshot.value
        ---@cast music_items AmbientSortedMusicItem[]
        local displayed   = displayMusicChoices(playlist, music_items, on_select)
        if not displayed.ok and on_select ~= nil then
            on_select(result.err(displayed.err))
        end
    end)

    return result.ok(nil)
end

---Display the current playlist in playback order and focus its current item.
---@param current_playlist AmbientPlayList
---@param on_select? AmbientMusicSelectedCallback
---@param current_music? AmbientMusic
---@return AmbientResult<nil, AmbientPlayListSelectorError>
function M:displayCurrentPlayListMusicItemSelectUi(current_playlist, on_select, current_music)
    if self.m_state ~= "READY" then
        return result.err("INVALID_STATE")
    end

    if current_playlist == nil then
        return result.err("NO_CURRENT_PLAYLIST")
    end

    if current_playlist:isEmpty() then
        return result.err("EMPTY_PLAYLIST")
    end

    local music_count   = #current_playlist.sorted_indices
    local initial_index = current_playlist.cursor
    if type(initial_index) ~= "number"
        or initial_index % 1 ~= 0
        or initial_index < 1
        or initial_index > music_count then
        return result.err("INVALID_INDEX")
    end

    ---@type AmbientSortedMusicItem[]
    local music_items = {}
    for playback_position = 1, music_count do
        local source_index = current_playlist.sorted_indices[playback_position]
        local music_item   = current_playlist.musics[source_index]
        if music_item == nil then
            return result.err("INVALID_INDEX")
        end

        table.insert(music_items, {
            position     = playback_position,
            source_index = source_index,
            music        = music_item,
        })

        if current_music ~= nil and music_item == current_music then
            initial_index = playback_position
        end
    end

    return displayMusicChoices(
        current_playlist,
        music_items,
        on_select,
        "ambient_current_playlist_music_selector",
        initial_index
    )
end

return M
